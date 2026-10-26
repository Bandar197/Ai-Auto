import 'dart:async';
import 'dart:convert';

import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// A serial/RFCOMM pipe whose far end is the in-process ELM327 emulator.
class EmulatorByteChannel implements ByteChannel {
  EmulatorByteChannel(this.emu, {this.failOpen = false});
  final Elm327Emulator emu;
  bool failOpen;
  int opens = 0;
  final List<List<int>> writes = [];
  StreamController<List<int>>? _in;
  final StringBuffer _pending = StringBuffer();

  @override
  String get description => 'COM7 @ 38400';

  @override
  Stream<List<int>> get input => _in!.stream;

  @override
  Future<void> open() async {
    opens++;
    if (failOpen) throw TransportException('cannot open COM7', code: 'unreachable');
    _in = StreamController<List<int>>();
  }

  @override
  Future<void> write(List<int> bytes) async {
    writes.add(bytes);
    _pending.write(latin1.decode(bytes));
    var text = _pending.toString();
    var i = text.indexOf('\r');
    while (i >= 0) {
      final out = emu.handle(text.substring(0, i));
      text = text.substring(i + 1);
      // Deliver the reply split in odd pieces, like a real UART.
      final b = latin1.encode(out);
      final c = _in;
      scheduleMicrotask(() {
        for (var k = 0; k < b.length; k += 5) {
          c?.add(b.sublist(k, k + 5 > b.length ? b.length : k + 5));
        }
      });
      i = text.indexOf('\r');
    }
    _pending
      ..clear()
      ..write(text);
  }

  /// The adapter disappears (out of range / powered off).
  Future<void> drop() async => _in?.close();

  @override
  Future<void> close() async {
    final c = _in;
    _in = null;
    if (c != null && !c.isClosed) await c.close();
  }
}

class FakeGattLink implements GattLink {
  FakeGattLink(this.services, {this.mtu = 185, this.emu});
  final Map<String, List<GattCharacteristicInfo>> services;
  final int mtu;
  final Elm327Emulator? emu;
  final List<(String, String, List<int>, bool)> writes = [];
  final StreamController<bool> conn = StreamController<bool>.broadcast();
  final StreamController<List<int>> rx = StreamController<List<int>>.broadcast();
  String? subscribed;
  bool subscribedIndicate = false;
  bool disconnected = false;
  final StringBuffer _pending = StringBuffer();

  @override
  String get description => 'OBDBLE';
  @override
  Stream<bool> get connection => conn.stream;
  @override
  Future<void> connect(Duration timeout) async {}
  @override
  Future<int> requestMtu(int m) async => mtu;
  @override
  Future<Map<String, List<GattCharacteristicInfo>>> discover() async => services;
  @override
  Future<Stream<List<int>>> subscribe(String service, String characteristic, {bool indicate = false}) async {
    subscribed = '$service/$characteristic';
    subscribedIndicate = indicate;
    return rx.stream;
  }

  @override
  Future<void> write(String service, String characteristic, List<int> data, {required bool withResponse}) async {
    writes.add((service, characteristic, data, withResponse));
    final e = emu;
    if (e == null) return;
    _pending.write(latin1.decode(data));
    var text = _pending.toString();
    var i = text.indexOf('\r');
    while (i >= 0) {
      final out = latin1.encode(e.handle(text.substring(0, i)));
      text = text.substring(i + 1);
      scheduleMicrotask(() {
        for (var k = 0; k < out.length; k += 20) {
          rx.add(out.sublist(k, k + 20 > out.length ? out.length : k + 20)); // 20-byte notifications
        }
      });
      i = text.indexOf('\r');
    }
    _pending
      ..clear()
      ..write(text);
  }

  @override
  Future<void> disconnect() async => disconnected = true;
}

const _full = '0000fff0-0000-1000-8000-00805f9b34fb';

