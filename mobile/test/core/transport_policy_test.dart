import 'package:automind_app/core/api/api_client.dart';
import 'package:automind_app/core/api/token_store.dart';
import 'package:automind_app/core/api/transport_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('https is always allowed', () {
    expect(isSecureBackendUri(Uri.parse('https://api.automind.ai/api/v1')), isTrue);
  });

  test('plain http only to this machine or the private LAN', () {
    for (final ok in [
      'http://localhost:8000',
      'http://127.0.0.1:8000',
      'http://[::1]:8000',
      'http://10.0.2.2:8000',
      'http://192.168.1.20:8000',
      'http://172.20.0.5:8000',
    ]) {
      expect(isSecureBackendUri(Uri.parse(ok)), isTrue, reason: ok);
    }
    for (final bad in [
      'http://api.automind.ai',
      'http://8.8.8.8',
      'http://172.32.0.1',
      'http://192.169.0.1',
      'ftp://192.168.0.10',
      'http://localhost.evil.com',
    ]) {
      expect(isSecureBackendUri(Uri.parse(bad)), isFalse, reason: bad);
    }
  });

  test('a request to a public http host is blocked before the token is attached', () async {
    final tokens = MemoryTokenStore()..tokens = const AuthTokens(accessToken: 'a', refreshToken: 'r');
    final dio = buildDio('http://api.example.com/api/v1', tokens);
    Object? caught;
    try {
      await dio.get<dynamic>('/me');
    } catch (e) {
      caught = ApiException.from(e);
    }
    expect(caught, isA<ApiException>());
    expect((caught! as ApiException).code, 'insecure_backend');
  });
}
