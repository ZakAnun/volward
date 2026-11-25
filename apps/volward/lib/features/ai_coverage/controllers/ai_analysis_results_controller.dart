import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../ai/ai_provider.dart';
import '../../../ai/ai_result_groups.dart';
import '../../../ai/ai_result_overview.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../scan_tree.dart';
import '../ports/workspace_ports.dart';
import '../views/ai_analysis_workspace_view_state.dart';
import 'ai_analysis_workspace_controller.dart';

/// Owns normalized results state, selection, review decisions, filters, sort,
/// detail/review navigation context and conclusion-narrative state.
class AiAnalysisResultsController extends ChangeNotifier {
  AiAnalysisResultsController({
    required AiAnalysisWorkspaceController owner,
    required WorkspaceSettingsPort settings,
    String? ownerId,
  }) : _owner = owner,
       // ignore: prefer_initializing_formals
       _settings = settings,
       _ownerId = ownerId ?? owner.activeOwnerId;

  @visibleForTesting
  factory AiAnalysisResultsController.forTest({bool delayedNarrative = false}) {
    final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
    final controller = AiAnalysisResultsController(
      owner: owner,
      settings: const _NoopResultsSettingsPort(),
      ownerId: 'owner-a',
    );
    if (delayedNarrative) {
      controller._narrativeSynthesizer = () {
        final completer = Completer<String?>();
        controller._pendingNarrative = completer;
        return completer.future;
      };
    }
    return controller;
  }

  final AiAnalysisWorkspaceController _owner;
  WorkspaceSettingsPort _settings;
  String? _ownerId;

  List<AiVerdict> _verdicts = const [];
  Set<String> _verdictPaths = const {};
  Set<String> get verdictPaths => _verdictPaths;
  List<AiVerdict>? _pendingRows;
  List<AiResultGroup>? _combinedGroups;

  List<AiResultGroup>? _normalizedGroupsCache;
  bool _normalizedGroupsCacheIncludesPreclassified = false;
  _NormalizedGroupsCacheKey? _normalizedGroupsCacheKey;
  final Set<String> _selected = {};
  final Map<String, WorkspaceReviewDecision> _reviewDecisions = {};
  final Set<String> _expandedGroupPaths = {};
  final Map<String, int> _expandedGroupItemLimits = {};
  final Set<String> _expandedReviewPaths = {};

  String _query = '';
  WorkspaceResultFilter _filter = WorkspaceResultFilter.all;
  String? _directoryFilter;
  String? _reviewQueueDirectoryFilter;
  int? _reviewQueueSessionInitialPending;
  WorkspaceResultSort _sort = WorkspaceResultSort.priority;

  bool _narrativeEnabled = false;
  bool _narrativeAuto = true;
  bool _narrativeLoading = false;
  bool _narrativeSynthesisInFlight = false;
  String? _narrativeText;
  String? _narrativeSignature;
  int _narrativeGeneration = 0;

  List<AiVerdict> get verdicts => _verdicts;
  List<AiResultGroup>? get normalizedGroupsCache => _normalizedGroupsCache;
  Set<String> get selected => Set.unmodifiable(_selected);
  Map<String, WorkspaceReviewDecision> get reviewDecisions =>
      Map.unmodifiable(_reviewDecisions);
  Set<String> get expandedGroupPaths => Set.unmodifiable(_expandedGroupPaths);
  Map<String, int> get expandedGroupItemLimits =>
      Map.unmodifiable(_expandedGroupItemLimits);
  Set<String> get expandedReviewPaths => Set.unmodifiable(_expandedReviewPaths);
  String get query => _query;
  WorkspaceResultFilter get filter => _filter;
  String? get directoryFilter => _directoryFilter;
  String? get reviewQueueDirectoryFilter => _reviewQueueDirectoryFilter;
  int? get reviewQueueSessionInitialPending =>
      _reviewQueueSessionInitialPending;
  WorkspaceResultSort get sort => _sort;
  bool get narrativeEnabled => _narrativeEnabled;
  bool get narrativeAuto => _narrativeAuto;
  bool get narrativeLoading => _narrativeLoading;
  bool get narrativeSynthesisInFlight => _narrativeSynthesisInFlight;
  String? get narrativeText => _narrativeText;
  String? get narrativeSignature => _narrativeSignature;
  int get narrativeGeneration => _narrativeGeneration;

