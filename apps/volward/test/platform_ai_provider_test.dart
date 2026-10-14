import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:volward/ai/ai_conclusion_synthesis.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/coverage_models.dart';
import 'package:volward/ai/platform_ai_provider.dart';
import 'package:volward/ai/platform_auth_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const baseUrl = 'https://example.test/v1';
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final storage = <String, String>{};

  // exp = 2000000000 (2033-05-18)
  const validToken = 'eyJhbGciOiJub25lIn0.eyJleHAiOjIwMDAwMDAwMDB9.sig';
  const staleToken =
      'eyJhbGciOiJub25lIn0.eyJleHAiOjIwMDAwMDAwMDAsInN0YWxlIjp0cnVlfQ.sig';

  setUp(() {
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
  });

  tearDown(() async {
    PlatformAuthStore.instance.configureForTest();
    await PlatformAuthStore.instance.debugSetUserToken(null);
    PlatformAuthStore.instance.debugUserToken = null;
    storage.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  const minimalSynthesisRequest = AiConclusionSynthesisRequest(
    analysisSessionId: 'sess-1',
    locale: 'en',
    rootLabel: 'Home',
    scan: AiConclusionSynthesisScan(
      rootPath: '/tmp',
      truncated: false,
      fullCoverage: true,
    ),
    totals: AiConclusionSynthesisTotals(
      safeBytes: 100,
      reviewCount: 0,
      keepCount: 1,
      analyzedItemCount: 1,
      analyzedTotalBytes: 200,
      rootSizeBytes: 500,
    ),
    directories: [],
  );

  test('402 maps to insufficient_credits', () async {
    await PlatformAuthStore.instance.debugSetUserToken(validToken);
    final client = MockClient((req) async => http.Response('{}', 402));
    final p = PlatformAiProvider(
      token: validToken,
      client: client,
      baseUrl: baseUrl,
    );
    await expectLater(
      p.analyze([const AiCandidate(path: '/a', sizeBytes: 1, isDir: false)]),
      throwsA(predicate((e) => e.toString().contains('insufficient_credits'))),
    );
  });

  test('synthesizeConclusion 402 maps to insufficient_credits', () async {
    await PlatformAuthStore.instance.debugSetUserToken(validToken);
    final client = MockClient((req) async => http.Response('{}', 402));
    final p = PlatformAiProvider(
      token: validToken,
      client: client,
      baseUrl: baseUrl,
    );
    await expectLater(
      p.synthesizeConclusion(minimalSynthesisRequest),
      throwsA(predicate((e) => e.toString().contains('insufficient_credits'))),
    );
  });

  test('synthesizeConclusion posts JSON and parses text', () async {
    await PlatformAuthStore.instance.debugSetUserToken(validToken);
    String? path;
    String? body;
    final client = MockClient((req) async {
      path = req.url.path;
      body = req.body;
      return http.Response('{"text":"Narrative here."}', 200);
    });
    final p = PlatformAiProvider(
      token: validToken,
      client: client,
      baseUrl: baseUrl,
    );
    final out = await p.synthesizeConclusion(minimalSynthesisRequest);
    expect(path, endsWith('/ai/synthesize-conclusion'));
    expect(jsonDecode(body!), containsPair('schema_version', 2));
    expect(out.text, 'Narrative here.');
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
      await PlatformAuthStore.instance.debugSetUserToken(staleToken);
      final client = MockClient((req) async => http.Response('{}', 401));
      final p = PlatformAiProvider(
        token: staleToken,
        client: client,
        baseUrl: baseUrl,
      );
      await expectLater(
        p.analyze([const AiCandidate(path: '/a', sizeBytes: 1, isDir: false)]),
        throwsA(predicate((e) => e.toString().contains('session_expired'))),
      );
      expect(await PlatformAuthStore.instance.userToken(), isNull);
    },
  );

  test('401 refreshes session and retries quota once', () async {
    storage['volward_device_uuid'] = 'dev-uuid';
    await PlatformAuthStore.instance.debugSetUserToken(staleToken);

    var quotaCalls = 0;
    final aiClient = MockClient((req) async {
      expect(req.url.path, endsWith('/ai/quota'));
      quotaCalls++;
      if (quotaCalls == 1) {
        expect(req.headers['Authorization'], 'Bearer $staleToken');
        return http.Response('{}', 401);
      }
      expect(req.headers['Authorization'], 'Bearer $validToken');
      return http.Response('{"credits_remaining":5,"credits_total":10}', 200);
    });

    final authClient = MockClient((req) async {
      expect(req.url.path, endsWith('/auth/refresh'));
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
      client: authClient,
      baseUrl: baseUrl,
    );

    final p = PlatformAiProvider(
      token: staleToken,
      client: aiClient,
      baseUrl: baseUrl,
    );

    final quota = await p.queryQuota();
    expect(quota?.creditsRemaining, 5);
    expect(quota?.creditsTotal, 10);
    expect(quotaCalls, 2);
    expect(await PlatformAuthStore.instance.userToken(), validToken);
  });

  test('401 refreshes session and retries analyze once', () async {
    storage['volward_device_uuid'] = 'dev-uuid';
    await PlatformAuthStore.instance.debugSetUserToken(staleToken);

    var analyzeCalls = 0;
    final aiClient = MockClient((req) async {
      expect(req.url.path, endsWith('/ai/analyze'));
      analyzeCalls++;
      if (analyzeCalls == 1) {
        return http.Response('{}', 401);
      }
      return http.Response(
        '{"entries":[{"path":"/a","verdict":"keep","confidence":"high","reason":"x"}],'
        '"credits_used":1,"credits_remaining":9,"model":"deepseek-v4-flash"}',
        200,
      );
    });

    final authClient = MockClient((req) async {
      expect(req.url.path, endsWith('/auth/refresh'));
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
      client: authClient,
      baseUrl: baseUrl,
    );

    final p = PlatformAiProvider(
      token: staleToken,
      client: aiClient,
      baseUrl: baseUrl,
    );

    final out = await p.analyze([
      const AiCandidate(path: '/a', sizeBytes: 1, isDir: false),
    ]);
    expect(out.verdicts.single.verdict, 'keep');
    expect(analyzeCalls, 2);
  });

  test('200 parses entries and credits_used', () async {
    await PlatformAuthStore.instance.debugSetUserToken(validToken);
    final client = MockClient(
      (req) async => http.Response(
        '{"entries":[{"path":"/a","verdict":"keep","confidence":"high","reason":"x"}],'
        '"credits_used":1,"credits_remaining":9,"model":"deepseek-v4-flash"}',
        200,
      ),
    );
    final p = PlatformAiProvider(
      token: validToken,
      client: client,
      baseUrl: baseUrl,
    );
    final out = await p.analyze([
      const AiCandidate(path: '/a', sizeBytes: 1, isDir: false),
    ]);
    expect(out.verdicts.single.verdict, 'keep');
    expect(p.lastCreditsUsed, 1);
    expect(p.lastCreditsRemaining, 9);
  });

  test(
    'request body includes cleanup metadata but omits member_paths',
    () async {
      await PlatformAuthStore.instance.debugSetUserToken(validToken);
      String? body;
      final client = MockClient((req) async {
        body = req.body;
        return http.Response(
          '{"entries":[],"credits_used":1,"credits_remaining":1,"model":"m"}',
          200,
        );
      });
      final p = PlatformAiProvider(
        token: validToken,
        client: client,
        baseUrl: baseUrl,
      );
      await p.analyze([
        const AiCandidate(
          path: '/a',
          sizeBytes: 1,
          isDir: true,
          cleanupSource: 'ai_tool_cache',
          cleanupHint: 'Known AI/editor cache',
          retentionDays: 30,
          memberPaths: ['/a/1', '/a/2'],
        ),
      ]);
      expect(body, isNotNull);
      final decoded = jsonDecode(body!) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List;
      final candidate = candidates.single as Map<String, dynamic>;
      expect(candidate['cleanup_source'], 'ai_tool_cache');
      expect(candidate['cleanup_hint'], 'Known AI/editor cache');
      expect(candidate['retention_days'], 30);
      expect(candidate.containsKey('member_paths'), isFalse);
    },
  );

  test('analyzeTreeNodes sends analysis_kind tree and tree_nodes', () async {
    await PlatformAuthStore.instance.debugSetUserToken(validToken);
    String? body;
    final client = MockClient((req) async {
      body = req.body;
      return http.Response(
        '{"entries":[{"path":"/Cache","verdict":"keep","confidence":"high","reason":"x"}],'
        '"credits_used":1,"credits_remaining":1,"model":"m"}',
        200,
      );
    });
    final p = PlatformAiProvider(
      token: validToken,
      client: client,
      baseUrl: baseUrl,
    );
    await p.analyzeTreeNodes([
      const CoverageTreeNode(
        path: '/Cache',
        sizeBytes: 100,
        fileCount: 3,
        subdirCount: 1,
        role: 'cache',
        markers: ['tmp'],
        topExtensions: [CoverageTreeTopExtension(extension: 'log', count: 2)],
      ),
    ]);
    expect(body, isNotNull);
    final decoded = jsonDecode(body!) as Map<String, dynamic>;
    expect(decoded['analysis_kind'], 'tree');
    expect(decoded.containsKey('candidates'), isFalse);
    final nodes = decoded['tree_nodes'] as List;
    final node = nodes.single as Map<String, dynamic>;
    expect(node['path'], '/Cache');
    expect(node['file_count'], 3);
    expect(node['subdir_count'], 1);
    expect(node['role'], 'cache');
    expect(node['markers'], ['tmp']);
    expect(node['top_extensions'], [
      ['log', 2],
    ]);
  });
}
