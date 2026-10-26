import 'dart:convert';
import 'dart:io';

import 'package:automind_app/core/clear/clear_audit.dart';
import 'package:automind_app/core/clear/clear_planner.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:automind_app/state/clear_controller.dart';
import 'package:automind_app/state/connection_controller.dart';
import 'package:automind_app/state/providers.dart';
import 'package:automind_app/state/scan_controller.dart';
import 'package:automind_app/state/verification_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../obd/helpers.dart';
import '../widget/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline engine clear: snapshot first, local approval, per-code result, full audit trail', () async {
    final c = ProviderContainer(retry: (_, _) => null, overrides: [
      ...await testOverrides(), // signed out → offline-first path
      demoLatencyProvider.overrideWithValue(Duration.zero),
      postClearRecheckDelayProvider.overrideWithValue(Duration.zero),
      scanCaptureDurationProvider.overrideWithValue(const Duration(seconds: 1)),
    ]);
    addTearDown(c.dispose);
    final conn = c.read(connectionProvider.notifier);
    await conn.connectDemo(c.read(appAssetsProvider).scenario('p0106_map_sensor')!);
    await c.read(scanProvider.notifier).run();
    final store = c.read(localStoreProvider);
    final report = (await store.loadReport(c.read(scanProvider).reportId!))!;
    final rec = await store.loadRecording(report.recordingId!);
    conn
      ..setEngineRunning(false)
      ..setAutoStartAfterClear(false); // engine stays off: the re-read reflects the clear itself

    final plan = planClear(recording: rec, connected: true, replay: false);
    final r = await c.read(clearProvider.notifier).clearTargets(report, plan.clearable.toList(), consentText: 'I understand');
    expect(r.ok, isTrue, reason: '${r.failure} ${r.detail}');
    final engine = r.results.single;
    expect(engine.key, 'engine');
    // The stored code is gone on the immediate re-read; the emulator keeps it as a
    // permanent (0A) code, which 04 never erases → honest "verification pending".
    expect(engine.codes['P0106'], 'verification_pending');
    final e = r.entry!;
    expect(e.record.operationId, startsWith('local-')); // no server involved
    expect(e.snapshotId, 'preclear_${r.operationId}');

    // The pre-clear snapshot is on disk and holds the erased codes + raw replies.
    final snap = jsonDecode(File('${store.root.path}/snapshots/${e.snapshotId}.json').readAsStringSync()) as Map;
    expect((snap['dtcs'] as List).map((d) => d['code']), contains('P0106'));
    expect(snap['raw_responses'], isNotEmpty);

    final events = await c.read(clearAuditProvider).read(reportId: report.id);
    final types = [for (final x in events) x['type']];
    expect(types.indexOf('snapshot_saved'), lessThan(types.indexOf('clear_sent'))); // snapshot BEFORE the command
    expect(types, containsAllInOrder(['clear_requested', 'consent_given', 'snapshot_saved', 'approval', 'clear_sent', 'clear_response', 'verification']));
    expect(events.firstWhere((x) => x['type'] == 'approval')['source'], 'local');

    final ops = ClearAuditLog.operations(events);
    expect(ops.single['service'], '04');
    expect(ops.single['before_snapshot_id'], e.snapshotId);
    expect(ops.single['result'], 'verification_pending');

    // … but the lamp is not claimed off unless the car reports MIL off or the user confirms.
    if (e.lampOffBy == null) {
      await c.read(clearProvider.notifier).confirmLampOff(e);
      final again = (await c.read(verificationProvider.notifier).byId(e.id))!;
      expect(again.lampOffBy, 'user');
    } else {
      expect(e.lampOffBy, 'module_status');
    }
  });

  test('a refused clear (engine running) is audited and nothing is sent', () async {
    final c = ProviderContainer(retry: (_, _) => null, overrides: [
      ...await testOverrides(),
      demoLatencyProvider.overrideWithValue(Duration.zero),
      scanCaptureDurationProvider.overrideWithValue(const Duration(seconds: 1)),
    ]);
    addTearDown(c.dispose);
    await c.read(connectionProvider.notifier).connectDemo(c.read(appAssetsProvider).scenario('p0106_map_sensor')!);
    await c.read(scanProvider.notifier).run();
    final report = (await c.read(localStoreProvider).loadReport(c.read(scanProvider).reportId!))!;
    final r = await c.read(clearProvider.notifier).clearAndVerify(report, consentText: 'ok');
    expect(r.failure, ClearFailure.engineRunning);
    final types = [for (final x in await c.read(clearAuditProvider).read(reportId: report.id)) x['type']];
    expect(types, ['clear_blocked']);
    expect(Directory('${c.read(localStoreProvider).root.path}/snapshots').existsSync(), isFalse);
  });

  group('UDS 0x14', () {
    test('reply parsing: positive, NRC, response-pending, silence', () {
      expect(parseClearReply('14FFFFFF', '54').positive, isTrue);
      final nrc = parseClearReply('14FFFFFF', '7F 14 22');
      expect(nrc.positive, isFalse);
      expect(nrc.nrc, 0x22);
      expect(nrc.nrcName, 'conditions_not_correct');
      expect(parseClearReply('14FFFFFF', '7F 14 78\r54').positive, isTrue); // pending, then OK
      expect(parseClearReply('14FFFFFF', '').noAnswer, isTrue);
    });

    const verified = UdsModule(
      key: 'bcm', nameEn: 'Body', nameAr: 'هيكل', requestId: 0x7A0, responseId: 0x7A8, verified: true, clearService: 'uds14',
    );
    const approval = ModuleClearApproval(operationId: 'op', status: 'approved', commands: ['14:bcm']);

    Future<(ObdClient, ScriptedTransport)> client(Map<String, String> replies) async {
      final t = ScriptedTransport({
        'ATZ': 'ELM327 v1.5', 'ATE0': 'OK', 'ATL0': 'OK', 'ATS1': 'OK', 'ATH1': 'OK', 'ATH0': 'OK', 'ATAT1': 'OK', 'ATSP0': 'OK',
        'ATI': 'ELM327 v1.5', 'AT@1': '?', 'ATRV': '12.5V', 'ATDPN': 'A6', 'ATDP': 'ISO 15765-4 (CAN 11/500)',
        '0100': '7E8 06 41 00 98 18 80 13', '010C': '7E8 04 41 0C 00 00', '010D': '7E8 03 41 0D 00',
        'ATSH7A0': 'OK', 'ATCRA7A8': 'OK', 'ATCRA': 'OK', 'ATSH7DF': 'OK',
        ...replies,
      });
      final c = ObdClient(transport: t, table: loadTable());
      await c.connect();
      await c.readSupportedPids();
      return (c, t);
    }

    test('gate: unverified / undocumented / unapproved modules are refused before anything is sent', () async {
      final (c, t) = await client({});
      const unverified = UdsModule(key: 'bcm', nameEn: 'b', nameAr: 'b', requestId: 0x7A0, responseId: 0x7A8, clearService: 'uds14');
      const undocumented = UdsModule(key: 'bcm', nameEn: 'b', nameAr: 'b', requestId: 0x7A0, responseId: 0x7A8, verified: true);
      await expectLater(c.clearModuleDtcs(unverified, approval), throwsA(isA<PolicyViolationException>()));
      await expectLater(c.clearModuleDtcs(undocumented, approval), throwsA(isA<PolicyViolationException>()));
      await expectLater(
        c.clearModuleDtcs(verified, const ModuleClearApproval(operationId: 'op', status: 'approved', commands: ['04'])),
        throwsA(isA<PolicyViolationException>()),
      );
      expect(t.sent.where((s) => s.startsWith('14')), isEmpty);
    });

    test('NRC is reported and no re-read pretends success', () async {
      final (c, _) = await client({'14FFFFFF': '7F 14 33'});
      final out = await c.clearModuleDtcs(verified, approval);
      expect(out.reply.nrc, 0x33);
      expect(out.reply.nrcName, 'security_access_denied');
      expect(out.after, isNull);
    });

    test('positive 0x54 is followed by a re-read that decides per code', () async {
      final (c, t) = await client({'14FFFFFF': '54', '1902FF': '59 02 FF 90 01 00 09'});
      final out = await c.clearModuleDtcs(verified, approval);
      expect(out.reply.positive, isTrue);
      expect(out.after!.dtcs.map((d) => d.code), ['B1001']); // still there after the clear
      expect(t.sent, contains('1902FF'));
    });
  });
}
