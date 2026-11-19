import 'package:flutter/widgets.dart';

abstract final class AiAnalysisWorkspaceKeys {
  static const workspace = Key('ai-analysis-workspace');
  static const back = Key('ai-analysis-back');
  static const loadPrevious = Key('ai-analysis-load-previous');
  static const analyzeAgain = Key('ai-analysis-analyze-again');
  static const startAnalysis = Key('ai-analysis-start-analysis');
  static const settings = Key('ai-analysis-open-settings');
  static const resultsList = Key('ai-analysis-results-list');
  static const summary = Key('ai-analysis-summary');
  static const decisionSummary = Key('ai-analysis-decision-summary');
  static const searchToggle = Key('ai-analysis-search-toggle');
  static const searchSortSheet = Key('ai-analysis-search-sort-sheet');
  static const resultsFilter = Key('ai-analysis-results-filter');
  static const resultsKeepExpandHint = Key('ai-analysis-keep-expand-hint');
  static const delete = Key('ai-analysis-delete');
  static const precheckDelete = Key('ai-analysis-precheck-delete');
  static const header = Key('ai-analysis-header');
  static const hubStatusChip = Key('ai-results-hub-status-chip');
  static const selectedSummary = Key('ai-analysis-selected-summary');
  static const pendingReview = Key('ai-analysis-pending-review');
  static const conclusionsOverview = Key('ai-analysis-conclusions-overview');
  static const resultsScopePanel = Key('ai-results-scope-panel');
  static const showAllResults = Key('ai-analysis-show-all-results');
  static const detailListSecondary = Key('ai-analysis-detail-list-secondary');
  static const reviewQueuePrimary = Key('ai-analysis-review-queue-primary');
  static const reviewQueue = Key('ai-analysis-review-queue');
  static const detailList = Key('ai-analysis-detail-list');
  static const resultsHero = Key('ai-analysis-results-hero');
  static const resultsMetricSafe = Key('ai-analysis-results-metric-safe');
  static const resultsMetricReview = Key('ai-analysis-results-metric-review');
  static const resultsMetricKeep = Key('ai-analysis-results-metric-keep');
  static const pendingPreview = Key('ai-analysis-pending-preview');
  static const resultsPreviewSafe = Key('ai-results-preview-safe');
  static const resultsPreviewReview = Key('ai-results-preview-review');
  static const backToConclusions = Key('ai-analysis-back-to-conclusions');
  static const conclusionNarrative = Key('ai-analysis-conclusion-narrative');
  static const conclusionNarrativeLoading = Key(
    'ai-analysis-conclusion-narrative-loading',
  );
  static const conclusionNarrativeGenerate = Key(
    'ai-analysis-conclusion-narrative-generate',
  );
  static const directoryGrid = Key('ai-analysis-directory-grid');
  static const directoryTypeFilter = Key('ai-analysis-directory-type-filter');

  static Key directoryCard(String path) =>
      Key('ai-analysis-directory-card:$path');

  static Key directoryTypeChip(String type) =>
      Key('ai-analysis-dir-type:$type');

  // Source-compatible aliases used by the extracted workspace implementation.
  static const workspaceKey = workspace;
  static const backKey = back;
  static const loadPreviousKey = loadPrevious;
  static const analyzeAgainKey = analyzeAgain;
  static const startAnalysisKey = startAnalysis;
  static const settingsKey = settings;
  static const resultsListKey = resultsList;
  static const summaryKey = summary;
  static const decisionSummaryKey = decisionSummary;
  static const searchToggleKey = searchToggle;
  static const searchSortSheetKey = searchSortSheet;
  static const resultsFilterKey = resultsFilter;
  static const resultsKeepExpandHintKey = resultsKeepExpandHint;
  static const deleteKey = delete;
  static const precheckDeleteKey = precheckDelete;
  static const headerKey = header;
  static const hubStatusChipKey = hubStatusChip;
  static const selectedSummaryKey = selectedSummary;
  static const pendingReviewKey = pendingReview;
  static const conclusionsOverviewKey = conclusionsOverview;
  static const resultsScopePanelKey = resultsScopePanel;
  static const showAllResultsKey = showAllResults;
  static const detailListSecondaryKey = detailListSecondary;
  static const reviewQueuePrimaryKey = reviewQueuePrimary;
  static const reviewQueueKey = reviewQueue;
  static const detailListKey = detailList;
  static const resultsHeroKey = resultsHero;
  static const resultsMetricSafeKey = resultsMetricSafe;
  static const resultsMetricReviewKey = resultsMetricReview;
  static const resultsMetricKeepKey = resultsMetricKeep;
  static const pendingPreviewKey = pendingPreview;
  static const resultsPreviewSafeKey = resultsPreviewSafe;
  static const resultsPreviewReviewKey = resultsPreviewReview;
  static const backToConclusionsKey = backToConclusions;
  static const conclusionNarrativeKey = conclusionNarrative;
  static const conclusionNarrativeLoadingKey = conclusionNarrativeLoading;
  static const conclusionNarrativeGenerateKey = conclusionNarrativeGenerate;
  static const directoryGridKey = directoryGrid;
  static const directoryTypeFilterKey = directoryTypeFilter;

  static Key directoryCardKey(String path) => directoryCard(path);
  static Key directoryTypeChipKey(String type) => directoryTypeChip(type);
}
