import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/coverage_ui_helpers.dart';
import 'package:volward/ai/coverage_verdict_store.dart';

void main() {
  test('computeCoverageSourceStats counts file and group sources', () {
    const verdicts = [
      CoverageVerdict(
        path: '/a',
        verdict: 'keep',
        confidence: 'high',
        reason: 'r',
        coverageSource: 'file',
        sizeBytes: 1,
      ),
      CoverageVerdict(
        path: '/b',
        verdict: 'keep',
        confidence: 'high',
        reason: 'r',
        coverageSource: 'group:/b',
        sizeBytes: 2,
      ),
    ];

    final stats = computeCoverageSourceStats(
      verdicts: verdicts,
      preClassifiedCount: 3,
    );

    expect(stats.fileVerdicts, 1);
    expect(stats.groupVerdicts, 1);
    expect(stats.localPreClassified, 3);
  });

  test('unanalyzedCandidateVerdicts skips paths with verdicts', () {
    const candidates = [
      AiCandidate(path: '/a', sizeBytes: 1, isDir: false),
      AiCandidate(path: '/b', sizeBytes: 2, isDir: false),
    ];

    final pending = unanalyzedCandidateVerdicts(
      candidates: candidates,
      verdictPaths: const {'/a'},
      reason: 'waiting',
    );

    expect(pending, hasLength(1));
    expect(pending.single.path, '/b');
    expect(pending.single.verdict, 'unanalyzed');
  });

  test('buildUnanalyzedDisplayVerdicts adds aggregate beyond preview', () {
    final previewCandidates = List.generate(
      3,
      (index) =>
          AiCandidate(path: '/preview/$index', sizeBytes: 1, isDir: false),
    );

    final pending = buildUnanalyzedDisplayVerdicts(
      pendingFileCount: 200,
      previewCandidates: previewCandidates,
      verdictPaths: const {},
      itemReason: 'waiting',
      aggregateSummaryReason: (remaining) =>
          'Plus $remaining more files awaiting analysis',
    );

    expect(previewCandidates, hasLength(3));
    expect(pending, hasLength(4));
    expect(pending.last.verdict, 'unanalyzed');
    expect(pending.last.reason, 'Plus 197 more files awaiting analysis');
    expect(pending.last.path, startsWith('coverage://pending/'));
  });
}
