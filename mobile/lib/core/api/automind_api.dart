import 'package:dio/dio.dart';

import 'api_client.dart';
import 'token_store.dart';

/// Typed wrapper of docs/API.md. Every method throws [ApiException].
class AutomindApi {
  AutomindApi(this.dio, this.tokens);

  final Dio dio;
  final TokenStore tokens;

  static const String termsVersion = '1.0';
  static const String privacyVersion = '1.0';

  Future<T> _call<T>(Future<Response<dynamic>> Function() f) async {
    try {
      final r = await f();
      return r.data as T;
    } on Object catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<bool> isReachable() async {
    try {
      await dio.get<dynamic>('/health', options: Options(extra: {'noAuth': true}, receiveTimeout: const Duration(seconds: 4)));
      return true;
    } on Object catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------ auth
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? fullName,
    required String locale,
  }) async {
    final r = await _call<Map<String, dynamic>>(() => dio.post('/auth/register',
        data: {
          'email': email,
          'password': password,
          'full_name': ?fullName,
          'locale': locale,
          'accept_terms_version': termsVersion,
          'accept_privacy_version': privacyVersion,
        },
        options: Options(extra: {'noAuth': true})));
    await tokens.write(AuthTokens.fromJson(r['tokens'] as Map<String, dynamic>));
    return r['user'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login({required String email, required String password, String? totp}) async {
    final r = await _call<Map<String, dynamic>>(() => dio.post('/auth/login',
        data: {'email': email, 'password': password, 'totp_code': ?totp}, options: Options(extra: {'noAuth': true})));
    await tokens.write(AuthTokens.fromJson(r['tokens'] as Map<String, dynamic>));
    return r['user'] as Map<String, dynamic>;
  }

  Future<void> logout() async {
    final t = await tokens.read();
    if (t != null) {
      try {
        await dio.post<dynamic>('/auth/logout', data: {'refresh_token': t.refreshToken});
      } on Object catch (_) {}
    }
    await tokens.clear();
  }

  Future<Map<String, dynamic>> me() => _call(() => dio.get('/me'));

  // ------------------------------------------------------------- vehicles
  Future<List<Map<String, dynamic>>> vehicles() async {
    final r = await _call<Map<String, dynamic>>(() => dio.get('/vehicles', queryParameters: {'limit': 100}));
    return [for (final i in r['items'] as List) i as Map<String, dynamic>];
  }

  Future<Map<String, dynamic>> createVehicle(Map<String, dynamic> body) => _call(() => dio.post('/vehicles', data: body));
  Future<Map<String, dynamic>> updateVehicle(String id, Map<String, dynamic> body) =>
      _call(() => dio.patch('/vehicles/$id', data: body));
  Future<void> deleteVehicle(String id) => _call(() => dio.delete('/vehicles/$id'));

  Future<List<Map<String, dynamic>>> maintenance(String vehicleId) async {
    final r = await _call<dynamic>(() => dio.get('/vehicles/$vehicleId/maintenance'));
    final items = r is Map ? r['items'] as List : r as List;
    return [for (final i in items) i as Map<String, dynamic>];
  }

  Future<Map<String, dynamic>> addMaintenance(String vehicleId, Map<String, dynamic> body) =>
      _call(() => dio.post('/vehicles/$vehicleId/maintenance', data: body));

  // ------------------------------------------------- devices / connections
  Future<Map<String, dynamic>> createDevice(Map<String, dynamic> body) => _call(() => dio.post('/devices', data: body));
  Future<String> postConnection(Map<String, dynamic> body) async {
    final r = await _call<Map<String, dynamic>>(() => dio.post('/connections', data: body));
    return r['id'] as String;
  }

  // -------------------------------------------------------------- sessions
  Future<Map<String, dynamic>> createSession(Map<String, dynamic> body) => _call(() => dio.post('/sessions', data: body));
  Future<List<Map<String, dynamic>>> sessions() async {
    final r = await _call<Map<String, dynamic>>(() => dio.get('/sessions', queryParameters: {'limit': 50}));
    return [for (final i in r['items'] as List) i as Map<String, dynamic>];
  }

  Future<void> postDtcs(String sessionId, List<Map<String, dynamic>> dtcs) =>
      _call(() => dio.post('/sessions/$sessionId/dtcs', data: {'dtcs': dtcs}));
  Future<Map<String, dynamic>> uploadSessionRecording(String sessionId, Map<String, dynamic> recording) =>
      _call(() => dio.post('/sessions/$sessionId/recording', data: recording));
  Future<Map<String, dynamic>> completeSession(String sessionId, {bool? milOn, String language = 'ar'}) =>
      _call(() => dio.post('/sessions/$sessionId/complete', data: {'mil_on': ?milOn, 'language': language}));
  Future<Map<String, dynamic>> diagnosis(String sessionId) => _call(() => dio.get('/sessions/$sessionId/diagnosis'));

  Future<Map<String, dynamic>> analyze(Map<String, dynamic> recording, {String language = 'ar'}) =>
      _call(() => dio.post('/diagnosis/analyze', data: {'recording': recording, 'language': language}));

  // ------------------------------------------------------------ recordings
  Future<List<Map<String, dynamic>>> recordings() async {
    final r = await _call<Map<String, dynamic>>(() => dio.get('/recordings', queryParameters: {'limit': 50}));
    return [for (final i in r['items'] as List) i as Map<String, dynamic>];
  }

  Future<Map<String, dynamic>> uploadRecording(Map<String, dynamic> recording) =>
      _call(() => dio.post('/recordings', data: recording));
  Future<Map<String, dynamic>> recording(String id) => _call(() => dio.get('/recordings/$id'));
  Future<Map<String, dynamic>> replayRecording(String id, {String language = 'ar'}) =>
      _call(() => dio.post('/recordings/$id/replay', data: {'language': language}));

  // ------------------------------------------------------------ demo / kb
  Future<List<dynamic>> demoScenarios() => _call(() => dio.get('/demo/scenarios'));
  Future<Map<String, dynamic>> kbDtc(String code) => _call(() => dio.get('/kb/dtc/$code'));

  // --------------------------------------------------------------- control
  Future<Map<String, dynamic>> requestOperation(Map<String, dynamic> body) =>
      _call(() => dio.post('/control/operations', data: body));
  Future<void> reportOperation(String id, Map<String, dynamic> body) =>
      _call(() => dio.patch('/control/operations/$id', data: body));
}
