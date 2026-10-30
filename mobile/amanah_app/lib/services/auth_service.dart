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
  }) async {
    final response = await _safeRequest(
      () => _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}${ApiConfig.loginEndpoint}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15)),
    );

    final data = _decodeJson(response);

    if (response.statusCode == 200) {
      final token = data['access_token'];
      if (token is! String || token.isEmpty) {
        throw const ResponseParseException('Login response missing access token');
      }
      await tokenStorage.saveToken(token);
      return data;
    }

    throw _mapClientError(response.statusCode, data, fallback: 'Login failed');
  }

  Future<Map<String, dynamic>> getProfile() async {
    final token = await tokenStorage.getToken();

    if (token == null || token.isEmpty) {
      throw const NotAuthenticatedException();
    }

    final response = await _safeRequest(
      () => _client
          .get(
            Uri.parse('${ApiConfig.baseUrl}${ApiConfig.profileEndpoint}'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15)),
    );

    // 401: invalid/expired session — clear token before throwing.
    if (response.statusCode == 401) {
      await tokenStorage.deleteToken();
      throw const SessionExpiredException();
    }

    // 403: authenticated but forbidden — keep token.
    if (response.statusCode == 403) {
      final data = _tryDecodeJson(response);
      final detail = _extractDetail(data);
      throw ForbiddenException(detail ?? 'Access denied');
    }

    // 5xx: server problems — keep token.
    if (response.statusCode >= 500) {
      throw const ServerException();
    }

    final data = _decodeJson(response);

    if (response.statusCode == 200) {
      return data;
    }

    throw _mapClientError(response.statusCode, data, fallback: 'Unable to load profile');
  }

  Future<void> logout() async {
    await tokenStorage.deleteToken();
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

  Map<String, dynamic>? _tryDecodeJson(http.Response response) {
    try {
      return _decodeJson(response);
    } catch (_) {
      return null;
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

    // Login/register 401 is invalid credentials, not a stored-session expiry.
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

  Future<void> saveToken(String token) => TokenStorage.saveToken(token);

  Future<String?> getToken() => TokenStorage.getToken();

  Future<void> deleteToken() => TokenStorage.deleteToken();
}
