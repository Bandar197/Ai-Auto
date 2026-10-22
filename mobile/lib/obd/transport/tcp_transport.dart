import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../errors.dart';
import 'obd_transport.dart';

/// ELM327 Wi-Fi adapters expose a raw TCP socket (default 192.168.0.10:35000).
/// Also used for the team's PC simulator (`automind simulate`).
class TcpTransport implements ObdTransport {
  TcpTransport({
    this.host = defaultHost,
    this.port = defaultPort,
    this.connectTimeout = const Duration(seconds: 5),
  });

  static const String defaultHost = '192.168.0.10';
  static const int defaultPort = 35000;

  final String host;
  final int port;
  final Duration connectTimeout;

  Socket? _socket;
  StreamController<String>? _controller;

  @override
  TransportKind get kind => TransportKind.wifiTcp;

  @override
  String get description => '$host:$port';

  @override
  bool get isConnected => _socket != null;

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
      final socket = await Socket.connect(host, port, timeout: connectTimeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      final controller = StreamController<String>.broadcast();
      _controller = controller;
      socket.cast<List<int>>().transform(const Latin1Decoder(allowInvalid: true)).listen(
            controller.add,
            onError: (Object e) {
              controller.addError(TransportException('socket error: $e', code: 'socket_error'));
              _teardown();
            },
            onDone: _teardown,
            cancelOnError: true,
          );
    } on SocketException catch (e) {
      final timedOut = e.message.toLowerCase().contains('timed out') || e.osError == null;
      throw TransportException(
        'cannot reach adapter at $host:$port (${e.message})',
        code: timedOut ? 'timeout' : 'unreachable',
      );
    }
  }

  void _teardown() {
    _socket?.destroy();
    _socket = null;
    final c = _controller;
    _controller = null;
    if (c != null && !c.isClosed) c.close();
  }

  @override
  Future<void> write(String data) async {
    final s = _socket;
    if (s == null) throw TransportException('socket closed', code: 'socket_closed');
    try {
      s.add(latin1.encode(data));
      await s.flush();
    } on Object catch (e) {
      _teardown();
      throw TransportException('write failed: $e', code: 'socket_closed');
    }
  }

  @override
  Future<void> close() async {
    _teardown();
  }
}
