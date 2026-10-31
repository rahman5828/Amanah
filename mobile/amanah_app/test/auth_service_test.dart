import 'dart:async';
import 'dart:convert';

import 'package:amanah_app/core/errors/auth_exceptions.dart';
import 'package:amanah_app/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryTokenStorage extends TokenStorageAdapter {
  String? _access;
  String? _refresh;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _access = accessToken;
    _refresh = refreshToken;
  }

  @override
  Future<void> saveToken(String token) async {
    _access = token;
  }

  @override
  Future<String?> getToken() async => _access;

  @override
  Future<String?> getAccessToken() async => _access;

  @override
  Future<String?> getRefreshToken() async => _refresh;

  @override
  Future<void> deleteToken() async {
    _access = null;
    _refresh = null;
  }

  @override
  Future<void> deleteTokens() async {
    await deleteToken();
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

      await expectLater(
        service.getProfile(),
        throwsA(isA<NotAuthenticatedException>()),
      );
    });

    test('401 without refreshable session clears token and throws SessionExpired',
        () async {
      await storage.saveTokens(
        accessToken: 'expired-token',
        refreshToken: 'bad-refresh',
      );

      final service = AuthService(
        httpClient: track(MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            return http.Response(
              jsonEncode({'detail': 'Invalid or expired refresh token.'}),
              401,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({'detail': 'Not authenticated'}),
            401,
            headers: {'content-type': 'application/json'},
          );
        })),
        tokenStorage: storage,
      );

      await expectLater(
        service.getProfile(),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(await storage.getToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
    });

    test('401 then successful refresh retries and succeeds', () async {
      await storage.saveTokens(
        accessToken: 'expired-access',
        refreshToken: 'valid-refresh',
      );

      var profileCalls = 0;
      final service = AuthService(
        httpClient: track(MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            return http.Response(
              jsonEncode({
                'access_token': 'new-access',
                'refresh_token': 'new-refresh',
                'token_type': 'bearer',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          profileCalls++;
          if (profileCalls == 1) {
            return http.Response(
              jsonEncode({'detail': 'Token expired'}),
              401,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'id': 'u1',
              'full_name': 'Test',
              'email': 't@example.com',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        })),
        tokenStorage: storage,
      );

      final profile = await service.getProfile();
      expect(profile['email'], 't@example.com');
      expect(await storage.getAccessToken(), 'new-access');
      expect(await storage.getRefreshToken(), 'new-refresh');
      expect(profileCalls, 2);
    });

    test('403 keeps token and throws ForbiddenException', () async {
      await storage.saveToken('ok-token');

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

      await expectLater(
        service.getProfile(),
        throwsA(isA<ForbiddenException>()),
      );
      expect(await storage.getToken(), 'ok-token');
    });

    test('500 keeps token and throws ServerException', () async {
      await storage.saveToken('ok-token');

      final service = AuthService(
        httpClient: track(MockClient(
          (_) async => http.Response('Internal Server Error', 500),
        )),
        tokenStorage: storage,
      );

      await expectLater(
        service.getProfile(),
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

      await expectLater(
        service.getProfile(),
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

      await expectLater(
        service.getProfile(),
        throwsA(isA<NetworkException>()),
      );
      expect(await storage.getToken(), 'ok-token');
    });
  });

  group('AuthService.refreshSession', () {
    test('successful refresh stores new pair', () async {
      await storage.saveTokens(
        accessToken: 'old-a',
        refreshToken: 'old-r',
      );

      final service = AuthService(
        httpClient: track(MockClient(
          (_) async => http.Response(
            jsonEncode({
              'access_token': 'fresh-a',
              'refresh_token': 'fresh-r',
              'token_type': 'bearer',
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        )),
        tokenStorage: storage,
      );

      final ok = await service.refreshSession();
      expect(ok, isTrue);
      expect(await storage.getAccessToken(), 'fresh-a');
      expect(await storage.getRefreshToken(), 'fresh-r');
    });

    test('401 on refresh clears tokens', () async {
      await storage.saveTokens(
        accessToken: 'a',
        refreshToken: 'revoked',
      );

      final service = AuthService(
        httpClient: track(MockClient(
          (_) async => http.Response(
            jsonEncode({'detail': 'Invalid or expired refresh token.'}),
            401,
            headers: {'content-type': 'application/json'},
          ),
        )),
        tokenStorage: storage,
      );

      final ok = await service.refreshSession();
      expect(ok, isFalse);
      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
    });

    test('network failure during refresh preserves tokens', () async {
      await storage.saveTokens(accessToken: 'a', refreshToken: 'r');

      final service = AuthService(
        httpClient: track(MockClient((_) async {
          throw TimeoutException('timeout');
        })),
        tokenStorage: storage,
      );

      final ok = await service.refreshSession();
      expect(ok, isFalse);
      expect(await storage.getAccessToken(), 'a');
      expect(await storage.getRefreshToken(), 'r');
    });

    test('server 500 during refresh preserves tokens', () async {
      await storage.saveTokens(accessToken: 'a', refreshToken: 'r');

      final service = AuthService(
        httpClient: track(MockClient(
          (_) async => http.Response('error', 503),
        )),
        tokenStorage: storage,
      );

      final ok = await service.refreshSession();
      expect(ok, isFalse);
      expect(await storage.getAccessToken(), 'a');
      expect(await storage.getRefreshToken(), 'r');
    });

    test('concurrent refreshSession calls share a single in-flight request',
        () async {
      await storage.saveTokens(accessToken: 'a', refreshToken: 'r');
      var refreshHits = 0;
      final gate = Completer<void>();

      final service = AuthService(
        httpClient: track(MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            refreshHits++;
            await gate.future;
            return http.Response(
              jsonEncode({
                'access_token': 'shared-a',
                'refresh_token': 'shared-r',
                'token_type': 'bearer',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('', 500);
        })),
        tokenStorage: storage,
      );

      final f1 = service.refreshSession();
      final f2 = service.refreshSession();
      gate.complete();
      final results = await Future.wait([f1, f2]);
      expect(results, [true, true]);
      expect(refreshHits, 1);
      expect(await storage.getAccessToken(), 'shared-a');
    });
  });

  group('AuthService.logout', () {
    test('clears stored tokens even if server logout fails', () async {
      await storage.saveTokens(accessToken: 'a', refreshToken: 'r');
      final service = AuthService(
        httpClient: track(MockClient((_) async {
          throw TimeoutException('offline');
        })),
        tokenStorage: storage,
      );

      await service.logout();
      expect(await storage.getToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
    });

    test('posts refresh token to logout endpoint then clears', () async {
      await storage.saveTokens(accessToken: 'a', refreshToken: 'r-token');
      http.BaseRequest? captured;

      final service = AuthService(
        httpClient: track(MockClient((request) async {
          captured = request;
          return http.Response('', 204);
        })),
        tokenStorage: storage,
      );

      await service.logout();
      expect(await storage.getToken(), isNull);
      expect(captured?.url.path, contains('/auth/logout'));
    });
  });

  group('AuthService.login', () {
    test('saves both access and refresh tokens on success', () async {
      final service = AuthService(
        httpClient: track(MockClient(
          (_) async => http.Response(
            jsonEncode({
              'access_token': 'new-access-token',
              'refresh_token': 'new-refresh-token',
              'token_type': 'bearer',
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        )),
        tokenStorage: storage,
      );

      await service.login(email: 'a@b.com', password: 'password12');
      expect(await storage.getAccessToken(), 'new-access-token');
      expect(await storage.getRefreshToken(), 'new-refresh-token');
    });

    test('does not save tokens on failure', () async {
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

      await expectLater(
        service.login(email: 'a@b.com', password: 'wrong'),
        throwsA(isA<AuthException>()),
      );
      expect(await storage.getToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
    });

    test('missing refresh_token in response throws ResponseParseException',
        () async {
      final service = AuthService(
        httpClient: track(MockClient(
          (_) async => http.Response(
            jsonEncode({
              'access_token': 'only-access',
              'token_type': 'bearer',
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        )),
        tokenStorage: storage,
      );

      await expectLater(
        service.login(email: 'a@b.com', password: 'password12'),
        throwsA(isA<ResponseParseException>()),
      );
      expect(await storage.getToken(), isNull);
    });
  });
}
