import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:volward/ai/ai_contract.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/byok_ai_provider.dart';

class _FakeContract implements AiContract {
  @override
  int batchSize() => 40;

  @override
  String upstreamEndpoint() => 'https://example.test/v1/chat';

  @override
  String buildRequestJson(List<AiCandidate> batch) =>
      '{"model":"deepseek-v4-flash","n":${batch.length}}';

  @override
  List<AiVerdict> parseResponseJson(String body, List<AiCandidate> batch) {
    return batch
        .map(
          (c) => AiVerdict(
            path: c.path,
            verdict: 'keep',
            confidence: 'high',
            reason: 'ok',
          ),
        )
        .toList();
  }
}

void main() {
  test('401 maps to invalid_api_key', () async {
    final client = MockClient((req) async => http.Response('nope', 401));
    final p = ByokAiProvider(
      apiKey: 'sk-x',
      client: client,
      contract: _FakeContract(),
    );
    await expectLater(
      p.analyze([const AiCandidate(path: '/a', sizeBytes: 1, isDir: false)]),
      throwsA(predicate((e) => e.toString().contains('invalid_api_key'))),
    );
  });

  test('200 uses contract parseResponseJson', () async {
    final client = MockClient(
      (req) async => http.Response('{"choices":[]}', 200),
    );
    final p = ByokAiProvider(
      apiKey: 'sk-x',
      client: client,
      contract: _FakeContract(),
    );
    final out = await p.analyze([
      const AiCandidate(path: '/a', sizeBytes: 1, isDir: false),
    ]);
    expect(out.single.verdict, 'keep');
  });

  test('accumulates reported token usage across batches', () async {
    var requestCount = 0;
    final client = MockClient((req) async {
      requestCount++;
      return http.Response(
        '{"choices":[],"usage":{'
        '"prompt_tokens":${requestCount * 10},'
        '"completion_tokens":${requestCount * 2},'
        '"total_tokens":${requestCount * 12}}}',
        200,
      );
    });
    final provider = ByokAiProvider(
      apiKey: 'sk-x',
      client: client,
      contract: _FakeContract(),
    );
    final candidates = List.generate(
      41,
      (index) => AiCandidate(path: '/$index', sizeBytes: 1, isDir: false),
    );

    await provider.analyze(candidates);

    expect(requestCount, 2);
    expect(provider.lastTokenUsage?.promptTokens, 30);
    expect(provider.lastTokenUsage?.completionTokens, 6);
    expect(provider.lastTokenUsage?.totalTokens, 36);
  });

  test('estimates token usage when upstream omits usage', () async {
    final client = MockClient(
      (req) async => http.Response('{"choices":[]}', 200),
    );
    final provider = ByokAiProvider(
      apiKey: 'sk-x',
      client: client,
      contract: _FakeContract(),
    );

    await provider.analyze([
      const AiCandidate(path: '/a', sizeBytes: 1, isDir: false),
    ]);

    expect(provider.lastTokenUsage?.promptTokens, 208);
    expect(provider.lastTokenUsage?.completionTokens, 40);
    expect(provider.lastTokenUsage?.totalTokens, 248);
    expect(provider.hasReliableTokenUsage, isFalse);
  });

  test('marks token usage unreliable when a batch omits usage', () async {
    var requestCount = 0;
    final client = MockClient((req) async {
      requestCount++;
      if (requestCount == 1) {
        return http.Response(
          '{"choices":[],"usage":{'
          '"prompt_tokens":10,'
          '"completion_tokens":2,'
          '"total_tokens":12}}',
          200,
        );
      }
      return http.Response('{"choices":[]}', 200);
    });
    final provider = ByokAiProvider(
      apiKey: 'sk-x',
      client: client,
      contract: _FakeContract(),
    );
    final candidates = List.generate(
      41,
      (index) => AiCandidate(path: '/$index', sizeBytes: 1, isDir: false),
    );

    await provider.analyze(candidates);

    expect(requestCount, 2);
    expect(provider.lastTokenUsage?.promptTokens, 218);
    expect(provider.lastTokenUsage?.completionTokens, 42);
    expect(provider.lastTokenUsage?.totalTokens, 260);
    expect(provider.hasReliableTokenUsage, isFalse);
  });

  test('estimates completed batch usage before a later failure', () async {
    var requestCount = 0;
    final client = MockClient((req) async {
      requestCount++;
      if (requestCount == 1) {
        return http.Response('{"choices":[]}', 200);
      }
      return http.Response('upstream failed', 500);
    });
    final provider = ByokAiProvider(
      apiKey: 'sk-x',
      client: client,
      contract: _FakeContract(),
    );
    final candidates = List.generate(
      41,
      (index) => AiCandidate(path: '/$index', sizeBytes: 1, isDir: false),
    );

    await expectLater(provider.analyze(candidates), throwsException);

    expect(requestCount, 2);
    expect(provider.lastTokenUsage?.promptTokens, 520);
    expect(provider.lastTokenUsage?.completionTokens, 1600);
    expect(provider.lastTokenUsage?.totalTokens, 2120);
    expect(provider.hasReliableTokenUsage, isFalse);
  });

  test('keeps completed batch usage when a later batch fails', () async {
    var requestCount = 0;
    final client = MockClient((req) async {
      requestCount++;
      if (requestCount == 1) {
        return http.Response(
          '{"choices":[],"usage":{'
          '"prompt_tokens":10,'
          '"completion_tokens":2,'
          '"total_tokens":12}}',
          200,
        );
      }
      return http.Response('upstream failed', 500);
    });
    final provider = ByokAiProvider(
      apiKey: 'sk-x',
      client: client,
      contract: _FakeContract(),
    );
    final candidates = List.generate(
      41,
      (index) => AiCandidate(path: '/$index', sizeBytes: 1, isDir: false),
    );

    await expectLater(provider.analyze(candidates), throwsException);

    expect(requestCount, 2);
    expect(provider.lastTokenUsage?.promptTokens, 10);
    expect(provider.lastTokenUsage?.completionTokens, 2);
    expect(provider.lastTokenUsage?.totalTokens, 12);
  });
}