  Future<String?> Function()? _narrativeSynthesizer;
  Completer<String?>? _pendingNarrative;

  AiWorkspaceResultsState get resultsState => AiWorkspaceResultsState(
    verdicts: _verdicts,
    selectedPaths: _selected,
    reviewDecisions: _reviewDecisions,
    expandedGroupPaths: _expandedGroupPaths,
    query: _query,
    directoryFilter: _directoryFilter,
    filter: _filter,
    sort: _sort,
  );

  AiWorkspaceNarrativeState get narrativeState => AiWorkspaceNarrativeState(
    enabled: _narrativeEnabled,
    auto: _narrativeAuto,
    loading: _narrativeLoading,
    text: _narrativeText,
    signature: _narrativeSignature,
    generation: _narrativeGeneration,
  );

  /// Completes the delayed narrative in the [forTest] delayed-narrative seam.
  @visibleForTesting
  void completeDelayedNarrative([String? text = 'narrative']) {
    _pendingNarrative?.complete(text);
  }

  void configure({required WorkspaceSettingsPort settings, String? ownerId}) {
    _settings = settings;
    final nextOwnerId = ownerId ?? _owner.activeOwnerId;
    if (nextOwnerId != _ownerId) {
      rebindOwner(nextOwnerId);
    }
  }

  void rebindOwner(String? ownerId) {
    _ownerId = ownerId;
    _owner.rebindOwner(ownerId);
    invalidateNarrative();
  }

  void reset() {
    setNormalizedGroupsCache(null);
    _verdicts = const [];
    _verdictPaths = const {};
    _selected.clear();
    _reviewDecisions.clear();
    _expandedGroupPaths.clear();
    _expandedGroupItemLimits.clear();
    _expandedReviewPaths.clear();
    _query = '';
    _filter = WorkspaceResultFilter.all;
    _directoryFilter = null;
    _reviewQueueDirectoryFilter = null;
    _reviewQueueSessionInitialPending = null;
    _sort = WorkspaceResultSort.priority;
    invalidateNarrative();
    _touch();
  }

  /// Replaces normalized verdicts and their derived selection, review and
  /// expansion state in one owner-owned transition. This is the single writer
  /// for result application, so the page never mutates these fields directly.
  void applyVerdicts(
    List<AiVerdict> verdicts, {
    Set<String>? preparedVerdictPaths,
    Set<String>? selectedPaths,
    Map<String, WorkspaceReviewDecision>? reviewDecisions,
    Set<String>? expandedGroupPaths,
    Set<String>? expandedReviewPaths,
  }) {
    _verdicts = List.unmodifiable(verdicts);
    _verdictPaths =
        preparedVerdictPaths ?? Set.unmodifiable(verdicts.map((v) => v.path));
    if (selectedPaths != null) {
      _selected
        ..clear()
        ..addAll(selectedPaths);
    } else {
      _selected.clear();
    }
    if (reviewDecisions != null) {
      _reviewDecisions
        ..clear()
        ..addAll(reviewDecisions);
      for (final verdict in verdicts) {
        if (verdict.verdict == 'review_needed' &&
            !_reviewDecisions.containsKey(verdict.path)) {
          _reviewDecisions[verdict.path] = WorkspaceReviewDecision.pending;
        }
      }
    } else {
      _reviewDecisions
        ..clear()
        ..addEntries(
          verdicts
              .where((verdict) => verdict.verdict == 'review_needed')
              .map(
                (verdict) =>
                    MapEntry(verdict.path, WorkspaceReviewDecision.pending),
              ),
        );
    }
    if (expandedGroupPaths != null) {
      _expandedGroupPaths
        ..clear()
        ..addAll(expandedGroupPaths);
    } else {
      _expandedGroupPaths.clear();
    }
    if (expandedReviewPaths != null) {
      _expandedReviewPaths
        ..clear()
        ..addAll(expandedReviewPaths);
    } else {
      _expandedReviewPaths.clear();
    }
    _touch();
  }

  /// Replaces only the verdict list while leaving selection/review/expansion
  /// state intact. Used for metadata enrichment of an already-applied result.
  void replaceVerdicts(List<AiVerdict> verdicts) {
    _verdicts = List.unmodifiable(verdicts);
    _verdictPaths = Set.unmodifiable(verdicts.map((v) => v.path));
    _touch();
  }

