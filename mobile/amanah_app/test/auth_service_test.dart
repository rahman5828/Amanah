import 'dart:async';
import 'dart:convert';

import 'package:amanah_app/core/errors/auth_exceptions.dart';
import 'package:amanah_app/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryTokenStorage extends TokenStorageAdapter {
  String? _token;

  @override
  Future<void> saveToken(String token) async {
    _token = token;
  }

  @override
  Future<String?> getToken() async => _token;

  @override
  Future<void> deleteToken() async {
    _token = null;
  }
}

void main() {
  late MemoryTokenStorage storage;
  final List<http.Client> clients = <http.Client>[];

  setUp(() {
    storage = MemoryTokenStorage();
  });

  tearDown(() {
    for (final client in clients) {
      client.close();
    }
    clients.clear();
  });

  http.Client track(http.Client client) {
    clients.add(client);
    return client;
  }

  group('AuthService.getProfile', () {
    test('missing token throws NotAuthenticatedException', () async {
      final service = AuthService(
        httpClient: track(MockClient((_) async => http.Response('', 500))),
        tokenStorage: storage,
      );

      expect(
        () => service.getProfile(),
        throwsA(isA<NotAuthenticatedException>()),
      );
      expect(await storage.getToken(), isNull);
    });

    test('valid token returns profile', () async {
      await storage.saveToken('valid-token');

      final service = AuthService(
        httpClient: track(MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer valid-token');
          return http.Response(
            jsonEncode({
              'id': '00000000-0000-0000-0000-000000000001',
              'full_name': 'Test User',
              'email': 'test@example.com',
              'created_at': '2026-01-01T00:00:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        })),
        tokenStorage: storage,
      );

      final profile = await service.getProfile();
      expect(profile['full_name'], 'Test User');
      expect(await storage.getToken(), 'valid-token');
    });

    test('HTTP 401 clears token and throws SessionExpiredException', () async {
      await storage.saveToken('expired-token');

      final service = AuthService(
        httpClient: track(MockClient(
          (_) async => http.Response(
            jsonEncode({'detail': 'Invalid or expired access token.'}),
            401,
            headers: {'content-type': 'application/json'},
          ),
        )),
        tokenStorage: storage,
      );

      expect(
        () => service.getProfile(),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(await storage.getToken(), isNull);
    });

    test('HTTP 403 keeps token and throws ForbiddenException', () async {
      await storage.saveToken('forbidden-token');

      final service = AuthService(
        httpClient: track(MockClient(
          (_) async => http.Response(
            jsonEncode({'detail': 'Forbidden'}),
            403,
            headers: {'content-type': 'application/json'},
          ),
        )),
        tokenStorage: storage,
      );

      expect(
        () => service.getProfile(),
        throwsA(isA<ForbiddenException>()),
      );
      expect(await storage.getToken(), 'forbidden-token');
    });

    test('HTTP 5xx keeps token and throws ServerException', () async {
      await storage.saveToken('ok-token');

      final service = AuthService(
        httpClient: track(MockClient(
          (_) async => http.Response('Internal Server Error', 500),
        )),
        tokenStorage: storage,
      );

      expect(
        () => service.getProfile(),
        throwsA(isA<ServerException>()),
      );
      expect(await storage.getToken(), 'ok-token');
    });

    test('malformed JSON keeps token and throws ResponseParseException', () async {
      await storage.saveToken('ok-token');

      final service = AuthService(
        httpClient: track(MockClient(
          (_) async => http.Response('not-json', 200),
        )),
        tokenStorage: storage,
      );

      expect(
        () => service.getProfile(),
        throwsA(isA<ResponseParseException>()),
      );
      expect(await storage.getToken(), 'ok-token');
    });

    test('network timeout keeps token and throws NetworkException', () async {
      await storage.saveToken('ok-token');

      final service = AuthService(
        httpClient: track(MockClient((_) async {
          throw TimeoutException('timeout');
        })),
        tokenStorage: storage,
      );

      expect(
        () => service.getProfile(),
        throwsA(isA<NetworkException>()),
      );
      expect(await storage.getToken(), 'ok-token');
    });
  });

  group('AuthService.logout', () {
    test('clears stored token', () async {
      await storage.saveToken('to-delete');
      final service = AuthService(
        httpClient: track(MockClient((_) async => http.Response('', 200))),
        tokenStorage: storage,
      );

      await service.logout();
      expect(await storage.getToken(), isNull);
    });
  });

  group('AuthService.login', () {
    test('saves token on success', () async {
      final service = AuthService(
        httpClient: track(MockClient(
          (_) async => http.Response(
            jsonEncode({
              'access_token': 'new-access-token',
              'token_type': 'bearer',
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        )),
        tokenStorage: storage,
      );

      await service.login(email: 'a@b.com', password: 'password12');
      expect(await storage.getToken(), 'new-access-token');
    });

    test('does not save token on failure', () async {
      final service = AuthService(
        httpClient: track(MockClient(
          (_) async => http.Response(
            jsonEncode({'detail': 'Invalid email or password.'}),
            401,
            headers: {'content-type': 'application/json'},
          ),
        )),
        tokenStorage: storage,
      );

      expect(
        () => service.login(email: 'a@b.com', password: 'wrong'),
        throwsA(isA<AuthException>()),
      );
      expect(await storage.getToken(), isNull);
    });
  });
}
