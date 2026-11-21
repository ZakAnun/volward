import '../../../ai/coverage_job_state.dart';
import '../../../ai/coverage_verdict_store.dart';
import '../../../widgets/ai_results_hub.dart';
import '../models/ai_analysis_workspace_display_state.dart';

/// Context-free snapshot consumed by the pure coverage-flow decision helpers.
///
/// The page controller builds one of these before asking for a decision, then
/// applies the returned plan to its own UI state. This keeps the timing and
/// presentation rules out of the page controller while preserving its single
/// writer role for phase and result state.
final class AiCoverageFlowContext {
  const AiCoverageFlowContext({
    required this.phase,
    required this.analyzing,
    required this.useFullCoverage,
    required this.uiPrefersAnalyzingPhase,
    required this.userEngagedFullRun,
    required this.verdictsNotEmpty,
    required this.resultsHubMode,
    required this.deferJobUiForScroll,
    required this.pauseInFlight,
    required this.jobState,
    required this.pendingJobState,
  });

  final AiWorkspaceDisplayState phase;
  final bool analyzing;
  final bool useFullCoverage;
  final bool uiPrefersAnalyzingPhase;
  final bool userEngagedFullRun;
  final bool verdictsNotEmpty;
  final ResultsHubMode resultsHubMode;
  final bool deferJobUiForScroll;
  final bool pauseInFlight;
  final CoverageJobState? jobState;
  final CoverageJobState? pendingJobState;
}

bool aiCoverageIsLightweightAnalyzing(AiCoverageFlowContext context) {
  if (!context.useFullCoverage || !context.uiPrefersAnalyzingPhase) {
    return false;
  }
  if (context.phase != AiWorkspaceDisplayState.analyzing) return false;
  final job = context.jobState;
  return context.analyzing || job?.status == CoverageJobStatus.running;
}

List<CoverageVerdict> aiCoverageJobBannerVerdictRows(
  AiCoverageFlowContext context,
  List<CoverageVerdict> verdictRows,
) {
  if (aiCoverageIsLightweightAnalyzing(context)) return const [];
  return verdictRows;
}

int aiCoverageJobCoalesceDelayMs(AiCoverageFlowContext context) {
  final pending = context.pendingJobState;
  if (pending != null &&
      (pending.status == CoverageJobStatus.paused ||
          pending.status == CoverageJobStatus.completed ||
          pending.status == CoverageJobStatus.cancelled)) {
    return 0;
  }
  if (aiCoverageIsLightweightAnalyzing(context)) return 1000;
  if (context.phase == AiWorkspaceDisplayState.analyzing &&
      context.uiPrefersAnalyzingPhase &&
      pending?.status == CoverageJobStatus.running) {
    return 1000;
  }
  return 150;
}

bool aiCoverageFreezeActivityMotion(
  CoverageJobState? job, {
  required bool pauseInFlight,
}) {
  if (pauseInFlight) return true;
  return job != null && job.status == CoverageJobStatus.paused;
}

bool aiCoverageShouldShowResultsLocalPreviewHint(
  AiCoverageFlowContext context,
) {
  if (!context.useFullCoverage) return false;
  final job = context.jobState;
  if (job == null) return true;
  if (job.status == CoverageJobStatus.paused) return true;
  return job.analyzedFiles == 0 && job.status == CoverageJobStatus.running;
}

bool aiCoverageShouldDeferJobUiDuringScroll(AiCoverageFlowContext context) {
  if (context.phase == AiWorkspaceDisplayState.results ||
      context.phase == AiWorkspaceDisplayState.deleting) {
    final status = context.jobState?.status ?? context.pendingJobState?.status;
    if (status == CoverageJobStatus.paused ||
        status == CoverageJobStatus.completed ||
        status == CoverageJobStatus.cancelled) {
      return false;
    }
  }
  return context.phase == AiWorkspaceDisplayState.analyzing ||
      aiCoverageIsLightweightAnalyzing(context);
}

bool aiCoverageJobStateIsTerminal(CoverageJobState state) {
  return state.status == CoverageJobStatus.paused ||
      state.status == CoverageJobStatus.completed ||
      state.status == CoverageJobStatus.cancelled;
}

/// Merges appended verdict rows into the currently visible rows by path,
/// preserving the latest row for any duplicate path. Small result sets are
/// sorted by path; heavy result sets keep their stable merged order so the
/// caller can apply the existing heavy-layout path without another sort.
List<CoverageVerdict> aiCoverageMergeVerdictRows(
  Iterable<CoverageVerdict> current,
  Iterable<CoverageVerdict> appended, {
  required int heavyThreshold,
}) {
  final byPath = {for (final row in current) row.path: row};
  for (final row in appended) {
    byPath[row.path] = row;
  }
  final merged = byPath.values.toList();
  if (merged.length < heavyThreshold) {
    merged.sort((a, b) => a.path.compareTo(b.path));
  }
  return merged;
}
