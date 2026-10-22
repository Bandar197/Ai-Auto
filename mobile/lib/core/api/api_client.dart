import 'package:dio/dio.dart';

import 'token_store.dart';

/// API error with the backend's `{error: {code, message}}` envelope.
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.status});
  final String code;
  final String message;
  final int? status;

  bool get isOffline => code == 'offline';

  @override
  String toString() => message.isEmpty ? code : message;

  static ApiException from(Object e) {
    if (e is ApiException) return e;
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] is Map) {
        final err = data['error'] as Map;
        return ApiException('${err['code']}', '${err['message'] ?? ''}', status: e.response?.statusCode);
      }
      if (e.response == null) {
        return ApiException('offline', e.message ?? 'network unreachable');
      }
      return ApiException('http_${e.response?.statusCode}', e.message ?? '', status: e.response?.statusCode);
    }
    return ApiException('error', e.toString());
  }
}

/// Adds the bearer token and refreshes it once on 401 (refresh tokens are
/// rotated by the server on every use, so the new pair is stored).
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this.tokens, this.refreshDio, {this.onLoggedOut});

  final TokenStore tokens;
  final Dio refreshDio;
  final void Function()? onLoggedOut;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final t = await tokens.read();
    if (t != null && options.extra['noAuth'] != true) {
      options.headers['Authorization'] = 'Bearer ${t.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    if (err.response?.statusCode != 401 || req.extra['retried'] == true || req.extra['noAuth'] == true) {
      return handler.next(err);
    }
    final t = await tokens.read();
    if (t == null) return handler.next(err);
    try {
      final r = await refreshDio.post<Map<String, dynamic>>('/auth/refresh', data: {'refresh_token': t.refreshToken});
      final body = r.data!;
      final tok = (body['tokens'] ?? body) as Map<String, dynamic>;
      final fresh = AuthTokens.fromJson(tok);
      await tokens.write(fresh);
      req.headers['Authorization'] = 'Bearer ${fresh.accessToken}';
      req.extra['retried'] = true;
      final retry = await refreshDio.fetch<dynamic>(req);
      return handler.resolve(retry);
    } on DioException catch (_) {
      await tokens.clear();
      onLoggedOut?.call();
      return handler.next(err);
    }
  }
}

Dio buildDio(String baseUrl, TokenStore tokens, {void Function()? onLoggedOut}) {
  final options = BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 60),
    contentType: Headers.jsonContentType,
    responseType: ResponseType.json,
  );
  final dio = Dio(options);
  final refreshDio = Dio(options);
  dio.interceptors.add(AuthInterceptor(tokens, refreshDio, onLoggedOut: onLoggedOut));
  return dio;
}
