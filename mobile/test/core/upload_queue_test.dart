import 'dart:io';

import 'package:automind_app/core/api/api_client.dart';
import 'package:automind_app/core/api/automind_api.dart';
import 'package:automind_app/core/api/token_store.dart';
import 'package:automind_app/core/storage/local_store.dart';
import 'package:automind_app/core/storage/scan_report.dart';
import 'package:automind_app/core/upload_queue.dart';
import 'package:automind_app/obd/obd.dart';
import 'package:flutter_test/flutter_test.dart';

import '../obd/helpers.dart';
import 'fake_adapter.dart';

void main() {
  late Directory dir;
  late LocalStore store;
  late MemoryTokenStore tokens;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('automind_q');
    store = LocalStore(dir);
    tokens = MemoryTokenStore()..tokens = const AuthTokens(accessToken: 'a1', refreshToken: 'r1');
  });

  Future<ScanReport> seed() async {
    final rec = Recorder(dataMode: DataMode.demo, sourceKind: 'simulator', table: loadTable(), newId: () => '3f2b8c1e-8d4a-4c1b-9a7e-2f1d3c4b5a69')
      ..vehicle = {'vin': 'AMDEMO1234567890X'}
      ..dtcs = [const Dtc('P0106', DtcStatus.stored, ecu: '7E8')];
    final r = rec.build();
    await store.saveRecording(r);
    final report = ScanReport(
      id: 'rep1',
      createdAt: DateTime.utc(2026),
      dataMode: 'demo',
      scenarioKey: 'p0106_map_sensor',
      recordingId: r.recordingId,
      dtcs: const [
        {'code': 'P0106', 'status': 'stored', 'ecu': '7E8'},
      ],
      connectionLog: const {'transport': 'demo'},
    );
    await store.saveReport(report);
    return report;
  }

  test('offline scan stays queued, then uploads in order when online (VIN redacted)', () async {
    Map<String, dynamic>? uploadedRecording;
    final adapter = FakeAdapter((o, body) {
      switch ('${o.method} ${o.path}') {
        case 'GET /health':
          return (200, {'status': 'ok'});
        case 'POST /sessions':
          expect((body as Map)['data_mode'], 'demo');
          expect(body['demo_scenario_key'], 'p0106_map_sensor');
          return (201, {'id': 's1', 'data_mode': 'demo'});
        case 'POST /sessions/s1/dtcs':
          expect(((body as Map)['dtcs'] as List).single['source_service'], '03');
          return (204, null);
        case 'POST /sessions/s1/recording':
          uploadedRecording = body as Map<String, dynamic>;
          return (201, {'id': 'rec1'});
        case 'POST /sessions/s1/complete':
          return (200, {'health_score': 72, 'health_band': 'attention', 'data_mode': 'demo', 'findings': []});
      }
      return (404, {'error': {'code': 'not_found', 'message': o.path}});
    });
    final dio = buildDio('http://test/api/v1', tokens)..httpClientAdapter = adapter;
    final queue = UploadQueue(store, AutomindApi(dio, tokens));
    final report = await seed();
    await queue.enqueue(report.id);

    adapter.offline = true;
    expect(await queue.process(), 0);
    expect(await queue.pending(), ['rep1']);

    adapter.offline = false;
    expect(await queue.process(), 1);
    expect(await queue.pending(), isEmpty);
    expect(adapter.calls, ['GET /health', 'POST /sessions', 'POST /sessions/s1/dtcs', 'POST /sessions/s1/recording', 'POST /sessions/s1/complete']);
    expect(uploadedRecording!['vehicle']['vin'], isNull);
    expect(uploadedRecording!['data_mode'], 'demo');
    final saved = await store.loadReport('rep1');
    expect(saved!.uploadState, 'uploaded');
    expect(saved.healthScore, 72);
    expect(saved.serverSessionId, 's1');
  });

  test('401 triggers exactly one refresh with the rotated token, then retries', () async {
    var meCalls = 0;
    final adapter = FakeAdapter((o, body) {
      final path = '${o.method} ${o.path}';
      if (path == 'GET /me') {
        meCalls++;
        if (o.headers['Authorization'] == 'Bearer a2') return (200, {'id': 'u1', 'email': 'x@y.z'});
        return (401, {'error': {'code': 'unauthorized', 'message': 'expired'}});
      }
      if (path == 'POST /auth/refresh') {
        expect((body as Map)['refresh_token'], 'r1');
        return (200, {'tokens': {'access_token': 'a2', 'refresh_token': 'r2', 'token_type': 'bearer', 'expires_in': 900}});
      }
      return (404, null);
    });
    final dio = buildDio('http://test/api/v1', tokens);
    dio.httpClientAdapter = adapter;
    // the refresh Dio shares options but has its own adapter: patch via interceptor
    final auth = dio.interceptors.whereType<AuthInterceptor>().single;
    auth.refreshDio.httpClientAdapter = adapter;
    final me = await AutomindApi(dio, tokens).me();
    expect(me['email'], 'x@y.z');
    expect(meCalls, 2);
    expect(tokens.tokens!.refreshToken, 'r2');
  });

  test('failed refresh clears tokens and surfaces unauthorized', () async {
    final adapter = FakeAdapter((o, body) => (401, {'error': {'code': 'unauthorized', 'message': 'nope'}}));
    final dio = buildDio('http://test/api/v1', tokens)..httpClientAdapter = adapter;
    dio.interceptors.whereType<AuthInterceptor>().single.refreshDio.httpClientAdapter = adapter;
    await expectLater(AutomindApi(dio, tokens).me(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
    expect(tokens.tokens, isNull);
  });
}
