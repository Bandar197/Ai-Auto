import 'dart:async';
import 'dart:io';

import 'package:automind_app/obd/obd.dart';

PidTable loadTable() => PidTable.fromJsonString(File('assets/shared/obd/pids.json').readAsStringSync());

Scenario loadScenario(String key) => Scenario.fromJsonString(File('assets/shared/scenarios/$key.json').readAsStringSync());

/// Scripted transport: maps a command to a raw reply (prompt appended).
class ScriptedTransport implements ObdTransport {
  ScriptedTransport(this.replies, {this.silent = const {}});

  final Map<String, String> replies;
  final Set<String> silent;
  final List<String> sent = [];
  StreamController<String>? _c;

  @override
  TransportKind get kind => TransportKind.wifiTcp;
  @override
  String get description => 'scripted';
  @override
  bool get isConnected => _c != null;
  @override
  Stream<String> get incoming => _c!.stream;

  @override
  Future<void> connect() async => _c = StreamController<String>.broadcast();

  @override
  Future<void> write(String data) async {
    final cmd = data.replaceAll('\r', '');
    sent.add(cmd);
    if (silent.contains(cmd)) return;
    final reply = replies[cmd] ?? '?';
    // Deliver in two chunks to exercise buffering.
    final half = reply.length ~/ 2;
    scheduleMicrotask(() {
      _c?.add(reply.substring(0, half));
      _c?.add('${reply.substring(half)}\r\r>');
    });
  }

  @override
  Future<void> close() async {
    await _c?.close();
    _c = null;
  }
}
