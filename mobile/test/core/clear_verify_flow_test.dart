import 'package:automind_app/core/api/api_client.dart';
import 'package:automind_app/core/api/automind_api.dart';
import 'package:automind_app/core/api/token_store.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:automind_app/state/clear_controller.dart';
import 'package:automind_app/state/connection_controller.dart';
import 'package:automind_app/state/providers.dart';
import 'package:automind_app/state/scan_controller.dart';
import 'package:automind_app/state/verification_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/test_app.dart';
import 'fake_adapter.dart';

/// End-to-end demo: scan → clear (server-approved) → wait (fake clock) →
/// later scan → verdict. The fake backend runs the same verdict algorithm.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, void Function(Duration), FakeAdapter)> setup() async {
    var now = const Duration(seconds: 10);
    final tokens = MemoryTokenStore()..tokens = const AuthTokens(accessToken: 'a', refreshToken: 'r');
    var session = 0;
    final opBodies = <Map>[];
    final adapter = FakeAdapter((o, body) {
      final path = '${o.method} ${o.path}';
      if (path == 'GET /health') return (200, {'status': 'ok'});
      if (path == 'GET /me') return (200, {'id': 'u1', 'email': 'owner@example.com'});
      if (path == 'POST /sessions') return (201, {'id': 's${++session}'});
      if (path.startsWith('POST /sessions/') && path.endsWith('/dtcs')) return (204, null);
      if (path.startsWith('POST /sessions/') && path.endsWith('/recording')) return (201, {'id': 'r'});
      if (path.startsWith('POST /sessions/') && path.endsWith('/complete')) {
        expect((body as Map)['readiness'], isA<Map>(), reason: 'readiness must be sent with complete');
        return (200, {'health_score': 70, 'health_band': 'attention', 'data_mode': 'demo', 'findings': []});
      }
      if (path == 'POST /control/operations') {
        opBodies.add(body as Map);
        expect(body['session_id'], isNotNull, reason: 'clear requires the saved session');
        expect(body['procedure_key'], 'clear_dtcs');
        return (201, {'id': 'op1', 'status': 'approved', 'commands': ['04']});
      }
      if (path == 'PATCH /control/operations/op1') return (204, null);
      if (path == 'POST /diagnosis/clear-verification') {
        final m = body as Map<String, dynamic>;
        final v = assessAfterClear(
          ClearRecord.fromJson(Map<String, dynamic>.from(m['record'] as Map)),
          [for (final c in m['checks'] as List) ScanSnapshot.fromJson(Map<String, dynamic>.from(c as Map))],
        );
        return (200, v.toJson());
      }
      return (404, {'error': {'code': 'not_found', 'message': path}});
    });
    final dio = buildDio('http://test/api/v1', tokens)..httpClientAdapter = adapter;
    dio.interceptors.whereType<AuthInterceptor>().single.refreshDio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        ...await testOverrides(tokens: tokens),
        apiProvider.overrideWithValue(AutomindApi(dio, tokens)),
        demoClockProvider.overrideWithValue(() => now),
        demoClearTimeScaleProvider.overrideWithValue(1),
        demoLatencyProvider.overrideWithValue(Duration.zero),
        postClearRecheckDelayProvider.overrideWithValue(Duration.zero),
        scanCaptureDurationProvider.overrideWithValue(const Duration(seconds: 1)),
      ],
    );
    addTearDown(container.dispose);
    expect(await container.read(authProvider.future), isNotNull);
    return (container, (Duration d) => now += d, adapter);
  }

  Future<String> clearScenario(ProviderContainer c, String key) async {
    final conn = c.read(connectionProvider.notifier);
    expect((await conn.connectDemo(c.read(appAssetsProvider).scenario(key)!)).ecuOk, isTrue);
    await c.read(scanProvider.notifier).run();
    final reportId = c.read(scanProvider).reportId!;
    final report = (await c.read(localStoreProvider).loadReport(reportId))!;
    expect(report.serverSessionId, isNotNull);
    expect(report.dtcs, isNotEmpty);
    final rec = await c.read(localStoreProvider).loadRecording(report.recordingId!);
    expect(rec!.readiness, isNotNull, reason: 'recording.readiness filled from 01 01');

    // Refused while the engine runs.
    final refused = await c.read(clearProvider.notifier).clearAndVerify(report, consentText: 'ok');
    expect(refused.failure, ClearFailure.engineRunning);

    conn.setEngineRunning(false); // "simulate engine off" switch
    final r = await c.read(clearProvider.notifier).clearAndVerify(report, consentText: 'I understand');
    expect(r.ok, isTrue, reason: '${r.failure} ${r.detail}');
    final e = r.entry!;
    expect(e.dataMode, 'demo');
    expect(e.sessionId, report.serverSessionId);
    expect(e.record.before.dtcs.map((d) => d.code), contains(report.dtcs.first['code']));
    expect(e.record.before.readiness, isNotNull);
    expect(e.checks, hasLength(1)); // immediate re-check
    expect(e.overall, 'verifying');
    expect(c.read(openVerificationProvider)?.id, e.id);
    return e.id;
  }

  test('p0106_map_sensor: the fault comes back → problem_confirmed', () async {
    final (c, advance, adapter) = await setup();
    final id = await clearScenario(c, 'p0106_map_sensor');
    advance(const Duration(seconds: 60)); // engine started 5 s after clear; stored after 45 s
    await c.read(scanProvider.notifier).run();
    expect(c.read(scanProvider).verificationId, id);
    final e = (await c.read(verificationProvider.notifier).byId(id))!;
    expect(e.checks, hasLength(2));
    expect(e.overall, 'problem_confirmed');
    expect(e.verificationSource, 'server');
    final v = e.verification!.codes.firstWhere((x) => x.code == 'P0106');
    expect(v.verdict, 'returned_confirmed');
    expect(e.verification!.summaryAr, contains('يوجد عطل حقيقي'));
    expect(e.verification!.summaryAr, startsWith('[تجريبي]'));
    expect(adapter.calls, contains('POST /diagnosis/clear-verification'));
  });

  test('old_code_repaired: stays away after the self-tests → likely_resolved', () async {
    final (c, advance, _) = await setup();
    final id = await clearScenario(c, 'old_code_repaired');
    advance(const Duration(seconds: 120)); // monitors complete at 90 s, warm-ups = 1
    await c.read(scanProvider.notifier).run();
    final e = (await c.read(verificationProvider.notifier).byId(id))!;
    expect(e.overall, 'likely_resolved');
    final v = e.verification!.codes.single;
    expect(v.code, 'P0102');
    expect(v.verdict, 'not_returned_verified');
    expect(v.titleAr, contains('غالبا عطل قديم'));
  });

  test('offline: the local Dart verdict is used', () async {
    final (c, advance, adapter) = await setup();
    final id = await clearScenario(c, 'p0106_map_sensor');
    advance(const Duration(seconds: 30)); // pending re-detected
    adapter.offline = true;
    final client = c.read(connectionProvider).client!;
    final e = await c.read(verificationProvider.notifier).addCheck(id, await client.snapshot());
    expect(e.verificationSource, 'local');
    expect(e.overall, 'problem_confirmed');
    expect(e.verification!.codes.firstWhere((x) => x.code == 'P0106').verdict, 'returned_pending');
  });
}
