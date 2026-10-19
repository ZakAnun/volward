/// Results-first AI cleanup overview: mode resolution and display caps.
enum ResultsHubMode { awaitingAnalysis, analyzing, ready }

/// Max items per safe/review preview block on the conclusions overview.
const kAiResultsPreviewItemCap = 6;

/// Max unknown candidate rows shown in the collapsible scope panel.
const kAiResultsScopeUnknownSampleCap = 8;

ResultsHubMode resolveResultsHubMode({
  required bool analyzing,
  required bool hasAnalyzedVerdicts,
  required bool coverageRunning,
}) {
  if (analyzing || coverageRunning) return ResultsHubMode.analyzing;
  if (hasAnalyzedVerdicts) return ResultsHubMode.ready;
  return ResultsHubMode.awaitingAnalysis;
}