  void setQuery(String value) {
    _query = value;
    _touch();
  }

  void setDirectoryFilter(String? path) {
    _directoryFilter = path;
    _touch();
  }

  void setFilter(WorkspaceResultFilter value) {
    _filter = value;
    _touch();
  }

  void setSort(WorkspaceResultSort value) {
    _sort = value;
    _touch();
  }

  void toggleSelection(String path, bool? selectedValue) {
    if (selectedValue == true) {
      _selected.add(path);
    } else {
      _selected.remove(path);
    }
    _touch();
  }

  void setSelectionForPaths(Iterable<String> paths, bool selectedValue) {
    for (final path in paths) {
      if (selectedValue) {
        _selected.add(path);
      } else {
        _selected.remove(path);
      }
    }
    _touch();
  }

  void setSelectedPaths(Iterable<String> paths) {
    _selected
      ..clear()
      ..addAll(paths);
    _touch();
  }

  void setExpandedGroupPaths(Iterable<String> paths) {
    _expandedGroupPaths
      ..clear()
      ..addAll(paths);
    _touch();
  }

  void setExpandedReviewPaths(Iterable<String> paths) {
    _expandedReviewPaths
      ..clear()
      ..addAll(paths);
    _touch();
  }

  void setReviewDecision(String path, WorkspaceReviewDecision decision) {
    _reviewDecisions[path] = decision;
    if (decision == WorkspaceReviewDecision.include) {
      _selected.add(path);
    } else {
      _selected.remove(path);
    }
    _touch();
  }

  void setReviewQueue({String? directoryPath, int? initialPending}) {
    _reviewQueueDirectoryFilter = directoryPath;
    _reviewQueueSessionInitialPending = initialPending;
    _touch();
  }

  void clearReviewQueue() {
    _reviewQueueDirectoryFilter = null;
    _reviewQueueSessionInitialPending = null;
    _touch();
  }

  void setExpandedGroup(String path, bool expanded) {
    if (expanded) {
      _expandedGroupPaths.add(path);
    } else {
      _expandedGroupPaths.remove(path);
      _expandedGroupItemLimits.remove(path);
    }
    _touch();
  }

  void setExpandedGroupItemLimit(String path, int limit) {
    _expandedGroupItemLimits[path] = limit;
    _touch();
  }

  void setNormalizedGroupsCache(
    List<AiResultGroup>? groups, {
    bool includesPreclassified = false,
  }) {
    _combinedGroups = null;
    _pendingRows = null;
    _normalizedGroupsCache = groups == null
        ? null
        : List<AiResultGroup>.unmodifiable(groups);
    _normalizedGroupsCacheIncludesPreclassified =
        groups != null && includesPreclassified;
    _normalizedGroupsCacheKey = null;
  }

  void cachePreparedGroups(
    List<AiResultGroup> groups, {
    required List<Map<String, dynamic>> preClassified,
    required Map<String, int> sizeByPath,
    required String rootPath,
    required bool fullCoverage,
    required Set<String> firstLevelDirectories,
    required Set<String> directories,
  }) {
    setNormalizedGroupsCache(groups, includesPreclassified: true);
    _normalizedGroupsCacheKey = _NormalizedGroupsCacheKey(
      verdicts: _verdicts,
      preClassified: preClassified,
      sizeByPath: sizeByPath,
      rootPath: rootPath,
      useFullCoverage: fullCoverage,
      firstLevelDirectoryPaths: firstLevelDirectories,
      directoryPathsForGrouping: directories,
    );
  }

  void setExpandedReview(String path, bool expanded) {
    if (expanded) {
      _expandedReviewPaths.add(path);
    } else {
      _expandedReviewPaths.remove(path);
    }
    _touch();
  }

  void removeSelectionWhere(
    bool Function(String path) test, {
    bool notify = true,
  }) {
    _selected.removeWhere(test);
    if (notify) {
      _touch();
    }
  }

  Future<void> loadNarrativeSettings() async {
    try {
      final enabled = await _settings.conclusionNarrativeEnabled();
      final auto = await _settings.conclusionNarrativeAuto();
      if (_disposed) return;
      _narrativeEnabled = enabled;
      _narrativeAuto = auto;
      _touch();
    } catch (_) {
      // Narrative settings are optional; keep the last known values.
    }
  }

