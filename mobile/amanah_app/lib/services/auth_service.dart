import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import '../core/errors/auth_exceptions.dart';
import '../core/storage/token_storage.dart';

class AuthService {
  AuthService({
    http.Client? httpClient,
    this.tokenStorage = const TokenStorageAdapter(),
  }) : _client = httpClient ?? http.Client();

  final http.Client _client;
  final TokenStorageAdapter tokenStorage;

  /// Single-flight lock so concurrent 401s share one refresh.
  Future<bool>? _refreshInFlight;

  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final response = await _safeRequest(
      () => _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}${ApiConfig.registerEndpoint}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'full_name': fullName,
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15)),
    );

    final data = _decodeJson(response);

    if (response.statusCode == 201) {
      return data;
    }

    throw _mapClientError(response.statusCode, data, fallback: 'Registration failed');
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? deviceLabel,
  }) async {
    final body = <String, dynamic>{
      'email': email,
      'password': password,
    };
    if (deviceLabel != null && deviceLabel.isNotEmpty) {
      body['device_label'] = deviceLabel;
    }

    final response = await _safeRequest(
      () => _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}${ApiConfig.loginEndpoint}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15)),
    );

    final data = _decodeJson(response);

    if (response.statusCode == 200) {
      final access = data['access_token'];
      final refresh = data['refresh_token'];
      if (access is! String || access.isEmpty) {
        throw const ResponseParseException('Login response missing access token');
      }
      if (refresh is! String || refresh.isEmpty) {
        throw const ResponseParseException('Login response missing refresh token');
      }
      await tokenStorage.saveTokens(accessToken: access, refreshToken: refresh);
      return data;
    }

    throw _mapClientError(response.statusCode, data, fallback: 'Login failed');
  }

  /// Exchange the stored refresh token for a new access + refresh pair.
  /// Returns true on success. Clears local credentials only when the server
  /// indicates the refresh token is invalid/expired/revoked (401).
  Future<bool> refreshSession() async {
    if (_refreshInFlight != null) {
      return _refreshInFlight!;
    }

    final completer = Completer<bool>();
    _refreshInFlight = completer.future;

    try {
      final refresh = await tokenStorage.getRefreshToken();
      if (refresh == null || refresh.isEmpty) {
        completer.complete(false);
        return false;
      }

      final response = await _safeRequest(
        () => _client
            .post(
              Uri.parse('${ApiConfig.baseUrl}${ApiConfig.refreshEndpoint}'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'refresh_token': refresh}),
            )
            .timeout(const Duration(seconds: 15)),
      );

      if (response.statusCode == 401) {
        await tokenStorage.deleteTokens();
        completer.complete(false);
        return false;
      }

      if (response.statusCode >= 500) {
        // Transient server error — keep credentials.
        completer.complete(false);
        return false;
      }

      final data = _decodeJson(response);
      if (response.statusCode != 200) {
        completer.complete(false);
        return false;
      }

      final access = data['access_token'];
      final newRefresh = data['refresh_token'];
      if (access is! String ||
          access.isEmpty ||
          newRefresh is! String ||
          newRefresh.isEmpty) {
        completer.complete(false);
        return false;
      }

      await tokenStorage.saveTokens(
        accessToken: access,
        refreshToken: newRefresh,
      );
      completer.complete(true);
      return true;
    } on NetworkException {
      completer.complete(false);
      return false;
    } on ResponseParseException {
      completer.complete(false);
      return false;
    } catch (_) {
      completer.complete(false);
      return false;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<Map<String, dynamic>> getProfile() async {
    return _authorizedGet(
      Uri.parse('${ApiConfig.baseUrl}${ApiConfig.profileEndpoint}'),
    );
  }

  /// Authenticated GET with a single silent refresh + retry on 401.
  Future<Map<String, dynamic>> _authorizedGet(Uri uri) async {
    final token = await tokenStorage.getAccessToken();
    if (token == null || token.isEmpty) {
      throw const NotAuthenticatedException();
    }

    final response = await _safeRequest(
      () => _client
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15)),
    );

    if (response.statusCode == 401) {
      final refreshed = await refreshSession();
      if (!refreshed) {
        // refreshSession already cleared tokens on 401 from /refresh.
        throw const SessionExpiredException();
      }
      final newToken = await tokenStorage.getAccessToken();
      if (newToken == null || newToken.isEmpty) {
        throw const SessionExpiredException();
      }
      final retry = await _safeRequest(
        () => _client
            .get(uri, headers: {'Authorization': 'Bearer $newToken'})
            .timeout(const Duration(seconds: 15)),
      );
      if (retry.statusCode == 401) {
        await tokenStorage.deleteTokens();
        throw const SessionExpiredException();
      }
      if (retry.statusCode >= 500) {
        throw const ServerException();
      }
      final retryData = _decodeJson(retry);
      if (retry.statusCode == 200) {
        return retryData;
      }
      throw _mapClientError(
        retry.statusCode,
        retryData,
        fallback: 'Unable to load profile',
        treat401AsSessionExpired: true,
      );
    }

    if (response.statusCode >= 500) {
      throw const ServerException();
    }

    final data = _decodeJson(response);

    if (response.statusCode == 200) {
      return data;
    }

    throw _mapClientError(
      response.statusCode,
      data,
      fallback: 'Unable to load profile',
      treat401AsSessionExpired: true,
    );
  }

  /// Revoke the current server session (best-effort) then clear local tokens.
  Future<void> logout() async {
    final refresh = await tokenStorage.getRefreshToken();
    if (refresh != null && refresh.isNotEmpty) {
      try {
        await _safeRequest(
          () => _client
              .post(
                Uri.parse('${ApiConfig.baseUrl}${ApiConfig.logoutEndpoint}'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'refresh_token': refresh}),
              )
              .timeout(const Duration(seconds: 10)),
        );
      } catch (_) {
        // Network/server failure during logout must not block local clear.
      }
    }
    await tokenStorage.deleteTokens();
  }

  Future<http.Response> _safeRequest(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request();
    } on TimeoutException {
      throw const NetworkException('Request timed out');
    } on SocketException {
      throw const NetworkException();
    } on http.ClientException {
      throw const NetworkException();
    } on HandshakeException {
      throw const NetworkException();
    }
  }

  Map<String, dynamic> _decodeJson(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw const ResponseParseException();
    } on FormatException {
      throw const ResponseParseException();
    } on ResponseParseException {
      rethrow;
    } catch (_) {
      throw const ResponseParseException();
    }
  }

  String? _extractDetail(Map<String, dynamic>? data) {
    if (data == null) return null;
    final detail = data['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    return null;
  }

  AuthException _mapClientError(
    int statusCode,
    Map<String, dynamic> data, {
    required String fallback,
    bool treat401AsSessionExpired = false,
  }) {
    final detail = _extractDetail(data) ?? fallback;

    if (statusCode == 401 && treat401AsSessionExpired) {
      return SessionExpiredException(detail);
    }
    if (statusCode == 403) {
      return ForbiddenException(detail);
    }
    if (statusCode >= 500) {
      return ServerException(detail);
    }
    return AuthException(detail);
  }
}

/// Thin adapter so tests can inject a fake token store without
/// touching FlutterSecureStorage.
class TokenStorageAdapter {
  const TokenStorageAdapter();

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) =>
      TokenStorage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

  /// Backward-compatible single-token write (access only).
  Future<void> saveToken(String token) => TokenStorage.saveToken(token);

  Future<String?> getToken() => TokenStorage.getToken();

  Future<String?> getAccessToken() => TokenStorage.getAccessToken();

  Future<String?> getRefreshToken() => TokenStorage.getRefreshToken();

  Future<void> deleteToken() => TokenStorage.deleteToken();

  Future<void> deleteTokens() => TokenStorage.deleteTokens();
}
