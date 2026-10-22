import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Same cases as backend/tests/integration/test_clear_verify.py.
void main() {
  final t0 = DateTime.utc(2026, 10, 1);
  final table = loadTable();

  test('monitor mapping', () {
    expect(monitorFor('P0302'), 'misfire');
    expect(monitorFor('P0135'), 'o2_sensor_heater');
    expect(monitorFor('P0420'), 'catalyst');
    expect(monitorFor('P0106'), 'components');
    expect(monitorFor('P0171'), 'fuel_system');
    expect(monitorFor('P0442'), 'evap_system');
    expect(monitorFor('P2195'), 'o2_sensor');
    expect(monitorFor('B0001'), isNull);
    expect(monitorFor('U0100'), isNull);
  });

  test('airbag code logic without vehicle access', () {
    final rec = ClearRecord(clearedAt: t0, before: ScanSnapshot(takenAt: t0, dtcs: const [SnapshotDtc('B0001', ecu: 'SRS')]));
    final back = [ScanSnapshot(takenAt: t0.add(const Duration(minutes: 1)), dtcs: const [SnapshotDtc('B0001')])];
    final v = assessAfterClear(rec, back);
    expect(v.codes.first.verdict, 'returned_immediately');
    expect(v.codes.first.explanationAr, contains('الوسائد'));
    expect(v.overall, 'problem_confirmed');
    final gone = [for (final h in [1, 9]) ScanSnapshot(takenAt: t0.add(Duration(hours: h)))];
    final v2 = assessAfterClear(rec, gone);
    expect(v2.codes.first.verdict, 'not_returned_verified');
    expect(v2.codes.first.explanationAr, contains('فحمة الدركسون'));
    expect(v2.overall, 'likely_resolved');
    expect(assessAfterClear(rec, gone.sublist(0, 1)).codes.first.verdict, 'not_returned_yet');
  });

  test('permanent code alone is not a return', () {
    final rec = ClearRecord(clearedAt: t0, before: ScanSnapshot(takenAt: t0, dtcs: const [SnapshotDtc('P0420')]));
    final snap = ScanSnapshot(
      takenAt: t0.add(const Duration(days: 1)),
      dtcs: const [SnapshotDtc('P0420', status: 'permanent')],
      warmupsSinceClear: 3,
      distanceSinceClearKm: 80,
    );
    final v = assessAfterClear(rec, [snap]);
    expect(v.codes.first.verdict, 'still_permanent');
    expect(v.codes.first.isRealProblem, isNull);
    expect(v.overall, 'verifying');
  });

  test('new code after clear is flagged', () {
    final rec = ClearRecord(clearedAt: t0, before: ScanSnapshot(takenAt: t0, dtcs: const [SnapshotDtc('P0171')]));
    final snap = ScanSnapshot(takenAt: t0.add(const Duration(days: 1)), dtcs: const [SnapshotDtc('P0300', status: 'pending')]);
    final v = assessAfterClear(rec, [snap]);
    expect(v.codes.any((c) => c.verdict == 'new_code' && c.code == 'P0300'), isTrue);
    expect(v.overall, 'problem_confirmed');
  });

  test('stored later (driven) → returned_confirmed; pending → returned_pending', () {
    final rec = ClearRecord(clearedAt: t0, before: ScanSnapshot(takenAt: t0, dtcs: const [SnapshotDtc('P0106')]));
    final later = ScanSnapshot(takenAt: t0.add(const Duration(hours: 2)), dtcs: const [SnapshotDtc('P0106')], warmupsSinceClear: 1);
    final v = assessAfterClear(rec, [ScanSnapshot(takenAt: t0.add(const Duration(minutes: 1))), later]);
    expect(v.codes.single.verdict, 'returned_confirmed');
    expect(v.codes.single.returnedInCheck, 2);
    expect(v.codes.single.titleAr, contains('يوجد عطل حقيقي'));
    final p = assessAfterClear(rec, [ScanSnapshot(takenAt: later.takenAt, dtcs: const [SnapshotDtc('P0106', status: 'pending')])]);
    expect(p.codes.single.verdict, 'returned_pending');
    expect(p.codes.single.isRealProblem, isTrue);
  });

  test('catalyst code needs its monitor complete and driving', () {
    final rec = ClearRecord(clearedAt: t0, before: ScanSnapshot(takenAt: t0, dtcs: const [SnapshotDtc('P0420')]));
    Map<String, dynamic> rd(bool complete) => {
          'monitors': {
            'catalyst': {'available': true, 'complete': complete},
          },
        };
    final notYet = ScanSnapshot(takenAt: t0.add(const Duration(days: 1)), readiness: rd(false), warmupsSinceClear: 3);
    expect(assessAfterClear(rec, [notYet]).codes.single.verdict, 'not_returned_yet');
    final done = ScanSnapshot(takenAt: t0.add(const Duration(days: 3)), readiness: rd(true), warmupsSinceClear: 5);
    final v = assessAfterClear(rec, [notYet, done]);
    expect(v.codes.single.verdict, 'not_returned_verified');
    expect(v.codes.single.monitorComplete, isTrue);
    expect(v.overall, 'likely_resolved');
  });

  test('nothing cleared, demo tag and JSON round trip', () {
    final empty = assessAfterClear(ClearRecord(clearedAt: t0, before: ScanSnapshot(takenAt: t0)), const []);
    expect(empty.overall, 'nothing_cleared');
    final rec = ClearRecord(clearedAt: t0, dataMode: 'demo', before: ScanSnapshot(takenAt: t0, dtcs: const [SnapshotDtc('P0106')]));
    final v = assessAfterClear(rec, const []);
    expect(v.summaryAr, startsWith('[تجريبي] '));
    expect(v.summaryEn, startsWith('[DEMO] '));
    final back = ClearVerification.fromJson(v.toJson());
    expect(back.overall, v.overall);
    expect(back.codes.single.titleAr, v.codes.single.titleAr);
    final r2 = ClearRecord.fromJson(rec.toJson());
    expect(r2.before.dtcs.single.code, 'P0106');
    expect(r2.dataMode, 'demo');
  });

  test('readiness decoding (01 01) matches the backend decoder', () {
    final r = decodeMonitorStatus([0x81, 0x07, 0x65, 0x65])!;
    expect(r['mil_on'], isTrue);
    expect(r['dtc_count'], 1);
    expect(r['ignition'], 'spark');
    final m = r['monitors'] as Map;
    expect(m.keys, containsAll(['misfire', 'fuel_system', 'components', 'catalyst', 'evap_system', 'o2_sensor', 'o2_sensor_heater']));
    expect(m['catalyst'], {'available': true, 'complete': false});
    expect(m['components'], {'available': true, 'complete': true});
    expect(incompleteMonitors(r), containsAll(['catalyst', 'evap_system', 'o2_sensor', 'o2_sensor_heater']));
    final d = decodeMonitorStatus([0x00, 0x0F, 0x01, 0x00])!;
    expect(d['ignition'], 'compression');
    expect((d['monitors'] as Map)['nmhc_catalyst'], {'available': true, 'complete': true});
  });

  group('emulator post-clear behaviour through ObdClient (fake clock)', () {
    const approval = ClearDtcApproval(operationId: 'op', status: 'approved', commands: ['04']);

    Future<(ClearRecord, List<ScanSnapshot>)> run(String key, List<int> laterSeconds) async {
      var now = const Duration(seconds: 10);
      final wall0 = DateTime.utc(2026, 10, 22, 8);
      DateTime wall() => wall0.add(now);
      final emu = Elm327Emulator(loadScenario(key), table, clock: () => now, engineRunning: false, startEngineAfterClearS: 5);
      final client = ObdClient(transport: DemoTransport(emu, latency: Duration.zero), table: table);
      expect((await client.connect()).ecuOk, isTrue);
      final before = await client.snapshot(at: wall());
      final out = await client.clearDtcs(approval);
      expect(out.success, isTrue);
      final rec = ClearRecord(clearedAt: wall(), before: before, dataMode: 'demo');
      final checks = [await client.snapshot(at: wall())]; // immediate, same key cycle
      for (final s in laterSeconds) {
        now += Duration(seconds: s);
        checks.add(await client.snapshot(at: wall()));
      }
      await client.dispose();
      return (rec, checks);
    }

    test('p0106 fault still present → pending after 20 s, stored after 45 s → problem_confirmed', () async {
      final (rec, checks) = await run('p0106_map_sensor', [30, 30]);
      expect(rec.before.dtcs.map((d) => d.code), contains('P0106'));
      expect(rec.before.readiness, isNotNull);
      expect(checks[0].dtcs.where((d) => d.status != 'permanent'), isEmpty); // cleared
      expect(checks[0].warmupsSinceClear, 0);
      expect(checks[1].dtcs.any((d) => d.code == 'P0106' && d.status == 'pending'), isTrue);
      expect(checks[2].dtcs.any((d) => d.code == 'P0106' && d.status == 'stored'), isTrue);
      final v = assessAfterClear(rec, checks);
      expect(v.overall, 'problem_confirmed');
      final c = v.codes.firstWhere((x) => x.code == 'P0106');
      expect(c.verdict, 'returned_confirmed');
      expect(c.isRealProblem, isTrue);
      expect(c.titleAr, contains('حقيقي'));
    });

    test('old_code_repaired → monitors complete, permanent erased → likely_resolved', () async {
      final (rec, checks) = await run('old_code_repaired', [120]);
      expect(checks[0].dtcs.single.status, 'permanent');
      expect(checks.last.dtcs, isEmpty);
      expect(checks.last.warmupsSinceClear, 1);
      expect(incompleteMonitors(checks.last.readiness), isEmpty);
      final v = assessAfterClear(rec, checks);
      final p0102 = v.codes.firstWhere((x) => x.code == 'P0102');
      expect(p0102.verdict, 'not_returned_verified');
      expect(p0102.isRealProblem, isFalse);
      expect(p0102.titleAr, contains('غالبا عطل قديم'));
      expect(v.overall, 'likely_resolved');
    });

    test('immediate re-check alone is not proof', () async {
      final (rec, checks) = await run('old_code_repaired', []);
      expect(assessAfterClear(rec, checks).overall, 'verifying');
    });

    test('engine running at clear time: fault returns immediately as pending only after 20 s', () async {
      var now = const Duration(seconds: 10);
      final emu = Elm327Emulator(loadScenario('p0106_map_sensor'), table, clock: () => now, clearTimeScale: 10);
      emu.engineRunning = false;
      final client = ObdClient(transport: DemoTransport(emu, latency: Duration.zero), table: table);
      await client.connect();
      await client.readSupportedPids();
      await client.clearDtcs(approval);
      emu.engineRunning = true;
      now += const Duration(seconds: 3); // ×10 → 30 s since clear
      expect((await client.readDtcs(DtcStatus.pending)).dtcs.map((d) => d.code), ['P0106']);
      now += const Duration(seconds: 2); // 50 s
      expect((await client.readDtcs(DtcStatus.stored)).dtcs.map((d) => d.code), ['P0106']);
      expect(emu.handle('0131'), isNot(contains('NO DATA')));
      await client.dispose();
    });
  });
}