  void invalidateNarrative() {
    _narrativeGeneration++;
    _narrativeLoading = false;
    _narrativeSynthesisInFlight = false;
    _narrativeText = null;
    _narrativeSignature = null;
    _touch();
  }

  void commitNarrative(String text, String signature) {
    _narrativeText = text;
    _narrativeSignature = signature;
    _touch();
  }

  void beginNarrativeSynthesis() {
    _narrativeSynthesisInFlight = true;
    _narrativeLoading = true;
    _touch();
  }

  void finishNarrativeSynthesis() {
    _narrativeSynthesisInFlight = false;
    _narrativeLoading = false;
    _touch();
  }

  /// Starts narrative generation behind an owner/generation guard. A late
  /// completion after [rebindOwner] must not publish into the new workspace.
  Future<void> generateNarrative({
    String signature = '',
    Future<String?> Function()? synthesize,
  }) async {
    final ownerId = _ownerId;
    final generation = _narrativeGeneration;
    _narrativeSynthesisInFlight = true;
    _narrativeLoading = true;
    _touch();
    try {
      final text =
          await (synthesize?.call() ??
              _narrativeSynthesizer?.call() ??
              Future<String?>.value());
      if (!_isCurrentNarrative(ownerId, generation)) return;
      if (text != null && text.isNotEmpty) {
        _narrativeText = text;
        _narrativeSignature = signature;
      }
    } finally {
      if (_isCurrentNarrative(ownerId, generation)) {
        _narrativeSynthesisInFlight = false;
        _narrativeLoading = false;
        _touch();
      }
    }
  }

  bool _isCurrentNarrative(String? ownerId, int generation) {
    final owned = ownerId == null || _ownerId == ownerId;
    return owned && _narrativeGeneration == generation && !_disposed;
  }

  bool _disposed = false;

  void _touch() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Context-free inputs used to derive normalized/visible groups and the
/// conclusions overview. The page assembles this snapshot; the Results owner
/// owns all derivation from it.
final class AiResultsProjectionInput {
  const AiResultsProjectionInput({
    required this.verdicts,
    required this.selected,
    required this.reviewDecisions,
    required this.expandedGroupPaths,
    required this.expandedGroupItemLimits,
    required this.expandedReviewPaths,
    required this.sizeByPath,
    required this.searchTextByPath,
    required this.preClassified,
    required this.unanalyzedVerdicts,
    required this.rootPath,
    required this.targetLabel,
    required this.useFullCoverage,
    required this.truncated,
    required this.filter,
    required this.sort,
    required this.query,
    required this.directoryFilter,
    required this.showsFilteredItems,
    required this.heavyResultsLayoutThreshold,
    required this.aiResultGroupDisplayItemCap,
    required this.firstLevelDirectoryPaths,
    required this.directoryPathsForGrouping,
    required this.coverageResultsLoadTruncated,
    required this.analyzedItemCountOverride,
    this.rootSizeBytesHint,
  });

  final List<AiVerdict> verdicts;
  final Set<String> selected;
  final Map<String, WorkspaceReviewDecision> reviewDecisions;
  final Set<String> expandedGroupPaths;
  final Map<String, int> expandedGroupItemLimits;
  final Set<String> expandedReviewPaths;
  final Map<String, int> sizeByPath;
  final Map<String, String> searchTextByPath;
  final List<Map<String, dynamic>> preClassified;
  final List<AiVerdict> unanalyzedVerdicts;
  final String rootPath;
  final String targetLabel;
  final bool useFullCoverage;
  final bool truncated;
  final int? rootSizeBytesHint;
  final WorkspaceResultFilter filter;
  final WorkspaceResultSort sort;
  final String query;
  final String? directoryFilter;
  final bool showsFilteredItems;
  final int heavyResultsLayoutThreshold;
  final int aiResultGroupDisplayItemCap;
  final Set<String> firstLevelDirectoryPaths;
  final Set<String> directoryPathsForGrouping;
  final bool coverageResultsLoadTruncated;
  final int? analyzedItemCountOverride;
}

/// Identifies the stable inputs used to construct normalized result groups.
/// Progress-only state is deliberately absent; it updates the overview while
/// retaining the already merged classification groups.
final class _NormalizedGroupsCacheKey {
  _NormalizedGroupsCacheKey.fromInput(AiResultsProjectionInput input)
    : verdicts = input.verdicts,
      preClassified = input.preClassified,
      sizeByPath = input.sizeByPath,
      rootPath = input.rootPath,
      useFullCoverage = input.useFullCoverage,
      firstLevelDirectoryPaths = Set<String>.unmodifiable(
        input.firstLevelDirectoryPaths,
      ),
      directoryPathsForGrouping = Set<String>.unmodifiable(
        input.directoryPathsForGrouping,
      );

