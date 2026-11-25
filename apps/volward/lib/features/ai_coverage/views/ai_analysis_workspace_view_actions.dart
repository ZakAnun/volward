import 'ai_analysis_workspace_view_state.dart';

/// Typed user intents accepted by the AI workspace views.
abstract interface class AiAnalysisWorkspaceViewActions {
  Future<void> initialize();

  Future<void> retry();

  Future<void> loadPreviousResult();

  Future<void> startAnalysis({required bool fullCoverage});

  Future<void> pauseCoverage();

  Future<void> resumeCoverage();

  Future<void> cancelCoverage();

  Future<void> restartCoverage();

  Future<void> raiseCoverageBudget(int credits);

  Future<void> refreshPrecheck();

  Future<void> loadUnknownCandidateSample();

  Future<void> raiseConfiguredCoverageCap();

  Future<void> openLocalOnlyResults();

  void setResultsQuery(String value);

  void setResultsDirectoryFilter(String? path);

  void setResultFilter(WorkspaceResultFilter filter);

  void setResultSort(WorkspaceResultSort sort);

  void setDirectoryTypeFilter(WorkspaceDirectoryTypeFilter filter);

  void setReviewDecision(String path, WorkspaceReviewDecision decision);

  void toggleSelection(String path);

  void setSelection(String path, bool selected);

  void toggleSafeGroup(List<String> paths, bool selected);

  void toggleGroupExpanded(String path);

  void showMoreItemsInGroup(String groupPath, int total);

  void toggleReviewExpanded(String path);

  void resetResultsFilters();

  void backToConclusions();

  void openOverview();

  void openReviewQueue({String? directoryPath});

  void openDetailList({
    WorkspaceResultFilter? initialFilter,
    String? directoryPath,
  });

  void toggleScopeExpanded();

  void goBack();

  void notifyResultsScrollStart();

  void notifyResultsScrollEnd({double? pixels, double? maxScrollExtent});

  Future<void> generateNarrative();

  Future<void> deleteSelected();

  Future<void> retryFailedDeletes();

  void exitWorkspace();
}
