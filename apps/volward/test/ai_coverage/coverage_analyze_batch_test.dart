import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/cancel_token.dart';
import 'package:volward/ai/coverage_analyze_batch.dart';
import 'package:volward/ai/coverage_models.dart';

class _FakeProvider implements AiProvider {
  _FakeProvider({required this.verdicts, this.credits = 1});

  final List<AiVerdict> verdicts;
  final int credits;

  @override
  Future<AnalyzeResult> analyze(
    List<AiCandidate> candidates, {
    CancelToken? cancelToken,
  }) async {
    return AnalyzeResult(verdicts: verdicts, credits: credits);
  }

  @override
  Future<AiQuotaInfo?> queryQuota() async => null;
}

void main() {
  test('missing API verdict degrades to review_needed per row', () async {
    final batch = createCoverageAnalyzeBatch(
      provider: _FakeProvider(
        verdicts: const [
          AiVerdict(
            path: '/a',
            verdict: 'keep',
            confidence: 'high',
            reason: 'ok',
          ),
        ],
      ),
    );
    final rows = [
      const CoverageRow(
        rowIndex: 0,
        kind: CoverageRowKind.file,
        path: '/a',
        sizeBytes: 1,
      ),
      const CoverageRow(
        rowIndex: 1,
        kind: CoverageRowKind.file,
        path: '/b',
        sizeBytes: 1,
      ),
    ];
    final outcome = await batch(rows);
    expect(outcome.verdicts, hasLength(2));
    expect(outcome.verdicts[0].verdict, 'keep');
    expect(outcome.verdicts[0].coverageSource, 'file');
    expect(outcome.verdicts[1].verdict, 'review_needed');
    expect(outcome.verdicts[1].confidence, 'low');
    expect(outcome.verdicts[1].coverageSource, kIncompleteCoverageSource);
    expect(outcome.verdicts[1].reason, kIncompleteVerdictReason);
  });

  test('complete API verdicts keep normal coverage source', () async {
    final batch = createCoverageAnalyzeBatch(
      provider: _FakeProvider(
        verdicts: const [
          AiVerdict(
            path: '/a',
            verdict: 'keep',
            confidence: 'high',
            reason: 'ok',
          ),
        ],
      ),
    );
    final rows = [
      const CoverageRow(
        rowIndex: 0,
        kind: CoverageRowKind.file,
        path: '/a',
        sizeBytes: 1,
      ),
    ];
    final outcome = await batch(rows);
    expect(outcome.verdicts.single.coverageSource, 'file');
  });

  test('empty API verdict list throws for non-empty batch', () async {
    final batch = createCoverageAnalyzeBatch(
      provider: _FakeProvider(verdicts: const []),
    );
    final rows = [
      const CoverageRow(
        rowIndex: 0,
        kind: CoverageRowKind.file,
        path: '/a',
        sizeBytes: 1,
      ),
    ];
    expect(batch(rows), throwsA(isA<CoverageAnalyzeException>()));
  });
}