  _NormalizedGroupsCacheKey({
    required this.verdicts,
    required this.preClassified,
    required this.sizeByPath,
    required this.rootPath,
    required this.useFullCoverage,
    required this.firstLevelDirectoryPaths,
    required this.directoryPathsForGrouping,
  });
  final List<AiVerdict> verdicts;
  final List<Map<String, dynamic>> preClassified;
  final Map<String, int> sizeByPath;
  final String rootPath;
  final bool useFullCoverage;
  final Set<String> firstLevelDirectoryPaths;
  final Set<String> directoryPathsForGrouping;

  bool matches(AiResultsProjectionInput input) {
    return identical(verdicts, input.verdicts) &&
        identical(preClassified, input.preClassified) &&
        identical(sizeByPath, input.sizeByPath) &&
        rootPath == input.rootPath &&
        useFullCoverage == input.useFullCoverage &&
        setEquals(firstLevelDirectoryPaths, input.firstLevelDirectoryPaths) &&
        setEquals(directoryPathsForGrouping, input.directoryPathsForGrouping);
  }
}

/// Derived result presentation owned by [AiAnalysisResultsController].
final class AiResultsProjection {
  const AiResultsProjection({
    required this.normalizedGroups,
    required this.visibleGroups,
    required this.overview,
    required this.safeBytes,
    required this.safeItemCount,
    required this.reviewCount,
    required this.directoryBucketCount,
  });

  final List<AiResultGroup> normalizedGroups;
  final List<AiWorkspaceVisibleResultGroup> visibleGroups;
  final AiAnalysisConclusionOverview overview;
  final int safeBytes;
  final int safeItemCount;
  final int reviewCount;
  final int directoryBucketCount;
}

extension AiAnalysisResultsProjection on AiAnalysisResultsController {
  AiResultsProjection buildProjection(AiResultsProjectionInput input) {
    var normalizedGroups = _normalizedGroupsFor(input);
    if (!identical(_normalizedGroupsCache, normalizedGroups)) {
      setNormalizedGroupsCache(normalizedGroups, includesPreclassified: true);
      _normalizedGroupsCacheKey = _NormalizedGroupsCacheKey.fromInput(input);
      normalizedGroups = _normalizedGroupsCache!;
    }
    if (input.unanalyzedVerdicts.isNotEmpty) {
      if (!identical(_pendingRows, input.unanalyzedVerdicts) ||
          _combinedGroups == null) {
        _pendingRows = input.unanalyzedVerdicts;
        _combinedGroups = mergeUnanalyzedGroups(
          normalizedGroups,
          groupAiResults(
            input.unanalyzedVerdicts,
            input.sizeByPath,
            rootPath: input.rootPath,
            directoryPaths: input.directoryPathsForGrouping,
          ),
        );
      }
      normalizedGroups = _combinedGroups!;
    }
    final visibleGroups = _visibleGroupsFor(input, normalizedGroups);
    final summary = _overallSummaryFor(input, normalizedGroups);
    final overview = _overviewFor(input, normalizedGroups);
    final safeItemCount = input.useFullCoverage
        ? normalizedGroups.fold<int>(
            0,
            (total, group) => total + group.safeCount,
          )
        : normalizedGroups.fold<int>(
            0,
            (total, group) =>
                total +
                group.items
                    .where((item) => item.verdict == 'safe_to_remove')
                    .length,
          );
    return AiResultsProjection(
      normalizedGroups: normalizedGroups,
      visibleGroups: visibleGroups,
      overview: overview,
      safeBytes: summary.safeBytes,
      safeItemCount: safeItemCount,
      reviewCount: summary.reviewCount,
      directoryBucketCount: _directoryBucketCountFor(
        input.rootPath,
        normalizedGroups,
      ),
    );
  }

