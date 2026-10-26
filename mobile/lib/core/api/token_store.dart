import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});
  final String accessToken;
  final String refreshToken;

  factory AuthTokens.fromJson(Map<String, dynamic> j) =>
      AuthTokens(accessToken: j['access_token'] as String, refreshToken: j['refresh_token'] as String);
}

/// Token persistence. Production uses the platform keystore/keychain.
abstract class TokenStore {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens t);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  static const _a = 'automind.access_token';
  static const _r = 'automind.refresh_token';

  @override
  Future<AuthTokens?> read() async {
    final a = await _s.read(key: _a);
    final r = await _s.read(key: _r);
    if (a == null || r == null) return null;
    return AuthTokens(accessToken: a, refreshToken: r);
  }

  @override
  Future<void> write(AuthTokens t) async {
    await _s.write(key: _a, value: t.accessToken);
    await _s.write(key: _r, value: t.refreshToken);
  }

  @override
  Future<void> clear() async {
    await _s.delete(key: _a);
    await _s.delete(key: _r);
  }
}

class MemoryTokenStore implements TokenStore {
  AuthTokens? tokens;
  @override
  Future<AuthTokens?> read() async => tokens;
  @override
  Future<void> write(AuthTokens t) async => tokens = t;
  @override
  Future<void> clear() async => tokens = null;
}
