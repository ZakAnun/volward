import 'ai_provider.dart';
import 'coverage_verdict_store.dart';

/// Source breakdown for the coverage banner (Design §9).
class CoverageSourceStats {
  const CoverageSourceStats({
    required this.fileVerdicts,
    required this.groupVerdicts,
    required this.localPreClassified,
  });

  final int fileVerdicts;
  final int groupVerdicts;
  final int localPreClassified;

  bool get isEmpty =>
      fileVerdicts == 0 && groupVerdicts == 0 && localPreClassified == 0;
}

CoverageSourceStats computeCoverageSourceStats({
  required Iterable<CoverageVerdict> verdicts,
  required int preClassifiedCount,
}) {
  var fileVerdicts = 0;
  var groupVerdicts = 0;
  for (final verdict in verdicts) {
    if (verdict.coverageSource == 'file') {
      fileVerdicts++;
    } else if (verdict.coverageSource.startsWith('group:')) {
      groupVerdicts++;
    }
  }
  return CoverageSourceStats(
    fileVerdicts: fileVerdicts,
    groupVerdicts: groupVerdicts,
    localPreClassified: preClassifiedCount,
  );
}

/// Paths from visible candidates that still lack a coverage verdict.
List<AiVerdict> unanalyzedCandidateVerdicts({
  required Iterable<AiCandidate> candidates,
  required Set<String> verdictPaths,
  required String reason,
}) {
  final items = <AiVerdict>[];
  for (final candidate in candidates) {
    if (verdictPaths.contains(candidate.path)) continue;
    items.add(
      AiVerdict(
        path: candidate.path,
        verdict: 'unanalyzed',
        confidence: '',
        reason: reason,
      ),
    );
  }
  return items;
}

const coveragePendingAggregatePrefix = 'coverage://pending/';

/// Builds preview rows plus an aggregate row when [pendingFileCount] exceeds
/// the preview list (Design §9 — not limited to legacy Top-150 candidates).
List<AiVerdict> buildUnanalyzedDisplayVerdicts({
  required int pendingFileCount,
  required Iterable<AiCandidate> previewCandidates,
  required Set<String> verdictPaths,
  required String itemReason,
  required String Function(int remainingCount) aggregateSummaryReason,
}) {
  if (pendingFileCount <= 0) return const [];
  final preview = unanalyzedCandidateVerdicts(
    candidates: previewCandidates,
    verdictPaths: verdictPaths,
    reason: itemReason,
  );
  final remaining = pendingFileCount - preview.length;
  if (remaining <= 0) return preview;
  return [
    ...preview,
    AiVerdict(
      path: '$coveragePendingAggregatePrefix$remaining',
      verdict: 'unanalyzed',
      confidence: '',
      reason: aggregateSummaryReason(remaining),
    ),
  ];
}