  List<AiResultGroup> _normalizedGroupsFor(AiResultsProjectionInput input) {
    final cached = _normalizedGroupsCache;
    // Presentation-prep caches group only provider verdicts. Local
    // preclassification is merged below, so bypass that cache whenever it is
    // present rather than undercounting the dashboard's safe total.
    if (cached != null &&
        (input.preClassified.isEmpty ||
            _normalizedGroupsCacheIncludesPreclassified) &&
        _normalizedGroupsCacheKey?.matches(input) == true) {
      return cached;
    }
    var groups = groupAiResults(
      classifiedVerdictsForGroups(input.verdicts, input.preClassified),
      input.sizeByPath,
      rootPath: input.rootPath,
      directoryPaths: input.directoryPathsForGrouping,
    );
    if (input.useFullCoverage && input.rootPath.isNotEmpty) {
      groups = ensureFirstLevelDirectoryGroups(
        groups,
        input.rootPath,
        input.firstLevelDirectoryPaths,
      );
    }
    return groups;
  }

  List<AiResultGroup> _groupsForDetailList(
    AiResultsProjectionInput input,
    List<AiResultGroup> groups,
  ) {
    final heavy =
        input.useFullCoverage ||
        input.verdicts.length >= input.heavyResultsLayoutThreshold;
    if (!heavy || input.showsFilteredItems) return groups;
    return capAiResultGroupsForDisplay(
      groups,
      input.sizeByPath,
      maxItemsPerGroup: input.aiResultGroupDisplayItemCap,
    );
  }

  List<AiWorkspaceVisibleResultGroup> _visibleGroupsFor(
    AiResultsProjectionInput input,
    List<AiResultGroup> groups,
  ) {
    final prepared = _groupsForDetailList(input, groups);
    final scanRoot = normalizeFsPath(input.rootPath);
    final visible = <AiWorkspaceVisibleResultGroup>[];
    for (final group in prepared) {
      if (input.useFullCoverage &&
          scanRoot.isNotEmpty &&
          group.path == scanRoot &&
          group.reviewCount == 0 &&
          group.safeCount == 0 &&
          group.keepCount == 0) {
        continue;
      }
      final visibleItems = group.items
          .where((item) => _itemVisible(input, item, groupPath: group.path))
          .toList(growable: false);
      final forceGroupRow =
          input.useFullCoverage &&
          input.firstLevelDirectoryPaths.contains(group.path);
      final keepShell =
          input.useFullCoverage &&
          input.filter == WorkspaceResultFilter.all &&
          group.keepCount > 0;
      if (visibleItems.isEmpty && !forceGroupRow && !keepShell) continue;
      final sortedItems = visibleItems.isEmpty
          ? const <AiVerdict>[]
          : _sortedVisibleItems(input, visibleItems);
      if (sortedItems.isEmpty && !forceGroupRow && !keepShell) continue;
      final classified = group.safeCount + group.reviewCount + group.keepCount;
      final listedBytes = visibleItems.fold<int>(
        0,
        (total, item) => total + (input.sizeByPath[item.path] ?? 0),
      );
      final displayBytes =
          visibleItems.isEmpty ||
              sortedItems.length < classified ||
              listedBytes < group.totalBytes
          ? group.totalBytes
          : listedBytes;
      visible.add(
        AiWorkspaceVisibleResultGroup(
          group: group,
          items: sortedItems,
          totalBytes: displayBytes,
          actionableCount: input.useFullCoverage
              ? group.safeCount + group.reviewCount
              : sortedItems.length,
        ),
      );
    }
    visible.sort((left, right) {
      final leftHasItems = left.items.isNotEmpty;
      final rightHasItems = right.items.isNotEmpty;
      if (leftHasItems && rightHasItems) {
        final itemOrder = _compareVisibleItems(
          input,
          left.items.first,
          right.items.first,
        );
        if (itemOrder != 0) return itemOrder;
      } else if (leftHasItems != rightHasItems) {
        return leftHasItems ? -1 : 1;
      } else {
        final reviewDiff = right.group.reviewCount.compareTo(
          left.group.reviewCount,
        );
        if (reviewDiff != 0) return reviewDiff;
        final safeDiff = right.group.safeCount.compareTo(left.group.safeCount);
        if (safeDiff != 0) return safeDiff;
      }
      final sizeOrder = right.totalBytes.compareTo(left.totalBytes);
      if (sizeOrder != 0) return sizeOrder;
      return left.group.path.compareTo(right.group.path);
    });
    return List.unmodifiable(visible);
  }

