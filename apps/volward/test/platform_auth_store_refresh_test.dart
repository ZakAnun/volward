import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:volward/ai/platform_auth_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const baseUrl = 'https://example.test/v1';
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final storage = <String, String>{};

  // exp = 2000000000 (2033-05-18)
  const validToken = 'eyJhbGciOiJub25lIn0.eyJleHAiOjIwMDAwMDAwMDB9.sig';

  setUp(() async {
    storage.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          final key = args['key'] as String;
          switch (call.method) {
            case 'read':
              return storage[key];
            case 'write':
              storage[key] = args['value'] as String;
              return null;
            case 'delete':
              storage.remove(key);
              return null;
            default:
              return null;
          }
        });
    PlatformAuthStore.instance.configureForTest(baseUrl: baseUrl);
    await PlatformAuthStore.instance.debugSetUserToken(null);
  });

  tearDown(() async {
    PlatformAuthStore.instance.configureForTest();
    await PlatformAuthStore.instance.debugSetUserToken(null);
    storage.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void seedDeviceUuid([String uuid = 'dev-uuid']) {
    storage['volward_device_uuid'] = uuid;
  }

  test('refreshSession 200 stores token and returns user', () async {
    seedDeviceUuid();
    final client = MockClient((req) async {
      expect(req.url.toString(), '$baseUrl/auth/refresh');
      expect(jsonDecode(req.body), {'device_uuid': 'dev-uuid'});
      return http.Response(
        jsonEncode({
          'token': validToken,
          'user_id': 'u1',
          'email': 'a@b.com',
          'credits': 5,
        }),
        200,
      );
    });
    PlatformAuthStore.instance.configureForTest(
      client: client,
      baseUrl: baseUrl,
    );

    final user = await PlatformAuthStore.instance.refreshSession();
    expect(user?.userId, 'u1');
    expect(user?.email, 'a@b.com');
    expect(user?.credits, 5);
    expect(await PlatformAuthStore.instance.userToken(), validToken);
  });

  test('refreshSession 403 returns null', () async {
    seedDeviceUuid();
    final client = MockClient((req) async => http.Response('{}', 403));
    PlatformAuthStore.instance.configureForTest(
      client: client,
      baseUrl: baseUrl,
    );

    expect(await PlatformAuthStore.instance.refreshSession(), isNull);
  });

  test(
    'refreshSession 404 calls ensureDeviceRegistered and returns null',
    () async {
      seedDeviceUuid();
      var registerCalled = false;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/auth/refresh')) {
          return http.Response('{}', 404);
        }
        if (req.url.path.endsWith('/device/register')) {
          registerCalled = true;
          return http.Response(jsonEncode({'token': 'device-token'}), 200);
        }
        fail('unexpected request: ${req.url}');
      });
      PlatformAuthStore.instance.configureForTest(
        client: client,
        baseUrl: baseUrl,
      );

      expect(await PlatformAuthStore.instance.refreshSession(), isNull);
      expect(registerCalled, isTrue);
    },
  );

  test('refreshSession 429 throws refresh_rate_limited', () async {
    seedDeviceUuid();
    final client = MockClient((req) async => http.Response('{}', 429));
    PlatformAuthStore.instance.configureForTest(
      client: client,
      baseUrl: baseUrl,
    );

    await expectLater(
      PlatformAuthStore.instance.refreshSession(),
      throwsA(predicate((e) => e.toString().contains('refresh_rate_limited'))),
    );
  });

  test('refreshSession 500 throws session_expired', () async {
    seedDeviceUuid();
    final client = MockClient((req) async => http.Response('{}', 500));
    PlatformAuthStore.instance.configureForTest(
      client: client,
      baseUrl: baseUrl,
    );

    await expectLater(
      PlatformAuthStore.instance.refreshSession(),
      throwsA(predicate((e) => e.toString().contains('session_expired'))),
    );
  });

  test('refreshSession returns null when device uuid missing', () async {
    var called = false;
    final client = MockClient((req) async {
      called = true;
      return http.Response('{}', 200);
    });
    PlatformAuthStore.instance.configureForTest(
      client: client,
      baseUrl: baseUrl,
    );

    expect(await PlatformAuthStore.instance.refreshSession(), isNull);
    expect(called, isFalse);
  });

  test(
    'ensureUserToken returns existing token when not expiring soon',
    () async {
      await PlatformAuthStore.instance.debugSetUserToken(validToken);
      var called = false;
      final client = MockClient((req) async {
        called = true;
        return http.Response('{}', 200);
      });
      PlatformAuthStore.instance.configureForTest(
        client: client,
        baseUrl: baseUrl,
      );

      final token = await PlatformAuthStore.instance.ensureUserToken();
      expect(token, validToken);
      expect(called, isFalse);
    },
  );

  test('ensureUserToken refreshes when token expiring soon', () async {
    seedDeviceUuid();
    // exp = 1 (1970) — always expiring soon
    const expiredToken = 'eyJhbGciOiJub25lIn0.eyJleHAiOjE.sig';
    await PlatformAuthStore.instance.debugSetUserToken(expiredToken);

    final client = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'token': validToken,
          'user_id': 'u1',
          'email': 'a@b.com',
          'credits': 0,
        }),
        200,
      );
    });
    PlatformAuthStore.instance.configureForTest(
      client: client,
      baseUrl: baseUrl,
    );

    final token = await PlatformAuthStore.instance.ensureUserToken();
    expect(token, validToken);
  });
}
