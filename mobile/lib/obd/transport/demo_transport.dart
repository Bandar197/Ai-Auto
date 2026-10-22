import 'dart:async';

import '../emulator/elm327_emulator.dart';
import '../errors.dart';
import 'obd_transport.dart';

/// In-process transport backed by [Elm327Emulator]. No network involved;
/// everything it produces is DEMO data.
class DemoTransport implements ObdTransport {
  DemoTransport(this.emulator, {this.latency = const Duration(milliseconds: 25)});

  final Elm327Emulator emulator;
  final Duration latency;

  StreamController<String>? _controller;
  final StringBuffer _pending = StringBuffer();

  @override
  TransportKind get kind => TransportKind.demo;

  @override
  String get description => 'demo:${emulator.scenario.key}';

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
    _controller = StreamController<String>.broadcast();
  }

  @override
  Future<void> write(String data) async {
    final c = _controller;
    if (c == null) throw TransportException('demo transport closed', code: 'socket_closed');
    _pending.write(data);
    var text = _pending.toString();
    var idx = text.indexOf('\r');
    while (idx >= 0) {
      final cmd = text.substring(0, idx);
      text = text.substring(idx + 1);
      final out = emulator.handle(cmd);
      if (latency == Duration.zero) {
        scheduleMicrotask(() {
          if (!c.isClosed) c.add(out);
        });
      } else {
        Timer(latency, () {
          if (!c.isClosed) c.add(out);
        });
      }
      idx = text.indexOf('\r');
    }
    _pending
      ..clear()
      ..write(text);
  }

  /// Simulates the adapter dropping off (for reconnect tests/demos).
  Future<void> simulateLinkLoss() async {
    final c = _controller;
    _controller = null;
    await c?.close();
  }

  @override
  Future<void> close() async {
    final c = _controller;
    _controller = null;
    _pending.clear();
    if (c != null && !c.isClosed) await c.close();
  }
}
