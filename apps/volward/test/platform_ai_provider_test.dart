import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/platform_ai_provider.dart';
import 'package:volward/ai/platform_auth_store.dart';

void main() {
  tearDown(() async {
    await PlatformAuthStore.instance.debugSetUserToken(null);
    PlatformAuthStore.instance.debugUserToken = null;
  });

  test('402 maps to insufficient_credits', () async {
    final client = MockClient((req) async => http.Response('{}', 402));
    final p = PlatformAiProvider(
      token: 't',
      client: client,
      baseUrl: 'https://example.test/v1',
    );
    await expectLater(
      p.analyze([const AiCandidate(path: '/a', sizeBytes: 1, isDir: false)]),
      throwsA(predicate((e) => e.toString().contains('insufficient_credits'))),
    );
  });

  test(
    'unconfigured platform endpoint fails before making a request',
    () async {
      var requests = 0;
      final client = MockClient((req) async {
        requests++;
        return http.Response('{}', 500);
      });
      final p = PlatformAiProvider(token: 't', client: client, baseUrl: '');

      await expectLater(
        p.analyze([const AiCandidate(path: '/a', sizeBytes: 1, isDir: false)]),
        throwsA(
          predicate((e) => e.toString().contains('platform_api_unconfigured')),
        ),
      );
      expect(requests, 0);
    },
  );

  test(
    '401 clears the stored token so the user is guided to re-link',
    () async {
      await PlatformAuthStore.instance.debugSetUserToken('stale');
      final client = MockClient((req) async => http.Response('{}', 401));
      final p = PlatformAiProvider(
        token: 'stale',
        client: client,
        baseUrl: 'https://example.test/v1',
      );
      await expectLater(
        p.analyze([const AiCandidate(path: '/a', sizeBytes: 1, isDir: false)]),
        throwsA(predicate((e) => e.toString().contains('session_expired'))),
      );
      expect(await PlatformAuthStore.instance.userToken(), isNull);
    },
  );

  test('200 parses entries and credits_used', () async {
    final client = MockClient(
      (req) async => http.Response(
        '{"entries":[{"path":"/a","verdict":"keep","confidence":"high","reason":"x"}],'
        '"credits_used":1,"credits_remaining":9,"model":"deepseek-v4-flash"}',
        200,
      ),
    );
    final p = PlatformAiProvider(
      token: 't',
      client: client,
      baseUrl: 'https://example.test/v1',
    );
    final out = await p.analyze([
      const AiCandidate(path: '/a', sizeBytes: 1, isDir: false),
    ]);
    expect(out.single.verdict, 'keep');
    expect(p.lastCreditsUsed, 1);
    expect(p.lastCreditsRemaining, 9);
  });

  test('request body omits member_paths', () async {
    String? body;
    final client = MockClient((req) async {
      body = req.body;
      return http.Response(
        '{"entries":[],"credits_used":1,"credits_remaining":1,"model":"m"}',
        200,
      );
    });
    final p = PlatformAiProvider(
      token: 't',
      client: client,
      baseUrl: 'https://example.test/v1',
    );
    await p.analyze([
      const AiCandidate(
        path: '/a',
        sizeBytes: 1,
        isDir: true,
        memberPaths: ['/a/1', '/a/2'],
      ),
    ]);
    expect(body, isNotNull);
    expect(body!.contains('member_paths'), isFalse);
  });
}
