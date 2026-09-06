import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/cancel_token.dart';
import 'package:volward/ai/coverage_analyze_batch.dart';
import 'package:volward/ai/coverage_models.dart';

class _FakeAiProvider implements AiProvider {
  @override
  Future<AnalyzeResult> analyze(
    List<AiCandidate> candidates, {
    CancelToken? cancelToken,
  }) async {
    return AnalyzeResult(
      verdicts: candidates
          .map(
            (candidate) => AiVerdict(
              path: candidate.path,
              verdict: 'keep',
              confidence: 'high',
              reason: 'test',
            ),
          )
          .toList(),
    );
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

  test('coverageRowsToCandidates forwards cleanup hints', () {
    const rows = [
      CoverageRow(
        rowIndex: 0,
        kind: CoverageRowKind.group,
        path: '/tmp/cache',
        sizeBytes: 10,
        memberCount: 3,
        cleanupSource: 'system_temp',
        cleanupHint: 'temporary location',
        retentionDays: 10,
      ),
    ];
    final candidates = coverageRowsToCandidates(rows);
    expect(candidates.single.cleanupSource, 'system_temp');
    expect(candidates.single.cleanupHint, 'temporary location');
    expect(candidates.single.retentionDays, 10);
  });

  test('coverageVerdictForRow attaches group member count for group rows', () {
    const group = CoverageRow(
      rowIndex: 0,
      kind: CoverageRowKind.group,
      path: '/tmp/cache',
      sizeBytes: 30,
      memberCount: 3,
    );
    final verdict = coverageVerdictForRow(
      group,
      const AiVerdict(
        path: '/tmp/cache',
        verdict: 'keep',
        confidence: 'high',
        reason: 'test',
      ),
    );
    expect(verdict.coverageSource, 'group:/tmp/cache');
    expect(verdict.groupMemberCount, 3);
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