void main() {
  final table = loadTable();

  group('ByteChannelTransport (serial COM / Bluetooth Classic)', () {
    test('chunking helper', () {
      expect(ByteChannelTransport.chunk([1, 2, 3, 4, 5], 2), [
        [1, 2],
        [3, 4],
        [5],
      ]);
      expect(ByteChannelTransport.chunk([1, 2, 3], 0), [
        [1, 2, 3],
      ]);
    });

    test('framing: text out as latin1, split replies reassembled by the ELM layer', () async {
      final ch = EmulatorByteChannel(Elm327Emulator(loadScenario('healthy'), table));
      final t = ByteChannelTransport(ch, maxChunk: 3);
      await t.connect();
      final elm = Elm327(t)..attach();
      final r = await elm.send('ATI');
      expect(r.text, 'ELM327 v1.5');
      expect(ch.writes.map((w) => latin1.decode(w)).join(), 'ATI\r');
      expect(ch.writes.every((w) => w.length <= 3), isTrue);
      expect(t.kind, TransportKind.usbSerial);
      await t.close();
    });

    test('open failure → TransportException; link drop closes incoming', () async {
      final bad = ByteChannelTransport(EmulatorByteChannel(Elm327Emulator(loadScenario('healthy'), table), failOpen: true));
      await expectLater(bad.connect(), throwsA(isA<TransportException>().having((e) => e.code, 'code', 'unreachable')));
      final ch = EmulatorByteChannel(Elm327Emulator(loadScenario('healthy'), table));
      final t = ByteChannelTransport(ch);
      await t.connect();
      final done = Completer<void>();
      t.incoming.listen(null, onDone: done.complete);
      await ch.drop();
      await done.future;
      expect(t.isConnected, isFalse);
      await expectLater(t.write('ATI\r'), throwsA(isA<TransportException>()));
    });

    test('same OBD engine end-to-end + auto-reconnect after the link drops', () async {
      final ch = EmulatorByteChannel(Elm327Emulator(loadScenario('p0106_map_sensor'), table, clock: () => const Duration(seconds: 10)));
      final client = ObdClient(transport: ByteChannelTransport(ch), table: table, config: const ObdClientConfig(backoff: Duration.zero));
      final r = await client.connect();
      expect(r.ecuOk, isTrue);
      expect(r.log.toJson()['transport'], 'usb_serial');
      expect((await client.readDtcs(DtcStatus.stored)).dtcs.map((d) => d.code), ['P0106']);
      client.autoReconnect = true;
      final events = <String>[];
      client.events.listen((e) => events.add(e.type));
      await ch.drop();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await client.waitReconnect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events, containsAllInOrder(['connection_lost', 'reconnected']));
      expect(ch.opens, 2);
      await client.readSupportedPids();
      expect((await client.readPid(0x0C)).single.values['engine_rpm'], greaterThan(500));
      await client.dispose();
    });
  });

  group('GattUartTransport (BLE)', () {
    GattCharacteristicInfo c(String u, {bool w = false, bool wnr = false, bool n = false, bool i = false}) =>
        GattCharacteristicInfo(u, write: w, writeWithoutResponse: wnr, notify: n, indicate: i);

    test('FFF0 layout (128-bit UUIDs as universal_ble reports them), MTU chunking', () async {
      final link = FakeGattLink({
        '00001800-0000-1000-8000-00805f9b34fb': [c('00002a00-0000-1000-8000-00805f9b34fb')],
        _full: [
          c('0000fff1-0000-1000-8000-00805f9b34fb', n: true),
          c('0000fff2-0000-1000-8000-00805f9b34fb', w: true, wnr: true),
        ],
      }, mtu: 23);
      final t = GattUartTransport(link);
      await t.connect();
      expect(t.profile!.name, 'FFF0');
      expect(link.subscribed, 'fff0/fff1');
      await t.write('${'0' * 45}\r');
      expect(link.writes.map((w) => w.$3.length), [20, 20, 6]); // ATT payload = MTU - 3 (min 20)
      expect(link.writes.every((w) => w.$4), isTrue); // write-with-response when allowed
      expect(link.writes.first.$2, 'fff2');
    });

    test('FFE0 single characteristic, write-without-response only, larger MTU', () async {
      final link = FakeGattLink({
        '0000ffe0-0000-1000-8000-00805f9b34fb': [c('0000ffe1-0000-1000-8000-00805f9b34fb', wnr: true, n: true)],
      }, mtu: 185);
      final t = GattUartTransport(link);
      await t.connect();
      expect(t.profile!.name, 'FFE0');
      await t.write('${'A' * 300}\r');
      expect(link.writes.map((w) => w.$3.length), [182, 119]);
      expect(link.writes.every((w) => !w.$4), isTrue);
    });

    test('18F0 layout with indicate-only RX', () async {
      final link = FakeGattLink({
        '000018f0-0000-1000-8000-00805f9b34fb': [
          c('00002af0-0000-1000-8000-00805f9b34fb', i: true),
          c('00002af1-0000-1000-8000-00805f9b34fb', w: true),
        ],
      });
      final t = GattUartTransport(link);
      await t.connect();
      expect(t.profile!.name, '18F0');
      expect(link.subscribedIndicate, isTrue);
    });

    test('manual UUID override wins; unknown layout is rejected and disconnected', () async {
      const custom = BleUartProfile(name: 'manual', service: 'abcd', notify: 'abce', write: 'abcf');
      final link = FakeGattLink({
        _full: [c('0000fff1-0000-1000-8000-00805f9b34fb', n: true), c('0000fff2-0000-1000-8000-00805f9b34fb', w: true)],
        '0000abcd-0000-1000-8000-00805f9b34fb': [c('0000abce-0000-1000-8000-00805f9b34fb', n: true), c('0000abcf-0000-1000-8000-00805f9b34fb', w: true)],
      });
      final t = GattUartTransport(link, uuidOverride: custom);
      await t.connect();
      expect(t.profile!.name, 'manual');
      final none = FakeGattLink({'0000aaaa-0000-1000-8000-00805f9b34fb': [c('0000aaab-0000-1000-8000-00805f9b34fb', n: true)]});
      await expectLater(GattUartTransport(none).connect(), throwsA(isA<TransportException>().having((e) => e.code, 'code', 'rejected')));
      expect(none.disconnected, isTrue);
    });

    test('ObdClient over BLE (20-byte notifications) and disconnect detection', () async {
      final link = FakeGattLink({
        '0000ffe0-0000-1000-8000-00805f9b34fb': [c('0000ffe1-0000-1000-8000-00805f9b34fb', w: true, n: true)],
      }, mtu: 23, emu: Elm327Emulator(loadScenario('p0302_misfire'), table, clock: () => const Duration(seconds: 10)));
      final client = ObdClient(transport: GattUartTransport(link), table: table);
      final r = await client.connect();
      expect(r.ecuOk, isTrue);
      expect(r.log.toJson()['transport'], 'ble');
      expect((await client.readVin()).vin, loadScenario('p0302_misfire').vin);
      final lost = Completer<void>();
      client.events.listen((e) {
        if (e.type == 'connection_lost' && !lost.isCompleted) lost.complete();
      });
      link.conn.add(false); // adapter powered off
      await lost.future;
      expect(client.currentStatus.adapter, AdapterState.disconnected);
      await client.dispose();
    });
  });
}