  ({int safeBytes, int reviewCount}) _overallSummaryFor(
    AiResultsProjectionInput input,
    List<AiResultGroup> groups,
  ) {
    var safeBytes = 0;
    var reviewCount = 0;
    for (final group in groups) {
      for (final item in group.items) {
        switch (item.verdict) {
          case 'safe_to_remove':
            safeBytes += input.sizeByPath[item.path] ?? 0;
          case 'review_needed':
            if (_isPendingReview(input, item)) reviewCount++;
          case 'keep':
          case 'unanalyzed':
          default:
            break;
        }
      }
    }
    return (safeBytes: safeBytes, reviewCount: reviewCount);
  }

  AiAnalysisConclusionOverview _overviewFor(
    AiResultsProjectionInput input,
    List<AiResultGroup> groups,
  ) {
    final overviewInput = AiResultOverviewBuildInput(
      targetLabel: input.targetLabel,
      rootPath: input.rootPath,
      verdicts: groups.expand((group) => group.items),
      sizeByPath: input.sizeByPath,
      rootSizeBytesHint: input.rootSizeBytesHint,
      truncated: input.truncated,
      fullCoverage: input.useFullCoverage,
      maxDirectories: 64,
      isPendingReview: (item) => _isPendingReview(input, item),
      analyzedItemCountOverride: input.analyzedItemCountOverride,
    );
    if (input.useFullCoverage && input.coverageResultsLoadTruncated) {
      return buildAiAnalysisConclusionOverviewFromGroups(overviewInput, groups);
    }
    return buildAiAnalysisConclusionOverview(overviewInput);
  }

  int _directoryBucketCountFor(String rootPath, List<AiResultGroup> groups) {
    final normalizedRoot = normalizeFsPath(rootPath);
    final buckets = <String>{};
    for (final group in groups) {
      for (final item in group.items) {
        if (item.verdict == 'unanalyzed') continue;
        final bucket = normalizedRoot.isEmpty
            ? parentFsPath(normalizeFsPath(item.path))
            : (firstLevelDirectoryUnderRoot(item.path, normalizedRoot) ??
                  normalizedRoot);
        buckets.add(bucket);
      }
    }
    return buckets.length;
  }

  bool _itemVisible(
    AiResultsProjectionInput input,
    AiVerdict item, {
    required String groupPath,
  }) {
    if (!_matchesFilter(input, item)) return false;
    if (!_matchesDirectory(input, item)) return false;
    if (!_matchesQuery(input, item)) return false;
    if (input.useFullCoverage &&
        input.filter == WorkspaceResultFilter.all &&
        item.verdict == 'keep') {
      return input.expandedGroupPaths.contains(groupPath);
    }
    return true;
  }

  List<AiVerdict> _sortedVisibleItems(
    AiResultsProjectionInput input,
    List<AiVerdict> items,
  ) {
    if (input.useFullCoverage &&
        items.length > input.heavyResultsLayoutThreshold) {
      final copy = [...items]
        ..sort((left, right) {
          final sizeOrder = (input.sizeByPath[right.path] ?? 0).compareTo(
            input.sizeByPath[left.path] ?? 0,
          );
          if (sizeOrder != 0) return sizeOrder;
          return left.path.compareTo(right.path);
        });
      return copy;
    }
    if (input.sort == WorkspaceResultSort.size) {
      return [...items]
        ..sort((left, right) => _compareVisibleItems(input, left, right));
    }
    List<AiVerdict> sortBucket(Iterable<AiVerdict> bucket) {
      final list = bucket.toList(growable: false);
      return [...list]
        ..sort((left, right) => _compareVisibleItems(input, left, right));
    }

    return [
      ...sortBucket(
        items.where(
          (item) =>
              item.verdict == 'review_needed' &&
              (input.reviewDecisions[item.path] ??
                      WorkspaceReviewDecision.pending) ==
                  WorkspaceReviewDecision.pending,
        ),
      ),
      ...sortBucket(
        items.where(
          (item) =>
              item.verdict == 'review_needed' &&
              (input.reviewDecisions[item.path] ??
                      WorkspaceReviewDecision.pending) ==
                  WorkspaceReviewDecision.include,
        ),
      ),
      ...sortBucket(
        items.where(
          (item) =>
              item.verdict == 'review_needed' &&
              (input.reviewDecisions[item.path] ??
                      WorkspaceReviewDecision.pending) ==
                  WorkspaceReviewDecision.keep,
        ),
      ),
      ...sortBucket(items.where((item) => item.verdict == 'safe_to_remove')),
      ...sortBucket(items.where((item) => item.verdict == 'keep')),
      ...sortBucket(items.where((item) => item.verdict == 'unanalyzed')),
    ];
  }

