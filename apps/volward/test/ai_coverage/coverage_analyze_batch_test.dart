import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/coverage_analyze_batch.dart';
import 'package:volward/ai/coverage_models.dart';

class _FakeAiProvider implements AiProvider {
  @override
  Future<List<AiVerdict>> analyze(List<AiCandidate> candidates) async {
    return candidates
        .map(
          (candidate) => AiVerdict(
            path: candidate.path,
            verdict: 'keep',
            confidence: 'high',
            reason: 'test',
          ),
        )
        .toList();
  }

  @override
  Future<AiQuotaInfo?> queryQuota() async => null;
}

void main() {
  test('coverageRowsToCandidates maps group rows as directories', () {
    const rows = [
      CoverageRow(
        rowIndex: 0,
        kind: CoverageRowKind.group,
        path: '/tmp/cache',
        sizeBytes: 10,
        memberCount: 3,
      ),
      CoverageRow(
        rowIndex: 1,
        kind: CoverageRowKind.file,
        path: '/a',
        sizeBytes: 1,
      ),
    ];
    final candidates = coverageRowsToCandidates(rows);
    expect(candidates.first.isDir, isTrue);
    expect(candidates.first.childCount, 3);
    expect(candidates.last.isDir, isFalse);
  });

  test('createCoverageAnalyzeBatch maps provider verdicts', () async {
    const rows = [
      CoverageRow(
        rowIndex: 0,
        kind: CoverageRowKind.file,
        path: '/a',
        sizeBytes: 1,
      ),
    ];
    final analyzeBatch = createCoverageAnalyzeBatch(
      provider: _FakeAiProvider(),
    );
    final outcome = await analyzeBatch(rows);
    expect(outcome.verdicts.single.path, '/a');
    expect(outcome.verdicts.single.coverageSource, 'file');
    expect(outcome.verdicts.single.verdict, 'keep');
  });
}
