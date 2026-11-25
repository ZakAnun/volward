import '../views/ai_analysis_workspace_view_actions.dart';
import '../views/ai_analysis_workspace_view_state.dart';

/// Public surface the adapter needs from the page controller. Keeping this
/// interface here lets the adapter live outside the large page file.
abstract interface class AiAnalysisWorkspaceActionsTarget {
  Future<void> initializeWorkspace();
  Future<void> retryWorkspace();
  Future<void> loadPreviousResultWorkspace();
  Future<void> startAnalysisWorkspace({required bool fullCoverage});
  Future<void> pauseCoverageWorkspace();
  Future<void> resumeCoverageWorkspace();
  Future<void> cancelCoverageWorkspace();
  Future<void> restartCoverageWorkspace();
  Future<void> raiseCoverageBudgetWorkspace(int credits);
  Future<void> refreshPrecheckWorkspace();
  Future<void> loadUnknownCandidateSampleWorkspace();
  Future<void> raiseConfiguredCoverageCapWorkspace();
  Future<void> openLocalOnlyResultsWorkspace();
  void setResultsQueryWorkspace(String value);
  void setResultsDirectoryFilterWorkspace(String? path);
  void setResultFilterWorkspace(WorkspaceResultFilter filter);
  void setResultSortWorkspace(WorkspaceResultSort sort);
  void setDirectoryTypeFilterWorkspace(WorkspaceDirectoryTypeFilter filter);
  void setReviewDecisionWorkspace(
    String path,
    WorkspaceReviewDecision decision,
  );
  void toggleSelectionWorkspace(String path);
  void setSelectionWorkspace(String path, bool selected);
  void toggleSafeGroupWorkspace(List<String> paths, bool selected);
  void toggleGroupExpandedWorkspace(String path);
  void showMoreItemsInGroupWorkspace(String groupPath, int total);
  void toggleReviewExpandedWorkspace(String path);
  void resetResultsFiltersWorkspace();
  void backToConclusionsWorkspace();
  void openOverviewWorkspace();
  void openReviewQueueWorkspace({String? directoryPath});
  void openDetailListWorkspace({
    WorkspaceResultFilter? initialFilter,
    String? directoryPath,
  });
  void toggleScopeExpandedWorkspace();
  void goBackWorkspace();
  void notifyResultsScrollStartWorkspace();
  void notifyResultsScrollEndWorkspace({
    double? pixels,
    double? maxScrollExtent,
  });
  Future<void> generateNarrativeWorkspace();
  Future<void> deleteSelectedWorkspace();
  Future<void> retryFailedDeletesWorkspace();
  void exitWorkspace();
}

/// Adapter from the immutable typed actions to the page controller.
final class AiAnalysisWorkspaceViewActionsAdapter
    implements AiAnalysisWorkspaceViewActions {
  AiAnalysisWorkspaceViewActionsAdapter(this._controller);

  final AiAnalysisWorkspaceActionsTarget _controller;

  @override
  Future<void> initialize() => _controller.initializeWorkspace();

  @override
  Future<void> retry() => _controller.retryWorkspace();

  @override
  Future<void> loadPreviousResult() =>
      _controller.loadPreviousResultWorkspace();

  @override
  Future<void> startAnalysis({required bool fullCoverage}) =>
      _controller.startAnalysisWorkspace(fullCoverage: fullCoverage);

  @override
  Future<void> pauseCoverage() => _controller.pauseCoverageWorkspace();

  @override
  Future<void> resumeCoverage() => _controller.resumeCoverageWorkspace();

  @override
  Future<void> cancelCoverage() => _controller.cancelCoverageWorkspace();

  @override
  Future<void> restartCoverage() => _controller.restartCoverageWorkspace();

  @override
  Future<void> raiseCoverageBudget(int credits) =>
      _controller.raiseCoverageBudgetWorkspace(credits);

  @override
  Future<void> refreshPrecheck() => _controller.refreshPrecheckWorkspace();

  @override
  Future<void> loadUnknownCandidateSample() =>
      _controller.loadUnknownCandidateSampleWorkspace();

  @override
  Future<void> raiseConfiguredCoverageCap() =>
      _controller.raiseConfiguredCoverageCapWorkspace();

  @override
  Future<void> openLocalOnlyResults() =>
      _controller.openLocalOnlyResultsWorkspace();

  @override
  void setResultsQuery(String value) =>
      _controller.setResultsQueryWorkspace(value);

  @override
  void setResultsDirectoryFilter(String? path) =>
      _controller.setResultsDirectoryFilterWorkspace(path);

  @override
  void setResultFilter(WorkspaceResultFilter filter) =>
      _controller.setResultFilterWorkspace(filter);

  @override
  void setResultSort(WorkspaceResultSort sort) =>
      _controller.setResultSortWorkspace(sort);

  @override
  void setDirectoryTypeFilter(WorkspaceDirectoryTypeFilter filter) =>
      _controller.setDirectoryTypeFilterWorkspace(filter);

  @override
  void setReviewDecision(String path, WorkspaceReviewDecision decision) =>
      _controller.setReviewDecisionWorkspace(path, decision);

  @override
  void toggleSelection(String path) =>
      _controller.toggleSelectionWorkspace(path);

  @override
  void setSelection(String path, bool selected) =>
      _controller.setSelectionWorkspace(path, selected);

  @override
  void toggleSafeGroup(List<String> paths, bool selected) =>
      _controller.toggleSafeGroupWorkspace(paths, selected);

  @override
  void toggleGroupExpanded(String path) =>
      _controller.toggleGroupExpandedWorkspace(path);

  @override
  void showMoreItemsInGroup(String groupPath, int total) =>
      _controller.showMoreItemsInGroupWorkspace(groupPath, total);

  @override
  void toggleReviewExpanded(String path) =>
      _controller.toggleReviewExpandedWorkspace(path);

  @override
  void resetResultsFilters() => _controller.resetResultsFiltersWorkspace();

  @override
  void backToConclusions() => _controller.backToConclusionsWorkspace();

  @override
  void openOverview() => _controller.openOverviewWorkspace();

  @override
  void openReviewQueue({String? directoryPath}) =>
      _controller.openReviewQueueWorkspace(directoryPath: directoryPath);

  @override
  void openDetailList({
    WorkspaceResultFilter? initialFilter,
    String? directoryPath,
  }) => _controller.openDetailListWorkspace(
    initialFilter: initialFilter,
    directoryPath: directoryPath,
  );

  @override
  void toggleScopeExpanded() => _controller.toggleScopeExpandedWorkspace();

  @override
  void goBack() => _controller.goBackWorkspace();

  @override
  void notifyResultsScrollStart() =>
      _controller.notifyResultsScrollStartWorkspace();

  @override
  void notifyResultsScrollEnd({double? pixels, double? maxScrollExtent}) =>
      _controller.notifyResultsScrollEndWorkspace(
        pixels: pixels,
        maxScrollExtent: maxScrollExtent,
      );

  @override
  Future<void> generateNarrative() => _controller.generateNarrativeWorkspace();

  @override
  Future<void> deleteSelected() => _controller.deleteSelectedWorkspace();

  @override
  Future<void> retryFailedDeletes() =>
      _controller.retryFailedDeletesWorkspace();

  @override
  void exitWorkspace() => _controller.exitWorkspace();
}
