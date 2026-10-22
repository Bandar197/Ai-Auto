import 'dart:async';

import '../errors.dart';
import '../transport/obd_transport.dart';
import 'elm_response.dart';

export 'elm_response.dart';

/// Serial ELM327 command layer: one command in flight, `cmd\r` out, read until
/// the `>` prompt, per-command timeout, response cleaning and error mapping.
///
/// Safety: only read-only OBD services (01, 02, 03, 07, 09, 0A) and AT
/// commands are accepted by [send]. Service 04 (clear DTCs) is only reachable
/// through [sendClearDtcs], which the client gates behind server approval.
class Elm327 {
  Elm327(
    this.transport, {
    this.defaultTimeout = const Duration(milliseconds: 2500),
    this.searchTimeout = const Duration(seconds: 10),
  });

  final ObdTransport transport;
  final Duration defaultTimeout;
  final Duration searchTimeout;

  static const Set<String> readOnlyServices = {'01', '02', '03', '07', '09', '0A'};

  final StringBuffer _buffer = StringBuffer();
  StreamSubscription<String>? _sub;
  /// Completes with true on `>` and false when the link closes.
  Completer<bool>? _prompt;
  Future<void> _tail = Future<void>.value();
  bool _closed = true;
  bool _staleAfterTimeout = false;
  int consecutiveTimeouts = 0;

  /// Fires once when the transport stream ends (link lost).
  final StreamController<void> _lost = StreamController<void>.broadcast();
  Stream<void> get onTransportLost => _lost.stream;

  /// Every command/response pair (for logs & debugging screens).
  final StreamController<ElmResponse> _log = StreamController<ElmResponse>.broadcast();
  Stream<ElmResponse> get log => _log.stream;

  bool get isOpen => !_closed;

  /// Attach to an already connected transport.
  void attach() {
    _sub?.cancel();
    _buffer.clear();
    _closed = false;
    _sub = transport.incoming.listen(
      (chunk) {
        _buffer.write(chunk);
        if (chunk.contains('>')) {
          final p = _prompt;
          if (p != null && !p.isCompleted) p.complete(true);
        }
      },
      onError: (Object _) => _markClosed(),
      onDone: _markClosed,
    );
  }

  void _markClosed() {
    if (_closed) return;
    _closed = true;
    final p = _prompt;
    if (p != null && !p.isCompleted) p.complete(false);
    if (!_lost.isClosed) _lost.add(null);
  }

  static String normalize(String cmd) => cmd.replaceAll(' ', '').toUpperCase();

  /// Sends an AT command or a read-only OBD request.
  Future<ElmResponse> send(String command, {Duration? timeout}) {
    final c = normalize(command);
    if (!c.startsWith('AT')) {
      final service = c.length >= 2 ? c.substring(0, 2) : c;
      if (!readOnlyServices.contains(service)) {
        throw PolicyViolationException('service $service is not allowed through send()');
      }
    }
    return _enqueue(c, timeout ?? defaultTimeout);
  }

  /// Service 04. Call only from the approval-gated client path.
  Future<ElmResponse> sendClearDtcs() => _enqueue('04', const Duration(seconds: 5));

  Future<ElmResponse> _enqueue(String command, Duration timeout) {
    final result = Completer<ElmResponse>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await _execute(command, timeout));
      } on Object catch (e, st) {
        result.completeError(e, st);
      }
    });
    return result.future;
  }

  Future<ElmResponse> _execute(String command, Duration timeout) async {
    final sw = Stopwatch()..start();
    if (_closed) {
      return ElmResponse(
          command: command, raw: '', lines: const [], elapsed: sw.elapsed, error: ElmErrorKind.transportClosed);
    }
    if (_staleAfterTimeout) {
      // A late prompt from the timed-out command may still arrive: drain it.
      if (!_buffer.toString().contains('>')) {
        final c = Completer<bool>();
        _prompt = c;
        try {
          await c.future.timeout(const Duration(milliseconds: 300));
        } on TimeoutException catch (_) {}
      }
      _staleAfterTimeout = false;
    }
    _buffer.clear();
    final prompt = Completer<bool>();
    _prompt = prompt;
    try {
      await transport.write('$command\r');
    } on TransportException {
      _markClosed();
      return ElmResponse(
          command: command, raw: '', lines: const [], elapsed: sw.elapsed, error: ElmErrorKind.transportClosed);
    }
    try {
      if (!_buffer.toString().contains('>')) {
        final gotPrompt = await prompt.future.timeout(timeout);
        if (!gotPrompt) throw TransportException('adapter link closed', code: 'socket_closed');
      }
    } on TimeoutException {
      consecutiveTimeouts++;
      _staleAfterTimeout = true;
      final r = ElmResponse(
        command: command,
        raw: _buffer.toString(),
        lines: const [],
        elapsed: sw.elapsed,
        error: ElmErrorKind.timeout,
      );
      _emit(r);
      return r;
    } on TransportException {
      final r = ElmResponse(
          command: command, raw: _buffer.toString(), lines: const [], elapsed: sw.elapsed, error: ElmErrorKind.transportClosed);
      _emit(r);
      return r;
    }
    consecutiveTimeouts = 0;
    final text = _buffer.toString();
    final cut = text.indexOf('>');
    final raw = cut >= 0 ? text.substring(0, cut) : text;
    _buffer.clear();
    final r = parseResponse(command, raw, sw.elapsed);
    _emit(r);
    return r;
  }

  void _emit(ElmResponse r) {
    if (!_log.isClosed) _log.add(r);
  }

  /// Cleans a raw response (pure function; unit tested).
  static ElmResponse parseResponse(String command, String raw, [Duration elapsed = Duration.zero]) {
    final cmd = normalize(command);
    final lines = <String>[];
    var searched = false;
    for (var line in raw.replaceAll('\x00', '').split(RegExp(r'[\r\n]+'))) {
      line = line.trim();
      if (line.isEmpty || line == '>') continue;
      final upper = line.toUpperCase();
      if (normalize(upper) == cmd) continue; // echo
      if (upper.startsWith('SEARCHING')) {
        searched = true;
        continue;
      }
      if (upper.startsWith('BUS INIT') && !upper.contains('ERROR')) {
        // "BUS INIT: ...OK" or "BUS INIT: ..." (OK may arrive on its own line)
        continue;
      }
      if (upper == 'OK' && lines.isEmpty && !cmd.startsWith('AT')) continue; // tail of BUS INIT
      lines.add(line);
    }
    ElmErrorKind? error;
    String? errorLine;
    final data = <String>[];
    for (final l in lines) {
      final kind = classifyElmLine(l);
      if (kind == null) {
        data.add(l);
      } else {
        error ??= kind;
        errorLine ??= l;
      }
    }
    // Partial success (some ECUs answered, one line flagged) keeps the data.
    if (data.isNotEmpty && error != null && error != ElmErrorKind.unknownCommand) {
      return ElmResponse(command: cmd, raw: raw, lines: data, elapsed: elapsed, searched: searched, errorLine: errorLine);
    }
    if (error != null) {
      return ElmResponse(
          command: cmd, raw: raw, lines: const [], elapsed: elapsed, error: error, errorLine: errorLine, searched: searched);
    }
    return ElmResponse(command: cmd, raw: raw, lines: data, elapsed: elapsed, searched: searched);
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    _markClosed();
  }
}
