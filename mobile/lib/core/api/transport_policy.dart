import 'dart:io';

import 'package:dio/dio.dart';

import 'api_client.dart';

/// Login tokens and vehicle data may leave the device only over HTTPS.
/// Plain HTTP is allowed only to this machine (loopback, Android emulator host)
/// and to private LAN addresses, for running the backend on a local laptop.
bool isSecureBackendUri(Uri uri) {
  if (uri.scheme == 'https') return true;
  if (uri.scheme != 'http') return false;
  final host = uri.host.toLowerCase();
  if (host == 'localhost') return true;
  final ip = InternetAddress.tryParse(host);
  if (ip == null) return false;
  if (ip.isLoopback) return true;
  if (ip.type != InternetAddressType.IPv4) return false;
  final b = ip.rawAddress;
  return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168);
}

/// Blocks any request that would send data over plain HTTP to a public host.
class TransportSecurityInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (isSecureBackendUri(options.uri)) return handler.next(options);
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        error: ApiException(
          'insecure_backend',
          'عنوان الخادم يجب أن يبدأ بـ https:// — The server address must use https://',
        ),
      ),
    );
  }
}