  bool _matchesDirectory(AiResultsProjectionInput input, AiVerdict item) {
    final directory = input.directoryFilter;
    if (directory == null || directory.isEmpty) return true;
    return isUnderFsRoot(
      normalizeFsPath(item.path),
      normalizeFsPath(directory),
    );
  }

  bool _matchesFilter(AiResultsProjectionInput input, AiVerdict item) {
    return switch (input.filter) {
      WorkspaceResultFilter.all => true,
      WorkspaceResultFilter.review => _isPendingReview(input, item),
      WorkspaceResultFilter.selected => input.selected.contains(item.path),
      WorkspaceResultFilter.safeToRemove => item.verdict == 'safe_to_remove',
      WorkspaceResultFilter.keep => item.verdict == 'keep',
    };
  }

  bool _matchesQuery(AiResultsProjectionInput input, AiVerdict item) {
    final query = input.query.trim().toLowerCase();
    if (query.isEmpty) return true;
    final haystack = input.searchTextByPath[item.path] ?? item.path;
    return haystack.toLowerCase().contains(query);
  }

  bool _isPendingReview(AiResultsProjectionInput input, AiVerdict item) {
    return item.verdict == 'review_needed' &&
        (input.reviewDecisions[item.path] ?? WorkspaceReviewDecision.pending) ==
            WorkspaceReviewDecision.pending;
  }

  int _compareVisibleItems(
    AiResultsProjectionInput input,
    AiVerdict left,
    AiVerdict right,
  ) {
    if (input.sort == WorkspaceResultSort.priority) {
      final priorityOrder = _priorityRank(
        input,
        left,
      ).compareTo(_priorityRank(input, right));
      if (priorityOrder != 0) return priorityOrder;
    }
    final sizeOrder = (input.sizeByPath[right.path] ?? 0).compareTo(
      input.sizeByPath[left.path] ?? 0,
    );
    if (sizeOrder != 0) return sizeOrder;
    return left.path.compareTo(right.path);
  }

  int _priorityRank(AiResultsProjectionInput input, AiVerdict item) {
    return switch (item.verdict) {
      'review_needed' => switch (input.reviewDecisions[item.path] ??
          WorkspaceReviewDecision.pending) {
        WorkspaceReviewDecision.pending => 0,
        WorkspaceReviewDecision.include => 1,
        WorkspaceReviewDecision.keep => 2,
      },
      'safe_to_remove' => 3,
      'keep' => 4,
      'unanalyzed' => 5,
      _ => 6,
    };
  }
}

class _NoopResultsSettingsPort implements WorkspaceSettingsPort {
  const _NoopResultsSettingsPort();

  @override
  Future<({int tokens, int credits})> coverageBudgetForMode(
    AiMode mode,
  ) async => (tokens: 0, credits: 0);

  @override
  Future<void> setCoverageBudgetTokens(int tokens) async {}

  @override
  Future<void> setCoverageBudgetCredits(int credits) async {}

  @override
  Future<bool> conclusionNarrativeEnabled() async => true;

  @override
  Future<bool> conclusionNarrativeAuto() async => true;

  @override
  Future<int> resolveRunBudgetCredits({
    required int estimatedCredits,
    required int accountBalance,
  }) async => estimatedCredits;

  @override
  Future<ByokTokenUsageTotals> addByokTokenUsage({
    required int inputTokens,
    required int outputTokens,
    required int totalTokens,
    required bool estimated,
    required bool partial,
  }) async => ByokTokenUsageTotals.empty;
}
