import 'dart:convert';

import 'package:automind_app/obd/obd.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final table = loadTable();

  Future<Recording> record() async {
    var now = const Duration(seconds: 12);
    final emu = Elm327Emulator(loadScenario('p0106_map_sensor'), table, clock: () => now);
    final client = ObdClient(transport: DemoTransport(emu, latency: Duration.zero), table: table);
    await client.connect();
    final sup = await client.readSupportedPids();
    var wall = DateTime.utc(2026, 10, 22, 10);
    final rec = Recorder(
      dataMode: client.dataMode,
      sourceKind: 'simulator',
      table: table,
      newId: () => '3f2b8c1e-8d4a-4c1b-9a7e-2f1d3c4b5a69',
      adapterFirmware: client.info.firmware,
      protocolCode: client.info.protocolCode,
      protocolName: client.info.protocolName,
      demoScenario: 'p0106_map_sensor',
      now: () => wall,
    )..setSupported(sup);
    rec.dtcs = (await client.readDtcs(DtcStatus.stored)).dtcs;
    final ff = await client.readFreezeFrame();
    if (ff != null) rec.freezeFrames = [ff];
    for (var i = 0; i < 12; i++) {
      for (final pid in [0x0C, 0x0B, 0x10, 0x14]) {
        wall = wall.add(const Duration(milliseconds: 250));
        now += const Duration(milliseconds: 250);
        final r = await client.readPid(pid);
        for (final x in r) {
          rec.addReading(PidReading(pid: x.pid, ecu: x.ecu, raw: x.raw, values: x.values, at: wall));
        }
      }
    }
    rec.addEvent('note', 'test');
    await client.dispose();
    return rec.build();
  }

  test('recorder JSON has the schema required fields', () async {
    final r = await record();
    final j = jsonDecode(r.toJsonString()) as Map<String, dynamic>;
    expect(Recording.validateJson(j), isEmpty);
    expect(j['data_mode'], 'demo');
    expect(j['source']['kind'], 'simulator');
    expect(j['source']['demo_scenario'], 'p0106_map_sensor');
    expect((j['samples'] as List), hasLength(48));
    expect((j['samples'] as List).first['raw'], startsWith('41 0C'));
    expect(j['dtcs'], [
      {'code': 'P0106', 'status': 'stored', 'ecu': '7E8'},
    ]);
    expect(j['supported_pids']['01'], contains('0B'));
    expect(j['ecus'], containsAll(['7E8', '7E9']));
    expect(j['duration_ms'], 12000);
    expect((j['signals'] as List).map((s) => s['key']), containsAll(['engine_rpm', 'map_kpa', 'maf_gs', 'o2_b1s1_voltage']));
  });

  test('replay re-decodes raw bytes to identical values and keeps data_mode', () async {
    final original = await record();
    final reloaded = Recording.fromJsonString(original.toJsonString());
    final replay = ReplaySource(reloaded, table: table);
    expect(replay.originalDataMode, 'demo');
    final decoded = replay.decodeAll();
    expect(decoded, hasLength(original.samples.length));
    for (var i = 0; i < decoded.length; i++) {
      expect(decoded[i].values, original.samples[i].values);
      expect(decoded[i].tMs, original.samples[i].tMs);
    }
  });

  test('replay timing: 2x speed, pause and seek', () async {
    final rec = await record();
    fakeAsync((async) {
      final replay = ReplaySource(rec, table: table);
      final got = <RecordingSample>[];
      replay.samples.listen(got.add);
      replay.play(speed: 2);
      async.elapse(const Duration(milliseconds: 1000)); // 2 s of recording
      expect(got.length, inInclusiveRange(7, 9));
      replay.pause();
      final n = got.length;
      async.elapse(const Duration(seconds: 5));
      expect(got.length, n);
      replay.seek(10000);
      replay.play(speed: 4);
      async.elapse(const Duration(seconds: 1));
      expect(replay.isFinished, isTrue);
      expect(got.last.tMs, rec.samples.last.tMs);
    });
  });

  test('replay mode cannot be recorded as new data', () {
    expect(
      () => Recorder(dataMode: DataMode.replay, sourceKind: 'simulator', table: table, newId: () => 'x'),
      throwsArgumentError,
    );
  });
}
