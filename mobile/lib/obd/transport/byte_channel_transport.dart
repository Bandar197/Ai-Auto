import 'dart:async';
import 'dart:convert';

import '../errors.dart';
import 'obd_transport.dart';

/// A raw, already-paired byte pipe to an ELM327: a serial/COM port (USB or
/// Bluetooth Classic paired in the OS) or an Android RFCOMM (SPP) socket.
/// Implementations live in lib/platform/ (they need plugins/platform channels).
abstract class ByteChannel {
  String get description;

  /// Opens the link; throws [TransportException] on failure.
  Future<void> open();

  /// Received bytes. The stream ends (or errors) when the link drops.
  Stream<List<int>> get input;

  /// Writes all bytes (implementations handle partial writes).
  Future<void> write(List<int> bytes);

  Future<void> close();
}

/// [ObdTransport] over a [ByteChannel]: latin1 text framing, optional write
/// chunking and disconnect detection (input stream end → [incoming] closes,
/// which the ELM327 layer reports as link loss → client auto-reconnect).
class ByteChannelTransport implements ObdTransport {
  ByteChannelTransport(this.channel, {this.kind = TransportKind.usbSerial, this.maxChunk = 0});

  final ByteChannel channel;
  @override
  final TransportKind kind;

  /// Max bytes per write (0 = unlimited).
  final int maxChunk;

  StreamController<String>? _controller;
  StreamSubscription<List<int>>? _sub;

  @override
  String get description => channel.description;

  @override
  bool get isConnected => _controller != null;

  @override
  Stream<String> get incoming {
    final c = _controller;
    if (c == null) throw TransportException('not connected');
    return c.stream;
  }

  @override
  Future<void> connect() async {
    await close();
    try {
      await channel.open();
    } on TransportException {
      rethrow;
    } on Object catch (e) {
      throw TransportException('cannot open ${channel.description}: $e', code: 'unreachable');
    }
    final c = StreamController<String>.broadcast();
    _controller = c;
    _sub = channel.input.listen(
      (bytes) {
        if (!c.isClosed) c.add(latin1.decode(bytes, allowInvalid: true));
      },
      onError: (Object _) => _teardown(),
      onDone: _teardown,
      cancelOnError: true,
    );
  }

  void _teardown() {
    _sub?.cancel();
    _sub = null;
    final c = _controller;
    _controller = null;
    if (c != null && !c.isClosed) c.close();
  }

  /// Splits [data] into chunks of at most [size] bytes (0 = one chunk).
  static List<List<int>> chunk(List<int> data, int size) {
    if (size <= 0 || data.length <= size) return [data];
    return [for (var i = 0; i < data.length; i += size) data.sublist(i, i + size > data.length ? data.length : i + size)];
  }

  @override
  Future<void> write(String data) async {
    if (_controller == null) throw TransportException('link closed', code: 'socket_closed');
    try {
      for (final part in chunk(latin1.encode(data), maxChunk)) {
        await channel.write(part);
      }
    } on Object catch (e) {
      _teardown();
      await channel.close();
      throw TransportException('write failed: $e', code: 'socket_closed');
    }
  }

  @override
  Future<void> close() async {
    _teardown();
    try {
      await channel.close();
    } on Object catch (_) {}
  }
}
