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
      p.analyze([
        const AiCandidate(path: '/a', sizeBytes: 1, isDir: false),
      ]),
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
}
