import 'dart:async';

import '../elm327/elm327.dart';

/// One raw adapter message, kept exactly as sent/received (recording.v2 `tx_rx_frames`).
class TxRxFrame {
  const TxRxFrame({required this.tMs, required this.dir, required this.data, this.canId, this.durationMs, this.timeout});

  factory TxRxFrame.fromJson(Map<String, dynamic> j) => TxRxFrame(
        tMs: (j['t_ms'] as num).toInt(),
        dir: j['dir'] as String,
        data: j['data'] as String? ?? '',
        canId: j['can_id'] as String?,
        durationMs: (j['duration_ms'] as num?)?.toInt(),
        timeout: j['timeout'] as bool?,
      );

  final int tMs;

  /// 'tx' (app → adapter) or 'rx' (adapter → app).
  final String dir;

  /// Unmodified text. RX keeps the adapter's line breaks.
  final String data;

  /// Only set when known for certain; never guessed from the payload.
  final String? canId;

  /// RX: time from sending the command to the prompt (or to the timeout).
  final int? durationMs;

  /// RX: the adapter did not answer within the timeout.
  final bool? timeout;

  Map<String, dynamic> toJson() => {
        't_ms': tMs,
        'dir': dir,
        'data': data,
        'can_id': ?canId,
        'duration_ms': ?durationMs,
        'timeout': ?timeout,
      };
}

/// Captures every command/response pair from [Elm327.log] as TX/RX frames with
/// millisecond timing relative to [startedAt]. Keeps at most [maxFrames]; when the
/// cap is hit, capture stops and [truncated] is set (never silently dropped).
class TrafficTap {
  TrafficTap({required this.startedAt, this.maxFrames = 20000, DateTime Function()? now, this.onFrame})
      : _now = now ?? (() => DateTime.now().toUtc());

  final DateTime startedAt;
  final int maxFrames;
  final DateTime Function() _now;

  /// Called for each captured frame (e.g. to append it to a durable journal).
  final void Function(TxRxFrame frame)? onFrame;

  final List<TxRxFrame> _frames = [];
  StreamSubscription<ElmResponse>? _sub;
  bool truncated = false;

  List<TxRxFrame> get frames => List.unmodifiable(_frames);

  void attach(Stream<ElmResponse> log) {
    _sub?.cancel();
    _sub = log.listen(add);
  }

  Future<void> detach() async {
    await _sub?.cancel();
    _sub = null;
  }

  int _ms(DateTime t) => t.difference(startedAt).inMilliseconds.clamp(0, 1 << 31);

  void _push(TxRxFrame f) {
    if (_frames.length >= maxFrames) {
      truncated = true;
      return;
    }
    _frames.add(f);
    onFrame?.call(f);
  }

  /// Records one completed exchange: TX at (now - elapsed), RX at now.
  void add(ElmResponse r) {
    final end = _now();
    final start = end.subtract(r.elapsed);
    final timedOut = r.error == ElmErrorKind.timeout;
    _push(TxRxFrame(tMs: _ms(start), dir: 'tx', data: r.command));
    _push(TxRxFrame(
      tMs: _ms(end),
      dir: 'rx',
      data: r.raw,
      durationMs: r.elapsed.inMilliseconds,
      timeout: timedOut ? true : null,
    ));
  }
}

/// Replies that can carry the VIN: OBD 09 02 and UDS ReadDataByIdentifier F190.
bool _readsVin(String cmd) {
  final c = cmd.replaceAll(' ', '').toUpperCase();
  return c.startsWith('0902') || c.startsWith('22F190');
}

/// Copy of [frames] with every VIN-bearing reply replaced by a marker (for sharing).
/// The TX side and timing are kept so the log still shows the request happened.
List<TxRxFrame> maskVinTraffic(List<TxRxFrame> frames) {
  final out = <TxRxFrame>[];
  var maskNext = false;
  for (final f in frames) {
    if (f.dir == 'tx') {
      maskNext = _readsVin(f.data);
      out.add(f);
    } else if (maskNext) {
      out.add(TxRxFrame(tMs: f.tMs, dir: f.dir, data: '[VIN masked]', canId: f.canId, durationMs: f.durationMs, timeout: f.timeout));
      maskNext = false;
    } else {
      out.add(f);
    }
  }
  return out;
}
