import 'dart:io';

import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

import '../obd/helpers.dart';

/// Opt-in cross-check against the team's Python simulator over real TCP:
///   automind simulate --host 127.0.0.1 --port 35000 --scenario p0106_map_sensor
///   AUTOMIND_SIM=127.0.0.1:35000 AUTOMIND_SIM_SCENARIO=p0106_map_sensor flutter test test/integration
void main() {
  final target = Platform.environment['AUTOMIND_SIM'];
  final scenarioKey = Platform.environment['AUTOMIND_SIM_SCENARIO'] ?? 'p0106_map_sensor';
  final skip = target == null ? 'set AUTOMIND_SIM=host:port to run against the Python simulator' : null;

  test('ObdClient over TCP against `automind simulate` ($scenarioKey)', () async {
    final parts = target!.split(':');
    final table = loadTable();
    final scenario = loadScenario(scenarioKey);
    final client = ObdClient(
      transport: TcpTransport(host: parts[0], port: int.parse(parts[1])),
      table: table,
    );
    final r = await client.connect();
    expect(r.adapterOk, isTrue, reason: client.currentStatus.toString());
    expect(r.ecuOk, isTrue, reason: client.currentStatus.toString());
    // AT@1 = AUTOMIND SIMULATOR → never live.
    expect(client.info.isSimulator, isTrue);
    expect(r.dataMode, DataMode.demo);
    expect(r.log.toJson()['data_mode'], 'demo');
    expect(r.log.toJson()['transport'], 'wifi_tcp');
    expect(client.info.firmware, scenario.firmware);

    final sup = await client.readSupportedPids();
    expect(sup.byEcu.values.first, containsAll(scenario.supportedPids('01')));
    final vin = await client.readVin();
    expect(vin.vin, scenario.vin);
    final stored = await client.readDtcs(DtcStatus.stored);
    expect(stored.dtcs.map((d) => d.code).toSet(), {for (final d in scenario.dtcs) if (d.status == DtcStatus.stored) d.code});
    final pending = await client.readDtcs(DtcStatus.pending);
    expect(pending.dtcs.map((d) => d.code).toSet(), {for (final d in scenario.dtcs) if (d.status == DtcStatus.pending) d.code});
    final ff = await client.readFreezeFrame();
    if (scenario.freezeFrame != null) {
      expect(ff?.dtc, scenario.freezeFrame!['dtc']);
    }
    for (final pid in [0x0C, 0x0D, 0x05, 0x0B, 0x10, 0x42]) {
      if (!sup.supports(pid)) continue;
      final rd = await client.readPid(pid);
      expect(rd, isNotEmpty, reason: 'PID $pid');
      for (final v in rd.single.values.values) {
        expect(v, isNotNull);
      }
    }
    await client.dispose();
  }, skip: skip, timeout: const Timeout(Duration(seconds: 60)));

  /// Clear-and-verify against the simulator, e.g.:
  ///   automind simulate --scenario old_code_repaired --port 35444 --engine-off --start-engine-after-clear 5 --time-scale 40
  ///   AUTOMIND_SIM=127.0.0.1:35444 AUTOMIND_SIM_SCENARIO=old_code_repaired AUTOMIND_SIM_CLEAR_EXPECT=likely_resolved flutter test test/integration
  final expectOverall = Platform.environment['AUTOMIND_SIM_CLEAR_EXPECT'];
  test('clear and verify against `automind simulate` → $expectOverall', () async {
    final parts = target!.split(':');
    final table = loadTable();
    final waitS = int.tryParse(Platform.environment['AUTOMIND_SIM_WAIT_S'] ?? '') ?? 4;
    Future<ObdClient> open() async {
      final c = ObdClient(transport: TcpTransport(host: parts[0], port: int.parse(parts[1])), table: table);
      expect((await c.connect()).ecuOk, isTrue);
      await c.readSupportedPids();
      return c;
    }

    var c = await open();
    final before = await c.snapshot();
    expect(before.dtcs, isNotEmpty);
    final out = await c.clearDtcs(const ClearDtcApproval(operationId: 'it', status: 'approved', commands: ['04']));
    expect(out.success, isTrue, reason: 'engine must be off (--engine-off)');
    final record = ClearRecord(clearedAt: DateTime.now().toUtc(), before: before, dataMode: 'demo');
    final checks = [await c.snapshot()]; // immediate, same key cycle
    await c.dispose();
    await Future<void>.delayed(Duration(seconds: waitS)); // simulated time runs ×time-scale
    c = await open(); // later scan on a new connection: vehicle state persists in the server
    checks.add(await c.snapshot());
    await c.dispose();
    final v = assessAfterClear(record, checks);
    // ignore: avoid_print
    print('verdict: ${v.overall} · ${v.codes.map((x) => '${x.code}:${x.verdict}').join(', ')}');
    expect(v.overall, expectOverall);
  }, skip: target == null || expectOverall == null ? 'set AUTOMIND_SIM and AUTOMIND_SIM_CLEAR_EXPECT' : null, timeout: const Timeout(Duration(seconds: 90)));
}
