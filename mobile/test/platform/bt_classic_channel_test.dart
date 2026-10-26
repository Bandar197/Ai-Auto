import 'dart:async';
import 'dart:convert';

import 'package:automind_app/obd/obd.dart';
import 'package:automind_app/platform/bt_classic_transport.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../obd/helpers.dart';

/// Fakes the Kotlin side of `automind/bt_classic` + `automind/bt_classic/rx`
/// with an ELM327 emulator behind the "socket".
class FakeAndroidBtClassic {
  FakeAndroidBtClassic(this.emu);
  final Elm327Emulator emu;
  final List<MethodCall> calls = [];
  MockStreamHandlerEventSink? sink;
  bool connected = false;
  bool failConnect = false;
  final StringBuffer _pending = StringBuffer();

  void install() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(BtClassicTransport.methods, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isSupported':
        case 'isEnabled':
        case 'requestPermission':
          return true;
        case 'bondedDevices':
          return [
            {'name': 'OBDII', 'address': '00:1D:A5:68:98:8B'},
          ];
        case 'connect':
          if (failConnect) throw PlatformException(code: 'connect_failed', message: 'read failed, socket might closed');
          connected = true;
          return true;
        case 'write':
          final data = (call.arguments as Map)['data'] as Uint8List;
          _pending.write(latin1.decode(data));
          var text = _pending.toString();
          var i = text.indexOf('\r');
          while (i >= 0) {
            final out = latin1.encode(emu.handle(text.substring(0, i)));
            text = text.substring(i + 1);
            scheduleMicrotask(() {
              for (var k = 0; k < out.length; k += 7) {
                sink?.success(Uint8List.fromList(out.sublist(k, k + 7 > out.length ? out.length : k + 7)));
              }
            });
            i = text.indexOf('\r');
          }
          _pending
            ..clear()
            ..write(text);
          return null;
        case 'disconnect':
          connected = false;
          return null;
      }
      return null;
    });
    m.setMockStreamHandler(
      BtClassicTransport.events,
      MockStreamHandler.inline(onListen: (args, events) => sink = events, onCancel: (_) => sink = null),
    );
  }

  /// The RFCOMM link drops (adapter unplugged / out of range).
  void dropLink() {
    connected = false;
    sink?.success({'event': 'disconnected'});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final table = loadTable();

  test('bonded devices and permission calls', () async {
    FakeAndroidBtClassic(Elm327Emulator(loadScenario('healthy'), table)).install();
    expect(await BtClassicTransport.isSupported(), isTrue);
    expect(await BtClassicTransport.requestPermission(), isTrue);
    final d = await BtClassicTransport.bondedDevices();
    expect(d.single.name, 'OBDII');
    expect(d.single.address, '00:1D:A5:68:98:8B');
  });

  test('connect → write → receive → disconnect event closes incoming', () async {
    final fake = FakeAndroidBtClassic(Elm327Emulator(loadScenario('healthy'), table))..install();
    final t = BtClassicTransport('00:1D:A5:68:98:8B', name: 'OBDII');
    await t.connect();
    expect(fake.calls.last.method, 'connect');
    expect((fake.calls.last.arguments as Map)['address'], '00:1D:A5:68:98:8B');
    expect(t.description, 'OBDII (00:1D:A5:68:98:8B)');
    final elm = Elm327(t)..attach();
    expect((await elm.send('ATI')).text, 'ELM327 v1.5');
    final w = fake.calls.where((c) => c.method == 'write').single;
    expect(latin1.decode((w.arguments as Map)['data'] as Uint8List), 'ATI\r');
    final done = Completer<void>();
    t.incoming.listen(null, onDone: done.complete);
    fake.dropLink();
    await done.future;
    expect(t.isConnected, isFalse);
  });

  test('connect failure maps to TransportException', () async {
    final fake = FakeAndroidBtClassic(Elm327Emulator(loadScenario('healthy'), table))
      ..failConnect = true
      ..install();
    await expectLater(BtClassicTransport('00:11:22:33:44:55').connect(), throwsA(isA<TransportException>()));
    expect(fake.connected, isFalse);
  });

  test('ObdClient over Classic SPP: scan data, link loss → auto-reconnect', () async {
    final fake = FakeAndroidBtClassic(Elm327Emulator(loadScenario('p0106_map_sensor'), table, clock: () => const Duration(seconds: 10)))
      ..install();
    final client = ObdClient(
      transport: BtClassicTransport('00:1D:A5:68:98:8B', name: 'OBDII'),
      table: table,
      config: const ObdClientConfig(backoff: Duration.zero),
    );
    final r = await client.connect();
    expect(r.adapterOk && r.ecuOk, isTrue);
    expect(client.dataMode, DataMode.demo); // AT@1 = AUTOMIND SIMULATOR
    expect((await client.readDtcs(DtcStatus.stored)).dtcs.map((d) => d.code), ['P0106']);
    client.autoReconnect = true;
    final events = <String>[];
    client.events.listen((e) => events.add(e.type));
    fake.dropLink();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await client.waitReconnect();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(events, containsAllInOrder(['connection_lost', 'reconnected']));
    expect(fake.calls.where((c) => c.method == 'connect'), hasLength(2));
    expect(fake.connected, isTrue);
    await client.dispose();
  });
}
