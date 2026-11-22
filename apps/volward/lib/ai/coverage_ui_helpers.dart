import 'ai_provider.dart';
import 'coverage_job_state.dart';
import 'coverage_models.dart';
import 'coverage_verdict_store.dart';

/// The lifecycle of provider-backed classification for one scan snapshot.
enum ClassificationAiPhase {
  notStarted,
  running,
  completed,
  paused,
  failed,
  notRequired,
}

/// Snapshot-wide classification counts, kept independent from paged verdict UI.
///
/// [bootstrapLocalCount] belongs to candidate construction, while
/// [localRuleCount] belongs to the full-coverage local-rule backfill. They are
/// intentionally not added together because the two pipelines can overlap.
class ClassificationProvenanceSummary {
  const ClassificationProvenanceSummary({
    required this.bootstrapLocalCount,
    required this.localRuleCount,
    required this.aiResolvedCount,
    required this.aiPlannedCount,
    required this.phase,
    this.localPlannedCount,
    this.localPhaseComplete = false,
  });

  final int bootstrapLocalCount;
  final int localRuleCount;
  final int aiResolvedCount;
  final int? aiPlannedCount;
  final ClassificationAiPhase phase;
  final int? localPlannedCount;
  final bool localPhaseComplete;
}

/// UI-ready AI progress facts derived from persisted classification counters.
/// A null [progressFraction] means the plan cannot provide a trustworthy
/// denominator and callers must not render percentage progress.
class ClassificationProgressPresentation {
  const ClassificationProgressPresentation({
    required this.provenance,
    required this.progressFraction,
  });

  final ClassificationProvenanceSummary provenance;
  final double? progressFraction;

  bool get showsAiProgress => progressFraction != null;

  int? get progressPercent =>
      progressFraction == null ? null : (progressFraction! * 100).round();
}

ClassificationProgressPresentation buildClassificationProgressPresentation(
  ClassificationProvenanceSummary provenance,
) {
  final planned = provenance.aiPlannedCount;
  final canShowProgress =
      planned != null &&
      planned > 0 &&
      (provenance.phase == ClassificationAiPhase.running ||
          provenance.phase == ClassificationAiPhase.completed);
  return ClassificationProgressPresentation(
    provenance: provenance,
    progressFraction: canShowProgress
        ? (provenance.aiResolvedCount / planned).clamp(0, 1).toDouble()
        : null,
  );
}

/// Builds source and lifecycle context without relying on a paged verdict list.
ClassificationProvenanceSummary buildClassificationProvenanceSummary({
  required CoverageJobState? job,
  required CoveragePlanSummary? plan,
  required int bootstrapPreclassifiedCount,
  required bool hasProvider,
  required bool isLocalOnlyPlan,
}) {
  final plannedAiFiles = _plannedAiFiles(plan);
  return ClassificationProvenanceSummary(
    bootstrapLocalCount: bootstrapPreclassifiedCount,
    localRuleCount: job?.localRuleFiles ?? 0,
    aiResolvedCount: job?.aiResolvedFiles ?? 0,
    aiPlannedCount: plannedAiFiles,
    phase: _classificationAiPhase(
      job: job,
      hasProvider: hasProvider,
      isLocalOnlyPlan: isLocalOnlyPlan,
    ),
    localPlannedCount: _plannedLocalFiles(plan),
    localPhaseComplete: job?.localPhaseComplete ?? false,
  );
}

int? _plannedLocalFiles(CoveragePlanSummary? plan) {
  if (plan == null || plan.planVersion < 3) return null;
  final safe = plan.localSafeFiles;
  final keep = plan.localKeepFiles;
  if (safe == null && keep == null) return null;
  return (safe ?? 0) + (keep ?? 0);
}

int? _plannedAiFiles(CoveragePlanSummary? plan) {
  if (plan == null || plan.planVersion < 3) return null;
  final treePendingFiles = plan.treePendingFiles;
  final tailFiles = plan.tailFiles ?? plan.tailFileCount;
  if (treePendingFiles == null && tailFiles == null) return null;
  return (treePendingFiles ?? 0) + (tailFiles ?? 0);
}

ClassificationAiPhase _classificationAiPhase({
  required CoverageJobState? job,
  required bool hasProvider,
  required bool isLocalOnlyPlan,
}) {
  if (isLocalOnlyPlan) return ClassificationAiPhase.notRequired;
  if (job == null) return ClassificationAiPhase.notStarted;
  return switch (job.status) {
    CoverageJobStatus.running => ClassificationAiPhase.running,
    CoverageJobStatus.completed => ClassificationAiPhase.completed,
    CoverageJobStatus.paused
        when job.pauseReason == CoveragePauseReason.failed =>
      ClassificationAiPhase.failed,
    CoverageJobStatus.paused ||
    CoverageJobStatus.cancelled => ClassificationAiPhase.paused,
    CoverageJobStatus.idle when hasProvider => ClassificationAiPhase.notStarted,
    CoverageJobStatus.idle => ClassificationAiPhase.notStarted,
  };
}

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
