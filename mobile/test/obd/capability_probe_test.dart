import 'dart:async';

import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake adapter whose 0100 reply depends on header/filter state, like a real ELM327.
class StatefulAdapter implements ObdTransport {
  StatefulAdapter({this.acceptsHeaders = true, this.headersWork = true, this.filterWorks = true, this.multiFrameVin = true, this.vehicle = true, this.fcsm = true, this.dpn = 'A6'});

  final bool acceptsHeaders, headersWork, filterWorks, multiFrameVin, vehicle, fcsm;
  final String dpn;
  bool headers = true;
  bool filtered = false;
  final List<String> sent = [];
  StreamController<String>? _c;

  @override
  TransportKind get kind => TransportKind.ble;
  @override
  String get description => 'stateful';
  @override
  bool get isConnected => _c != null;
  @override
  Stream<String> get incoming => _c!.stream;
  @override
  Future<void> connect() async => _c = StreamController<String>.broadcast();
  @override
  Future<void> close() async {
    await _c?.close();
    _c = null;
  }

  String _reply(String cmd) {
    switch (cmd) {
      case 'ATI':
        return 'ELM327 v1.5';
      case 'AT@1':
        return '?';
      case 'ATRV':
        return '12.4V';
      case 'ATDP':
        return 'AUTO, ISO 15765-4 (CAN 11/500)';
      case 'ATDPN':
        return dpn;
      case 'ATH0':
      case 'ATH1':
        if (!acceptsHeaders) return '?';
        if (headersWork) headers = cmd == 'ATH1';
        return 'OK';
      case 'ATCRA7E8':
        filtered = true;
        return 'OK';
      case 'ATAR':
        filtered = false;
        return 'OK';
      case 'ATCAF1':
        return 'OK';
      case 'ATFCSM0':
        return fcsm ? 'OK' : '?';
      case '0100':
        if (!vehicle) return 'NO DATA';
        final ecm = headers ? '7E8 06 41 00 BE 3F A8 13' : '41 00 BE 3F A8 13';
        final tcm = headers ? '7E9 06 41 00 80 00 00 01' : '41 00 80 00 00 01';
        return (filtered && filterWorks) ? ecm : '$ecm\r$tcm';
      case '0902':
        if (!vehicle) return 'NO DATA';
        return multiFrameVin ? '014\r0: 49 02 01 4B 4D 48\r1: 45 43 34 31 43 42 43\r2: 41 31 32 33 34 35 36' : '49 02 01 00 00 00 00';
    }
    return '?';
  }

  @override
  Future<void> write(String data) async {
    final cmd = data.replaceAll('\r', '');
    sent.add(cmd);
    final r = _reply(cmd);
    scheduleMicrotask(() => _c?.add('$r\r\r>'));
  }
}

AdapterInfo _info() => AdapterInfo(firmware: 'ELM327 v1.5', protocolCode: '6');

Future<(AdapterCapabilities, StatefulAdapter)> _probe(StatefulAdapter t, {bool ecu = true, AdapterInfo? info}) async {
  await t.connect();
  final elm = Elm327(t)..attach();
  final caps = await CapabilityProbe(elm).run(info: info ?? _info(), transport: t.kind, ecuConnected: ecu);
  return (caps, t);
}

void main() {
  test('a working adapter proves headers, filters and ISO-TP by behaviour', () async {
    final (c, t) = await _probe(StatefulAdapter());
    expect(c.capabilities[Capability.headers], isTrue);
    expect(c.evidence[Capability.headers], Evidence.behavioral);
    expect(c.capabilities[Capability.filters], isTrue);
    expect(c.evidence[Capability.filters], Evidence.behavioral);
    expect(c.capabilities[Capability.isoTp], isTrue);
    expect(c.capabilities[Capability.multiFrame], isTrue);
    expect(c.evidence[Capability.canFormatting], Evidence.acceptedOnly);
    expect(c.capabilities[Capability.protocolSwitching], isNull);
    expect(c.connection, 'ble');
    expect(c.voltage, 12.4);
    expect(c.firmware, 'ELM327 v1.5');
    // State restored: headers back on, filter cleared.
    expect(t.headers, isTrue);
    expect(t.filtered, isFalse);
  });

  test("'?' is never treated as supported", () async {
    final (c, _) = await _probe(StatefulAdapter());
    final at1 = c.probe.firstWhere((s) => s.cmd == 'AT@1');
    expect(at1.ok, isFalse);
    expect(c.name, isNull); // AT@1 answered '?', info.description is null
  });

  test('a clone that says OK to ATH1 but sends no headers fails behaviourally', () async {
    final (c, _) = await _probe(StatefulAdapter(headersWork: false));
    expect(c.capabilities[Capability.headers], isFalse);
    expect(c.evidence[Capability.headers], Evidence.behavioral);
    expect(c.usable(Capability.headers), isFalse);
  });

  test('a filter that lets other ECUs through fails', () async {
    final (c, _) = await _probe(StatefulAdapter(filterWorks: false));
    expect(c.capabilities[Capability.filters], isFalse);
  });

  test('single-frame VIN leaves ISO-TP not tested, not passed', () async {
    final (c, _) = await _probe(StatefulAdapter(multiFrameVin: false));
    expect(c.capabilities[Capability.isoTp], isNull);
    expect(c.evidence[Capability.isoTp], Evidence.notTested);
  });

  test('missing ATFCSM is reported as failed', () async {
    final (c, _) = await _probe(StatefulAdapter(fcsm: false));
    expect(c.capabilities[Capability.flowControl], isFalse);
  });

  test('without a vehicle nothing behavioural is claimed and no OBD request is sent', () async {
    final (c, t) = await _probe(StatefulAdapter(), ecu: false);
    expect(c.capabilities[Capability.headers], isNull);
    expect(c.capabilities[Capability.filters], isNull);
    expect(c.capabilities[Capability.isoTp], isNull);
    expect(t.sent.where((s) => s.startsWith('01') || s.startsWith('09')), isEmpty);
  });

  test('non-CAN protocol skips CAN-only probes', () async {
    final (c, t) = await _probe(StatefulAdapter(dpn: 'A3'), info: AdapterInfo(protocolCode: '3'));
    expect(c.capabilities[Capability.filters], isNull);
    expect(c.capabilities[Capability.canFormatting], isNull);
    expect(t.sent, isNot(contains('ATCRA7E8')));
    expect(t.sent, isNot(contains('0902')));
  });

  test('never sends clear, write or protocol-switch commands', () async {
    final (_, t) = await _probe(StatefulAdapter());
    for (final s in t.sent) {
      expect(s, isNot(startsWith('04')));
      expect(s, isNot(startsWith('14')));
      expect(s, isNot(startsWith('2E')));
      expect(s, isNot(startsWith('ATSP')));
      expect(s, isNot(startsWith('ATTP')));
    }
  });

  test('json round-trips with recording.v2 wire names', () async {
    final (c, _) = await _probe(StatefulAdapter());
    final j = c.toJson();
    expect((j['capabilities'] as Map).keys, containsAll(['headers', 'iso_tp', 'flow_control', 'protocol_switching']));
    final back = AdapterCapabilities.fromJson(j);
    expect(back.capabilities, c.capabilities);
    expect(back.evidence[Capability.headers], Evidence.behavioral);
    expect(back.probe.length, c.probe.length);
  });
}
