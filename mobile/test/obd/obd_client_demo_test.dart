import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final table = loadTable();

  Future<(ObdClient, Elm327Emulator)> connectDemo(String key) async {
    final emu = Elm327Emulator(loadScenario(key), table, clock: () => const Duration(seconds: 10));
    final client = ObdClient(
      transport: DemoTransport(emu, latency: Duration.zero),
      table: table,
      config: const ObdClientConfig(backoff: Duration.zero),
    );
    final r = await client.connect();
    expect(r.adapterOk, isTrue);
    expect(r.ecuOk, isTrue);
    return (client, emu);
  }

  test('full flow against the p0106 scenario', () async {
    final (client, _) = await connectDemo('p0106_map_sensor');
    final states = <LinkStatus>[];
    client.status.listen(states.add);

    expect(client.info.firmware, 'ELM327 v1.5');
    expect(client.info.isSimulator, isTrue);
    expect(client.dataMode, DataMode.demo);
    expect(client.info.protocolCode, '6');
    expect(client.info.protocolAuto, isTrue);
    expect(client.info.protocolName, 'AUTO, ISO 15765-4 (CAN 11/500)');
    expect(client.info.voltage, closeTo(14.2, 0.3));
    expect(client.currentStatus.adapter, AdapterState.connected);
    expect(client.currentStatus.ecu, EcuState.connected);

    final sup = await client.readSupportedPids();
    expect(sup.ecus, containsAll(['7E8', '7E9']));
    expect(sup.byEcu['7E9'], {0x01});
    expect(sup.byEcu['7E8'], containsAll([0x0B, 0x0C, 0x0D, 0x05, 0x42, 0x4C]));
    expect(sup.supports(0x0A), isFalse);
    expect(sup.service09, containsAll([0x02, 0x04]));
    expect(sup.toRecordingJson()['01'], contains('0C'));

    final vin = await client.readVin();
    expect(vin.vin, loadScenario('p0106_map_sensor').vin);
    expect(vin.vin, hasLength(17));
    expect(vin.valid, isTrue);

    final stored = await client.readDtcs(DtcStatus.stored);
    expect(stored.dtcs.map((d) => d.code), ['P0106']);
    expect(stored.dtcs.single.ecu, '7E8');
    expect((await client.readDtcs(DtcStatus.pending)).dtcs, isEmpty);
    expect((await client.readDtcs(DtcStatus.permanent)).dtcs.map((d) => d.code), ['P0106']);

    final ff = await client.readFreezeFrame();
    expect(ff, isNotNull);
    expect(ff!.dtc, 'P0106');
    expect(ff.values['engine_rpm'], 748);
    expect(ff.values['map_kpa'], 61);
    expect(ff.values['coolant_temp'], 89);

    final rpm = (await client.readPid(0x0C)).single;
    expect(rpm.ecu, '7E8');
    expect(rpm.values['engine_rpm'], inInclusiveRange(600, 900)); // warm idle at t=10s
    final map = (await client.readPid(0x0B)).single.values['map_kpa']!;
    expect(map, greaterThan(45)); // P0106 fault: offset +28 at idle
    final coolant = (await client.readPid(0x05)).single.values['coolant_temp']!;
    expect(coolant, inInclusiveRange(85, 95));
    final volts = (await client.readPid(0x42)).single.values['module_voltage']!;
    expect(volts, inInclusiveRange(13.9, 14.5));
    final mon = (await client.readPid(0x01)).single.values;
    expect(mon['mil_on'], 1);
    expect(mon['dtc_count'], 1);

    // Unsupported PIDs are never requested.
    expect(() => client.readPid(0x0A), throwsA(isA<NotSupportedException>()));
    await client.dispose();
  });

  test('healthy scenario values are physically plausible across the drive cycle', () async {
    final sc = loadScenario('healthy');
    var now = Duration.zero;
    final emu = Elm327Emulator(sc, table, clock: () => now);
    final client = ObdClient(transport: DemoTransport(emu, latency: Duration.zero), table: table);
    await client.connect();
    await client.readSupportedPids();
    now = const Duration(seconds: 15); // warm idle
    final idleMap = (await client.readPid(0x0B)).single.values['map_kpa']!;
    final idleMaf = (await client.readPid(0x10)).single.values['maf_gs']!;
    final stft = (await client.readPid(0x06)).single.values['stft_b1']!;
    final ltft = (await client.readPid(0x07)).single.values['ltft_b1']!;
    expect(idleMap, inInclusiveRange(28, 35));
    expect(idleMaf, inInclusiveRange(2.5, 4));
    expect(stft.abs(), lessThanOrEqualTo(5));
    expect(ltft.abs(), lessThanOrEqualTo(5));
    now = const Duration(seconds: 80); // cruise
    expect((await client.readPid(0x0D)).single.values['vehicle_speed'], inInclusiveRange(75, 85));
    expect((await client.readPid(0x0C)).single.values['engine_rpm'], inInclusiveRange(1800, 2000));
    // O2 B1S1 switches between lean and rich.
    final o2 = <double>[];
    for (var ms = 0; ms < 2000; ms += 125) {
      now = Duration(milliseconds: 15000 + ms);
      o2.add((await client.readPid(0x14)).single.values['o2_b1s1_voltage']!);
    }
    expect(o2.reduce((a, b) => a < b ? a : b), lessThan(0.25));
    expect(o2.reduce((a, b) => a > b ? a : b), greaterThan(0.75));
    expect((await client.readDtcs(DtcStatus.stored)).dtcs, isEmpty);
    expect(await client.readFreezeFrame(), isNull);
    await client.dispose();
  });

  test('clear DTCs is refused without approval and with the engine running', () async {
    final (client, emu) = await connectDemo('p0171_vacuum_leak');
    await client.readSupportedPids();
    expect(
      () => client.clearDtcs(const ClearDtcApproval(operationId: 'x', status: 'rejected_policy', commands: [])),
      throwsA(isA<PolicyViolationException>()),
    );
    const ok = ClearDtcApproval(operationId: 'op1', status: 'approved', commands: ['04']);
    await expectLater(client.clearDtcs(ok), throwsA(isA<PolicyViolationException>()));
    expect((await client.readDtcs(DtcStatus.stored)).dtcs, isNotEmpty);

    emu.engineRunning = false;
    final out = await client.clearDtcs(ok);
    expect(out.success, isTrue);
    expect(out.responseFrames.join(), contains('44'));
    expect((await client.readDtcs(DtcStatus.stored)).dtcs, isEmpty);
    expect((await client.readDtcs(DtcStatus.pending)).dtcs, isEmpty);
    expect((await client.readDtcs(DtcStatus.permanent)).dtcs, isNotEmpty); // permanent stays
    expect(await client.readFreezeFrame(), isNull);
    await client.dispose();
  });

  for (final (proto, ecu, family) in [('7', '18DAF110', ProtocolFamily.can29), ('3', '10', ProtocolFamily.iso9141), ('2', '10', ProtocolFamily.j1850)]) {
    test('end-to-end over protocol $proto (${family.name})', () async {
      final sc = loadScenario('p0302_misfire');
      final emu = Elm327Emulator(sc, table, clock: () => const Duration(seconds: 10), protocol: proto);
      final client = ObdClient(transport: DemoTransport(emu, latency: Duration.zero), table: table);
      final r = await client.connect();
      expect(r.ecuOk, isTrue);
      expect(client.info.protocolCode, proto);
      expect(client.services.family, family);
      final sup = await client.readSupportedPids();
      expect(sup.byEcu.keys, contains(ecu));
      expect(sup.supports(0x0C), isTrue);
      final vin = await client.readVin();
      expect(vin.vin, sc.vin);
      final dtcs = await client.readDtcs(DtcStatus.stored);
      expect(dtcs.dtcs.map((d) => d.code), ['P0302']);
      expect(dtcs.dtcs.single.ecu, ecu);
      expect((await client.readDtcs(DtcStatus.pending)).dtcs.map((d) => d.code), ['P0300']);
      final rpm = (await client.readPid(0x0C)).single;
      expect(rpm.ecu, ecu);
      expect(rpm.values['engine_rpm'], inInclusiveRange(550, 950));
      await client.dispose();
    });
  }

  test('ignition off → adapter OK, ECU no response', () async {
    final emu = Elm327Emulator(loadScenario('healthy'), table, ignitionOn: false);
    final client = ObdClient(transport: DemoTransport(emu, latency: Duration.zero), table: table);
    final r = await client.connect();
    expect(r.adapterOk, isTrue);
    expect(r.ecuOk, isFalse);
    expect(client.currentStatus.ecu, EcuState.noResponse);
    expect(r.log.errorCode, 'ecu_unable_to_connect');
    await client.dispose();
  });

  test('link loss is detected and auto-reconnect emits events', () async {
    final emu = Elm327Emulator(loadScenario('healthy'), table, clock: () => const Duration(seconds: 5));
    final transport = DemoTransport(emu, latency: Duration.zero);
    final client = ObdClient(transport: transport, table: table, config: const ObdClientConfig(backoff: Duration.zero));
    await client.connect();
    client.autoReconnect = true;
    final events = <String>[];
    client.events.listen((e) => events.add(e.type));
    await transport.simulateLinkLoss();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await client.waitReconnect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events, containsAllInOrder(['connection_lost', 'reconnected']));
    expect(client.currentStatus.adapter, AdapterState.connected);
    await client.dispose();
  });

  test('connection log matches POST /connections', () async {
    final emu = Elm327Emulator(loadScenario('healthy'), table);
    final client = ObdClient(transport: DemoTransport(emu, latency: Duration.zero), table: table);
    final r = await client.connect();
    final j = r.log.toJson();
    expect(j['data_mode'], 'demo');
    expect(j['adapter_status'], 'connected');
    expect(j['ecu_status'], 'connected');
    expect(j['protocol_code'], '6');
    expect(j['adapter_firmware'], 'ELM327 v1.5');
    expect(j['attempts'], 1);
    expect(j['started_at'], isA<String>());
    await client.dispose();
  });
}
