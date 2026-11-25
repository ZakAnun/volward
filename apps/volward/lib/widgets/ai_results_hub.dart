import '../ai/coverage_ui_helpers.dart';

/// Results-first AI cleanup overview: mode resolution and display caps.
enum ResultsHubMode { awaitingAnalysis, analyzing, partial, ready }

/// Max items per safe/review preview block on the conclusions overview.
const kAiResultsPreviewItemCap = 6;

/// Max unknown candidate rows shown in the collapsible scope panel.
const kAiResultsScopeUnknownSampleCap = 8;

ResultsHubMode resolveResultsHubMode({
  required bool analyzing,
  required bool hasAnalyzedVerdicts,
  required bool coverageRunning,
  CoverageCompletionPhase? coverageCompletion,
}) {
  if (analyzing ||
      coverageRunning ||
      coverageCompletion == CoverageCompletionPhase.running) {
    return ResultsHubMode.analyzing;
  }
  if (coverageCompletion == CoverageCompletionPhase.partial) {
    return ResultsHubMode.partial;
  }
  if (hasAnalyzedVerdicts) return ResultsHubMode.ready;
  return ResultsHubMode.awaitingAnalysis;
}
