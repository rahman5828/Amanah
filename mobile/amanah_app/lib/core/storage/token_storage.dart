import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _accessTokenKey = 'amanah_access_token';
  static const String _refreshTokenKey = 'amanah_refresh_token';

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  /// Backward-compatible alias used by older call sites.
  static Future<void> saveToken(String accessToken) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
  }

  static Future<String?> getToken() async {
    return _storage.read(key: _accessTokenKey);
  }

  static Future<String?> getAccessToken() async {
    return _storage.read(key: _accessTokenKey);
  }

  static Future<String?> getRefreshToken() async {
    return _storage.read(key: _refreshTokenKey);
  }

  static Future<void> deleteToken() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  static Future<void> deleteTokens() async {
    await deleteToken();
  }
}
