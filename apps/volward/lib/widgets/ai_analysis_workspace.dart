import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../ai/ai_analysis_gateway.dart';
import '../ai/ai_coverage_coordinator.dart';
import '../ai/ai_provider.dart';
import '../ai/ai_settings_store.dart';
import '../ai/byok_ai_provider.dart';
import '../ai/coverage_client_logic.dart';
import '../ai/coverage_models.dart';
import '../ai/coverage_job_state.dart';
import '../ai/coverage_pause_messages.dart';
import '../ai/coverage_ui_helpers.dart';
import '../ai/coverage_verdict_adapter.dart';
import '../ai/coverage_verdict_store.dart';
import '../ai/platform_ai_provider.dart';
import '../analytics/analytics.dart';
import '../analytics/analytics_events.dart';
import '../volward_session.dart';
import '../ai/ai_result_groups.dart';
import '../ai/ai_token_estimate.dart';
import '../l10n/l10n.dart';
import '../proto/ai_payload_pb_decoder.dart';
import '../scan_tree.dart';
import '../snapshot_cache.dart';
import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';
import 'coverage_job_banner.dart';
import 'apple_widgets.dart';
import 'top_toast.dart';

class _AiCandidatesBootstrap {
  const _AiCandidatesBootstrap({
    required this.preClassified,
    required this.unknown,
    required this.sizeByPath,
    required this.deleteTargetsByPath,
    required this.estimatedTokens,
    required this.estimatedByokBatchTokens,
    required this.hasExistingResult,
    required this.truncated,
    required this.candidatesBeforeCap,
    required this.selected,
    required this.resultCacheKey,
    required this.rootPath,
    this.preClassifiedTotal,
    this.unknownTotal,
    this.unknownCandidatesSpillPath,
    this.sizeByPathSpillPath,
  });

  final List<Map<String, dynamic>> preClassified;
  final List<AiCandidate> unknown;
  final Map<String, int> sizeByPath;
  final Map<String, String> deleteTargetsByPath;
  final int estimatedTokens;
  final int estimatedByokBatchTokens;
  final bool hasExistingResult;
  final bool truncated;
  final int candidatesBeforeCap;
  final Set<String> selected;
  final String resultCacheKey;
  final String rootPath;
  final int? preClassifiedTotal;
  final int? unknownTotal;
  final String? unknownCandidatesSpillPath;
  final String? sizeByPathSpillPath;
}

const _candidateHeavyListThreshold = 256;
const _candidateSpillPreviewCap = 32;

_AiCandidatesBootstrap _parseAiCandidatesFromSpillFile(String spillPath) {
  final file = File(spillPath);
  try {
    if (spillPath.endsWith('.pb')) {
      final map = decodeAiCandidatesPb(file.readAsBytesSync());
      if (map == null) {
        throw const FormatException('invalid candidates pb');
      }
      return _compactCandidatesBootstrap(
        _bootstrapFromCandidatesMap(map),
        sourcePath: spillPath,
      );
    }
    final raw = file.readAsStringSync();
    return _compactCandidatesBootstrap(
      _parseAiCandidatesPayload(raw),
      sourcePath: spillPath,
    );
  } finally {
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}

_AiCandidatesBootstrap _parseAndCompactCandidatesRaw(String raw) {
  return _compactCandidatesBootstrap(
    _parseAiCandidatesPayload(raw),
    sourcePath:
        '${Directory.systemTemp.path}/volward-candidates-${DateTime.now().microsecondsSinceEpoch}',
  );
}

_AiCandidatesBootstrap _compactCandidatesBootstrap(
  _AiCandidatesBootstrap full, {
  required String sourcePath,
}) {
  final preTotal = full.preClassified.length;
  var preClassified = full.preClassified;
  if (preClassified.length > _candidateSpillPreviewCap) {
    preClassified = preClassified
        .take(_candidateSpillPreviewCap)
        .toList(growable: false);
  }

  final unknownTotal = full.candidatesBeforeCap > full.unknown.length
      ? full.candidatesBeforeCap
      : full.unknown.length;
  var unknown = full.unknown;
  String? unknownSpill;
  var deleteTargetsByPath = full.deleteTargetsByPath;
  if (unknown.length > _candidateHeavyListThreshold) {
    unknownSpill = '$sourcePath.unknown.json';
    File(unknownSpill).writeAsStringSync(
      jsonEncode(unknown.map((candidate) => candidate.toJson()).toList()),
    );
    unknown = const [];
    deleteTargetsByPath = const {};
  }

  var sizeByPath = full.sizeByPath;
  String? sizeSpill;
  if (sizeByPath.length > _candidateHeavyListThreshold) {
    sizeSpill = '$sourcePath.sizes.json';
    File(sizeSpill).writeAsStringSync(jsonEncode(sizeByPath));
    sizeByPath = Map.fromEntries(
      preClassified
          .map((entry) {
            final path = entry['path'] as String? ?? '';
            return MapEntry(path, _asInt(entry['size_bytes']));
          })
          .where((entry) => entry.key.isNotEmpty),
    );
  }

  final selected = _selectedPathsFromPreClassifiedMaps(preClassified);

  return _AiCandidatesBootstrap(
    preClassified: preClassified,
    unknown: unknown,
    sizeByPath: sizeByPath,
    deleteTargetsByPath: deleteTargetsByPath,
    estimatedTokens: full.estimatedTokens,
    estimatedByokBatchTokens: full.estimatedByokBatchTokens,
    hasExistingResult: full.hasExistingResult,
    truncated: full.truncated,
    candidatesBeforeCap: full.candidatesBeforeCap,
    selected: selected,
    resultCacheKey: full.resultCacheKey,
    rootPath: full.rootPath,
    preClassifiedTotal: preTotal,
    unknownTotal: unknownTotal,
    unknownCandidatesSpillPath: unknownSpill,
    sizeByPathSpillPath: sizeSpill,
  );
}

List<AiCandidate> _readUnknownCandidatesFromSpill(String spillPath) {
  final file = File(spillPath);
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((raw) => AiCandidate.fromJson(Map<String, dynamic>.from(raw)))
        .toList(growable: false);
  } finally {
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}

Map<String, int> _readSizeByPathSpill(String spillPath) {
  final file = File(spillPath);
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) return const {};
    return decoded.map((key, value) => MapEntry('$key', _asInt(value)));
  } finally {
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}

enum _ReviewDecision { pending, include, keep }

enum _ResultFilterMode { all, review, selected }

enum _ResultSortMode { priority, size }

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

Set<String> _selectedPathsFromPreClassifiedMaps(
  Iterable<Map<String, dynamic>> preClassified,
) {
  final selected = <String>{};
  for (final entry in preClassified) {
    if (entry['confidence'] != 'high' || entry['deletable'] != true) continue;
    final path = entry['path'] as String?;
    if (path != null && path.isNotEmpty) selected.add(path);
  }
  return selected;
}

bool coveragePlanSummaryShowsV3PrecheckBreakdown(CoveragePlanSummary? summary) {
  if (summary == null || summary.planVersion < 3) {
    return false;
  }
  return summary.localSafeFiles != null &&
      summary.localKeepFiles != null &&
      summary.estimatedTreeCredits != null &&
      summary.estimatedTailCredits != null;
}

int? coveragePrecheckEstimatedCredits(CoveragePlanSummary? summary) {
  if (summary == null) return null;
  if (coveragePlanSummaryShowsV3PrecheckBreakdown(summary)) {
    return summary.estimatedTreeCredits! + summary.estimatedTailCredits!;
  }
  return summary.estimatedPages;
}

_AiCandidatesBootstrap _bootstrapFromCandidatesMap(Map<String, dynamic> map) {
  final sizeByPath = <String, int>{};
  final deleteTargetsByPath = <String, String>{};
  final preClassified = <Map<String, dynamic>>[];
  final preRaw = map['pre_classified'];
  if (preRaw is List) {
    for (final rawEntry in preRaw) {
      if (rawEntry is Map) {
        final entry = Map<String, dynamic>.from(rawEntry);
        preClassified.add(entry);
        final path = entry['path'] as String?;
        if (path != null) sizeByPath[path] = _asInt(entry['size_bytes']);
      }
    }
  }

  final unknown = <AiCandidate>[];
  final unknownRaw = map['unknown_candidates'];
  if (unknownRaw is List) {
    for (final rawCandidate in unknownRaw) {
      if (rawCandidate is Map) {
        final candidate = AiCandidate.fromJson(
          Map<String, dynamic>.from(rawCandidate),
        );
        unknown.add(candidate);
        sizeByPath[candidate.path] = candidate.sizeBytes;
        final deleteTarget = candidate.deleteTarget;
        if (deleteTarget != null && deleteTarget.isNotEmpty) {
          deleteTargetsByPath[candidate.path] = deleteTarget;
        }
      }
    }
  }

  final selected = _selectedPathsFromPreClassifiedMaps(preClassified);

  final estimatedTotal = _asInt(map['estimated_input_tokens']);
  final estimatedBatchRaw = _asInt(map['estimated_byok_batch_input_tokens']);
  final estimatedByokBatch = estimatedBatchRaw > 0
      ? estimatedBatchRaw
      : (unknown.isNotEmpty
            ? estimateByokBatchInputTokens(unknown, kByokAnalyzeBatchSize)
            : estimatedTotal);

  return _AiCandidatesBootstrap(
    preClassified: preClassified,
    unknown: unknown,
    sizeByPath: sizeByPath,
    deleteTargetsByPath: deleteTargetsByPath,
    estimatedTokens: estimatedTotal > 0
        ? estimatedTotal
        : (unknown.isNotEmpty
              ? estimateByokTotalInputTokens(unknown, kByokAnalyzeBatchSize)
              : 0),
    estimatedByokBatchTokens: estimatedByokBatch,
    hasExistingResult: map['has_existing_result'] == true,
    truncated: map['truncated'] == true,
    candidatesBeforeCap: _asInt(map['candidates_total_before_cap']),
    selected: selected,
    resultCacheKey: map['result_cache_key']?.toString() ?? '',
    rootPath: map['root_path']?.toString() ?? '',
  );
}

_AiCandidatesBootstrap _parseAiCandidatesPayload(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('ai candidates payload is not an object');
  }
  return _bootstrapFromCandidatesMap(Map<String, dynamic>.from(decoded));
}

class _LoadedAnalysisParseResult {
  const _LoadedAnalysisParseResult({
    required this.loadedRootPath,
    required this.entryMaps,
    required this.resultSizes,
  });

  final String loadedRootPath;
  final List<Map<String, dynamic>> entryMaps;
  final Map<String, int> resultSizes;
}

String? _readAnalysisJsonFromCacheRoot(String cacheRoot, List<String> keys) {
  final base = '$cacheRoot/ai_analysis';
  for (final key in keys) {
    if (key.isEmpty) continue;
    final pbFile = File('$base/$key.pb');
    if (pbFile.existsSync()) {
      final map = decodeAiAnalysisResultPb(pbFile.readAsBytesSync());
      if (map != null) {
        return jsonEncode({
          'root_path': map['root_path'],
          'entries': map['entries'],
        });
      }
    }
    final jsonFile = File('$base/$key.json');
    if (jsonFile.existsSync()) {
      return jsonFile.readAsStringSync();
    }
  }
  return null;
}

bool _savedAnalysisFileExists(String key) {
  if (key.isEmpty) return false;
  final base = '${SnapshotCache.cacheDir().path}/ai_analysis';
  return File('$base/$key.pb').existsSync() ||
      File('$base/$key.json').existsSync();
}

_LoadedAnalysisParseResult _parseLoadedAnalysisJsonString(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('expected object');
  }
  final map = Map<String, dynamic>.from(decoded);
  final loadedRootPath = map['root_path']?.toString() ?? '';
  final entriesRaw = map['entries'];
  if (entriesRaw is! List) {
    throw const FormatException('missing entries');
  }
  final entryMaps = <Map<String, dynamic>>[];
  final resultSizes = <String, int>{};
  for (final rawEntry in entriesRaw) {
    if (rawEntry is! Map) continue;
    final entry = Map<String, dynamic>.from(rawEntry);
    final path = entry['path'] as String?;
    if (path == null || path.isEmpty) continue;
    resultSizes[path] = _asInt(entry['size_bytes']);
    entryMaps.add(entry);
  }
  return _LoadedAnalysisParseResult(
    loadedRootPath: loadedRootPath,
    entryMaps: entryMaps,
    resultSizes: resultSizes,
  );
}

class _CandidateCleanupMeta {
  const _CandidateCleanupMeta({
    this.cleanupSource,
    this.cleanupHint,
    this.retentionDays,
  });

  final String? cleanupSource;
  final String? cleanupHint;
  final int? retentionDays;
}

class _LoadedVerdictsBuildInput {
  const _LoadedVerdictsBuildInput({
    required this.entryMaps,
    required this.candidateMetaByPath,
  });

  final List<Map<String, dynamic>> entryMaps;
  final Map<String, _CandidateCleanupMeta> candidateMetaByPath;
}

List<AiVerdict> _buildLoadedVerdicts(_LoadedVerdictsBuildInput input) {
  return input.entryMaps
      .map((entry) {
        final path = entry['path'] as String? ?? '';
        final meta = input.candidateMetaByPath[path];
        return AiVerdict(
          path: path,
          verdict: entry['verdict']?.toString() ?? '',
          confidence: entry['confidence']?.toString() ?? '',
          reason: entry['reason']?.toString() ?? '',
          cleanupSource:
              entry['cleanup_source'] as String? ?? meta?.cleanupSource,
          cleanupHint: entry['cleanup_hint'] as String? ?? meta?.cleanupHint,
          retentionDays: switch (entry['retention_days']) {
            int value => value,
            num value => value.toInt(),
            _ => meta?.retentionDays,
          },
        );
      })
      .toList(growable: false);
}

class _ResultsPresentationPrepInput {
  const _ResultsPresentationPrepInput({
    required this.verdicts,
    required this.sizeByPath,
    required this.rootPath,
    required this.directoryPaths,
    required this.maxAutoExpandedRows,
    required this.preClassified,
    required this.firstLevelDirectoryPaths,
    required this.fullCoverageLayout,
  });

  final List<AiVerdict> verdicts;
  final Map<String, int> sizeByPath;
  final String rootPath;
  final List<String> directoryPaths;
  final int maxAutoExpandedRows;
  final List<Map<String, dynamic>> preClassified;
  final List<String> firstLevelDirectoryPaths;
  final bool fullCoverageLayout;
}

class _ResultsPresentationPrepOutput {
  const _ResultsPresentationPrepOutput({
    required this.normalizedGroups,
    required this.expandedGroupPaths,
    required this.selectedPaths,
  });

  final List<AiResultGroup> normalizedGroups;
  final Set<String> expandedGroupPaths;
  final Set<String> selectedPaths;
}

Set<String> _selectedPathsForVerdictsIsolate(
  List<AiVerdict> verdicts,
  List<Map<String, dynamic>> preClassified,
) {
  final aiPaths = verdicts.map((verdict) => verdict.path).toSet();
  final selected = <String>{};
  for (final entry in preClassified) {
    if (entry['deletable'] != true || entry['confidence'] != 'high') continue;
    final path = entry['path'] as String?;
    if (path == null || path.isEmpty || aiPaths.contains(path)) continue;
    selected.add(path);
  }
  for (final verdict in verdicts) {
    if (verdict.verdict == 'safe_to_remove') {
      selected.add(verdict.path);
    }
  }
  return selected;
}

Set<String> _expandedGroupPathsForPresentation(
  List<AiResultGroup> groups, {
  required int maxAutoExpandedRows,
}) {
  var rowBudget = maxAutoExpandedRows;
  final expanded = <String>{};
  for (final group in groups) {
    final actionable = group.reviewCount > 0 || group.safeCount > 0;
    if (!actionable && group.items.length >= 3) continue;
    final rowCost = group.items.length + 1;
    if (rowBudget < rowCost) break;
    expanded.add(group.path);
    rowBudget -= rowCost;
  }
  return expanded;
}

_ResultsPresentationPrepOutput _prepareResultsPresentationIsolate(
  _ResultsPresentationPrepInput input,
) {
  var groups = groupAiResults(
    input.verdicts,
    input.sizeByPath,
    rootPath: input.rootPath,
    directoryPaths: input.directoryPaths.toSet(),
  );
  if (input.fullCoverageLayout && input.rootPath.isNotEmpty) {
    groups = ensureFirstLevelDirectoryGroups(
      groups,
      input.rootPath,
      input.firstLevelDirectoryPaths,
    );
  }
  final expanded = _expandedGroupPathsForPresentation(
    groups,
    maxAutoExpandedRows: input.maxAutoExpandedRows,
  );
  return _ResultsPresentationPrepOutput(
    normalizedGroups: groups,
    expandedGroupPaths: expanded,
    selectedPaths: _selectedPathsForVerdictsIsolate(
      input.verdicts,
      input.preClassified,
    ),
  );
}

enum _Phase { loading, precheck, privacy, analyzing, results, deleting, error }

class AiAnalysisWorkspace extends StatefulWidget {
  const AiAnalysisWorkspace({
    super.key,
    required this.snapshotId,
    required this.targetLabel,
    required this.onExit,
    required this.onOpenSettings,
    required this.onDeletingChanged,
    required this.onDeleteCompleted,
    this.gateway = const ProductionAiAnalysisGateway(),
    this.debugCoverageJobState,
  });

  static const workspaceKey = Key('ai-analysis-workspace');
  static const backKey = Key('ai-analysis-back');
  static const loadPreviousKey = Key('ai-analysis-load-previous');
  static const analyzeAgainKey = Key('ai-analysis-analyze-again');
  static const settingsKey = Key('ai-analysis-open-settings');
  static const resultsListKey = Key('ai-analysis-results-list');
  static const summaryKey = Key('ai-analysis-summary');
  static const decisionSummaryKey = Key('ai-analysis-decision-summary');
  static const searchToggleKey = Key('ai-analysis-search-toggle');
  static const deleteKey = Key('ai-analysis-delete');
  static const precheckDeleteKey = Key('ai-analysis-precheck-delete');
  static const headerKey = Key('ai-analysis-header');
  static const selectedSummaryKey = Key('ai-analysis-selected-summary');
  static const pendingReviewKey = Key('ai-analysis-pending-review');

  final String snapshotId;
  final String targetLabel;
  final VoidCallback onExit;
  final VoidCallback onOpenSettings;
  final ValueChanged<bool> onDeletingChanged;
  final VoidCallback onDeleteCompleted;
  final AiAnalysisGateway gateway;

  /// Test-only: inject a coverage job without hydrating the coordinator.
  @visibleForTesting
  final CoverageJobState? debugCoverageJobState;

  @override
  State<AiAnalysisWorkspace> createState() => _AiAnalysisWorkspaceState();
}

class _AiAnalysisWorkspaceState extends State<AiAnalysisWorkspace> {
  static const _preClassifiedPrecheckPreviewCap = 32;
  static const _maxDefaultExpandedResultRows = 96;
  static const _expandedGroupInitialItemCap = 120;
  static const _expandedGroupItemCapStep = 120;
  static const _coverageVerdictRefreshMinInterval = Duration(milliseconds: 350);
  static const _heavyResultsLayoutThreshold = 200;

  _Phase _phase = _Phase.loading;
  String? _error;
  List<Map<String, dynamic>> _preClassified = [];
  int? _preClassifiedTotalCount;
  int? _unknownTotalCount;
  String? _unknownCandidatesSpillPath;
  String? _sizeByPathSpillPath;
  List<AiCandidate> _unknown = [];
  Map<String, AiCandidate> _unknownByPath = {};
  int _estimatedTokens = 0;
  int _estimatedByokBatchTokens = 0;
  bool _hasExistingResult = false;
  bool _candidatesBootstrapPending = false;
  bool _truncated = false;
  int _candidatesBeforeCap = 0;
  String _resultCacheKey = '';
  String _rootPath = '';
  List<AiVerdict> _verdicts = [];
  final Set<String> _selected = {};
  final Map<String, _ReviewDecision> _reviewDecisions = {};
  final Set<String> _expandedGroupPaths = {};
  final Map<String, int> _expandedGroupItemLimits = {};
  final Set<String> _expandedReviewPaths = {};
  final Map<String, int> _sizeByPath = {};
  final Map<String, String> _deleteTargetsByPath = {};
  bool _hasProvider = false;
  bool _analyzing = false;
  bool _deleting = false;
  int? _partialDeleteFailedCount;
  int? _partialDeleteFreedBytes;
  List<String> _retryTargets = [];
  AiMode _mode = AiMode.off;
  int? _platformCredits;
  int _operationGeneration = 0;
  final ScrollController _resultsScrollController = ScrollController();
  final TextEditingController _resultsSearchController =
      TextEditingController();
  bool _resultsSearchExpanded = false;
  String _resultsQuery = '';
  _ResultFilterMode _resultFilterMode = _ResultFilterMode.all;
  _ResultSortMode _resultSortMode = _ResultSortMode.priority;
  List<AiResultGroup>? _normalizedGroupsCache;
  List<_VisibleResultGroup>? _visibleGroupsCache;
  CoverageJobState? _coverageJobState;
  bool _useFullCoverage = false;
  bool _coverageHydrating = false;
  bool _coverageHydrated = false;
  int? _coverageBudgetCredits;
  int? _estimatedCoverageCredits;
  CoveragePlanSummary? _coveragePlanSummary;
  bool _coveragePlanSummaryLoadInFlight = false;
  bool _coveragePlanSummaryBannerLoadAttempted = false;

  /// True after the user starts, resumes, or opens full-coverage results this visit.
  bool _coverageUserEngagedFullRun = false;

  /// After Start/Resume/Raise, stay on Analyzing until pause/complete (not Review).
  bool _coverageUiPrefersAnalyzingPhase = false;

  /// [updatedAtMs] of the paused job when Resume/Raise started (drops stale emits).
  int? _coverageStalePausedUpdatedAtMs;

  /// While true, defer coverage job [setState] until scroll ends (avoids jank).
  bool _deferCoverageJobUiForScroll = false;
  int? _runBudgetCredits;
  bool _coverageCapBelowEstimate = false;
  int _coverageVerdictPageCount = 2;
  static const _coverageVerdictPageSize = 500;

  /// Initial Full Coverage results load after job ends (more load on scroll).
  static const _maxCoverageVerdictPagesOnTerminal = 40;
  int _coverageVerdictByteOffset = 0;
  List<CoverageVerdict> _coverageVerdictRows = const [];
  DateTime? _lastCoverageVerdictRefreshAt;
  Timer? _coverageJobStateCoalesceTimer;
  CoverageJobState? _pendingCoverageJobState;
  bool _coverageVerdictPageLoadInFlight = false;
  bool _resultsLayoutPending = false;
  int _resultsLayoutGeneration = 0;
  _ResultListLayout? _resultListLayout;
  bool _resultsUserScrolling = false;
  List<CoverageVerdict>? _pendingCoverageVerdictRowsAfterScroll;
  bool _pendingCoverageVerdictRowsPreserveUi = true;

  int _beginOperation() => ++_operationGeneration;
  bool _isCurrent(int generation) =>
      mounted && generation == _operationGeneration;

  bool get _canStartCoverage {
    if (_mode != AiMode.platform) return true;
    if (_coverageCapBelowEstimate) return false;
    if (_estimatedCoverageCredits == null || _platformCredits == null) {
      return true;
    }
    return _platformCredits! >= _estimatedCoverageCredits!;
  }

  bool get _showsCoverageV3PrecheckBreakdown =>
      coveragePlanSummaryShowsV3PrecheckBreakdown(_coveragePlanSummary);

  bool get _coveragePlanIsLocalOnly {
    final summary = _coveragePlanSummary;
    if (summary == null || summary.planVersion < 3) return false;
    return !coveragePlanRequiresApi(summary);
  }

  int? get _coveragePlanMinApiCalls {
    final summary = _coveragePlanSummary;
    if (summary == null) return null;
    return coveragePlanMinApiCalls(summary);
  }

  void _rebuildUnknownByPath() {
    _unknownByPath = {for (final item in _unknown) item.path: item};
  }

  int get _displayPreClassifiedCount =>
      _preClassifiedTotalCount ?? _preClassified.length;

  int get _displayUnknownCount => _unknownTotalCount ?? _unknown.length;

  int get _precheckSelectedDeletableCount => _selected.length;

  void _selectAllPrecheckDeletableShown({required bool selected}) {
    setState(() {
      for (final entry in _preClassified.take(
        _preClassifiedPrecheckPreviewCap,
      )) {
        if (entry['deletable'] != true) continue;
        final path = entry['path'] as String?;
        if (path == null || path.isEmpty) continue;
        if (selected) {
          _selected.add(path);
        } else {
          _selected.remove(path);
        }
      }
    });
  }

  List<Widget> _buildPrecheckAiEstimateLines(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.volward;
    if (_useFullCoverage) {
      if (_coverageHydrating && _estimatedCoverageCredits == null) {
        return [
          Text(
            l10n.aiPreCheckCoverageEstimatePending,
            style: context.vwCaption,
          ),
        ];
      }
      final summary = _coveragePlanSummary;
      if (summary != null && summary.planVersion >= 3) {
        final treePending = summary.treePendingFiles ?? 0;
        final tailFiles = summary.tailFiles ?? summary.tailFileCount ?? 0;
        final minCalls = coveragePlanMinApiCalls(summary);
        final credits = _estimatedCoverageCredits ?? minCalls;
        if (_showsCoverageV3PrecheckBreakdown) {
          return [
            Text(
              l10n.aiPreCheckAiScopeV2(treePending, tailFiles, minCalls),
              style: context.vwCaption,
            ),
            if (treePending > 0) ...[
              const SizedBox(height: AppleSpacing.xxs),
              Text(
                l10n.aiPreCheckTreeCreditsMayGrow,
                style: context.vwFinePrint.copyWith(color: tokens.inkMuted80),
              ),
            ],
          ];
        }
        return [
          Text(
            l10n.aiPreCheckAiScopeV2(treePending, tailFiles, minCalls),
            style: context.vwCaption,
          ),
          if (minCalls > 0)
            Text(
              l10n.aiPreCheckFullCoverageEstimate(credits, minCalls),
              style: context.vwCaptionStrong,
            ),
          if (treePending > 0) ...[
            const SizedBox(height: AppleSpacing.xxs),
            Text(
              l10n.aiPreCheckTreeCreditsMayGrow,
              style: context.vwFinePrint.copyWith(color: tokens.inkMuted80),
            ),
          ],
        ];
      }
    }
    final batchCount = _truncated
        ? _unknown.length.clamp(0, kDefaultAiCandidateCap)
        : (_unknown.isNotEmpty
              ? _unknown.length
              : _displayUnknownCount.clamp(0, kDefaultAiCandidateCap));
    final batchTokens = _estimatedByokBatchTokens > 0
        ? _estimatedByokBatchTokens
        : (_unknown.isNotEmpty
              ? estimateByokBatchInputTokens(_unknown, kByokAnalyzeBatchSize)
              : _estimatedTokens);
    return [
      Text(
        l10n.aiPreCheckUnknownTitle(
          _displayUnknownCount,
          batchTokens,
          kByokAnalyzeBatchSize,
          kDefaultAiCandidateCap,
        ),
        style: context.vwCaption,
      ),
      if (_truncated && !_useFullCoverage)
        Text(
          l10n.aiTruncatedNotice(
            batchCount,
            _candidatesBeforeCap,
            kDefaultAiCandidateCap,
          ),
          style: AppleTypography.caption.copyWith(color: tokens.warning),
        ),
    ];
  }

  void _deleteCandidateSpillFiles() {
    for (final path in [_unknownCandidatesSpillPath, _sizeByPathSpillPath]) {
      if (path == null || path.isEmpty) continue;
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _ensureUnknownCandidatesLoaded() async {
    final unknownSpill = _unknownCandidatesSpillPath;
    final sizeSpill = _sizeByPathSpillPath;
    if (unknownSpill == null && sizeSpill == null) return;
    final unknown = unknownSpill == null
        ? _unknown
        : await compute(_readUnknownCandidatesFromSpill, unknownSpill);
    final extraSizes = sizeSpill == null
        ? const <String, int>{}
        : await compute(_readSizeByPathSpill, sizeSpill);
    if (!mounted) return;
    setState(() {
      if (unknownSpill != null) {
        _unknown = unknown;
        _rebuildUnknownByPath();
        _deleteTargetsByPath.clear();
        for (final candidate in unknown) {
          final deleteTarget = candidate.deleteTarget;
          if (deleteTarget != null && deleteTarget.isNotEmpty) {
            _deleteTargetsByPath[candidate.path] = deleteTarget;
          }
          _sizeByPath[candidate.path] = candidate.sizeBytes;
        }
        _unknownCandidatesSpillPath = null;
      }
      if (sizeSpill != null) {
        _sizeByPath.addAll(extraSizes);
        _sizeByPathSpillPath = null;
      }
    });
  }

  Map<String, _CandidateCleanupMeta> _candidateCleanupMetaByPath() {
    return {
      for (final entry in _unknownByPath.entries)
        entry.key: _CandidateCleanupMeta(
          cleanupSource: entry.value.cleanupSource,
          cleanupHint: entry.value.cleanupHint,
          retentionDays: entry.value.retentionDays,
        ),
    };
  }

  List<String> _directoryPathsForGrouping() {
    return [
      ..._unknown.where((candidate) => candidate.isDir).map((c) => c.path),
      ..._preClassified
          .where((entry) => entry['is_dir'] == true)
          .map((entry) => entry['path']?.toString() ?? '')
          .where((path) => path.isNotEmpty),
    ];
  }

  Future<void> _applyHeavyResultsPresentation({
    required List<AiVerdict> verdicts,
    required bool preserveUiState,
    Map<String, _ReviewDecision>? savedReview,
    Set<String>? savedSelected,
    Set<String>? savedExpandedGroups,
    Set<String>? savedExpandedReviews,
    void Function()? resetPresentation,
  }) async {
    final layoutGeneration = ++_resultsLayoutGeneration;
    if (mounted) {
      setState(() => _resultsLayoutPending = true);
    }
    final prep = await compute(
      _prepareResultsPresentationIsolate,
      _ResultsPresentationPrepInput(
        verdicts: verdicts,
        sizeByPath: Map<String, int>.from(_sizeByPath),
        rootPath: _rootPath,
        directoryPaths: _directoryPathsForGrouping(),
        maxAutoExpandedRows: _maxDefaultExpandedResultRows,
        preClassified: List<Map<String, dynamic>>.from(_preClassified),
        firstLevelDirectoryPaths: _scanRootFirstLevelDirectoryPaths().toList(),
        fullCoverageLayout: _useFullCoverage,
      ),
    );
    if (!mounted || layoutGeneration != _resultsLayoutGeneration) return;
    setState(() {
      _verdicts = verdicts;
      _normalizedGroupsCache = prep.normalizedGroups;
      _visibleGroupsCache = null;
      _resultsLayoutPending = false;
      if (preserveUiState && savedReview != null) {
        _reviewDecisions
          ..clear()
          ..addAll(savedReview);
        for (final verdict in verdicts) {
          if (verdict.verdict == 'review_needed' &&
              !_reviewDecisions.containsKey(verdict.path)) {
            _reviewDecisions[verdict.path] = _ReviewDecision.pending;
          }
        }
      } else {
        resetPresentation?.call();
        _reviewDecisions
          ..clear()
          ..addEntries(
            verdicts
                .where((verdict) => verdict.verdict == 'review_needed')
                .map(
                  (verdict) => MapEntry(verdict.path, _ReviewDecision.pending),
                ),
          );
      }
      if (preserveUiState && savedSelected != null) {
        _selected
          ..clear()
          ..addAll(savedSelected);
      } else {
        _selected
          ..clear()
          ..addAll(prep.selectedPaths);
      }
      if (preserveUiState && savedExpandedGroups != null) {
        _expandedGroupPaths
          ..clear()
          ..addAll(savedExpandedGroups);
      } else {
        _expandedGroupPaths
          ..clear()
          ..addAll(prep.expandedGroupPaths);
      }
      if (preserveUiState && savedExpandedReviews != null) {
        _expandedReviewPaths
          ..clear()
          ..addAll(savedExpandedReviews);
      }
      _hasExistingResult = verdicts.isNotEmpty;
    });
  }

  AiVerdict _withCandidateMeta(AiVerdict verdict) {
    final candidate = _unknownByPath[verdict.path];
    if (candidate == null) return verdict;
    return AiVerdict(
      path: verdict.path,
      verdict: verdict.verdict,
      confidence: verdict.confidence,
      reason: verdict.reason,
      cleanupSource: verdict.cleanupSource ?? candidate.cleanupSource,
      cleanupHint: verdict.cleanupHint ?? candidate.cleanupHint,
      retentionDays: verdict.retentionDays ?? candidate.retentionDays,
    );
  }

  @override
  void initState() {
    super.initState();
    AiCoverageCoordinator.instance.addJobStateListener(_onCoverageJobState);
    _bootstrap();
  }

  @override
  void dispose() {
    AiCoverageCoordinator.instance.removeJobStateListener(_onCoverageJobState);
    _coverageJobStateCoalesceTimer?.cancel();
    _deleteCandidateSpillFiles();
    _operationGeneration++;
    _resultsScrollController.dispose();
    _resultsSearchController.dispose();
    super.dispose();
  }

  void _resetResultsScroll() {
    if (_resultsScrollController.hasClients) {
      _resultsScrollController.jumpTo(0);
    }
  }

  void _resetResultsPresentation() {
    _resultsSearchController.clear();
    _resultsSearchExpanded = false;
    _resultsQuery = '';
    _resultFilterMode = _ResultFilterMode.all;
    _resultSortMode = _ResultSortMode.priority;
    _visibleGroupsCache = null;
  }

  void _invalidateResultGroups() {
    _normalizedGroupsCache = null;
    _visibleGroupsCache = null;
    _resultListLayout = null;
  }

  void _invalidateVisibleGroups() {
    _visibleGroupsCache = null;
    _resultListLayout = null;
  }

  _ResultListLayout _resultListLayoutFor(List<_VisibleResultGroup> groups) {
    final cached = _resultListLayout;
    if (cached != null && identical(cached.groups, groups)) {
      return cached;
    }
    final layout = _ResultListLayout.build(
      groups: groups,
      expandedGroupPaths: _expandedGroupPaths,
      showsFilteredItems: _showsFilteredItems,
      itemLimitFor: _expandedItemLimitFor,
    );
    _resultListLayout = layout;
    return layout;
  }

  void _queueCoverageVerdictRowsUntilScrollIdle(
    List<CoverageVerdict> rows, {
    required bool preserveUiState,
  }) {
    _pendingCoverageVerdictRowsAfterScroll = rows;
    _pendingCoverageVerdictRowsPreserveUi = preserveUiState;
  }

  void _flushPendingCoverageVerdictRowsAfterScroll() {
    final pending = _pendingCoverageVerdictRowsAfterScroll;
    if (pending == null) return;
    _pendingCoverageVerdictRowsAfterScroll = null;
    _applyCoverageVerdictRows(
      pending,
      preserveUiState: _pendingCoverageVerdictRowsPreserveUi,
    );
  }

  @override
  void didUpdateWidget(covariant AiAnalysisWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway ||
        oldWidget.snapshotId != widget.snapshotId) {
      unawaited(_bootstrap());
    }
  }

  Future<void> _bootstrap() async {
    final generation = _beginOperation();
    _resetResultsScroll();
    setState(() {
      _invalidateResultGroups();
      _resetResultsPresentation();
      _phase = _Phase.loading;
      _error = null;
      _sizeByPath.clear();
      _deleteTargetsByPath.clear();
      _selected.clear();
      _reviewDecisions.clear();
      _expandedGroupPaths.clear();
      _expandedGroupItemLimits.clear();
      _expandedReviewPaths.clear();
      _preClassified = [];
      _preClassifiedTotalCount = null;
      _unknownTotalCount = null;
      _deleteCandidateSpillFiles();
      _unknownCandidatesSpillPath = null;
      _sizeByPathSpillPath = null;
      _unknown = [];
      _unknownByPath = {};
      _verdicts = [];
      _lastCoverageVerdictRefreshAt = null;
      _analyzing = false;
      _deleting = false;
      _estimatedTokens = 0;
      _estimatedByokBatchTokens = 0;
      _hasExistingResult = false;
      _candidatesBootstrapPending = false;
      _truncated = false;
      _candidatesBeforeCap = 0;
      _resultCacheKey = '';
      _rootPath = '';
      _partialDeleteFailedCount = null;
      _partialDeleteFreedBytes = null;
      _retryTargets = [];
      _coverageJobState = null;
      _coverageVerdictByteOffset = 0;
      _coverageVerdictPageCount = 2;
      _coverageHydrating = false;
      _coverageHydrated = false;
      _coverageBudgetCredits = null;
      _estimatedCoverageCredits = null;
      _coveragePlanSummary = null;
      _runBudgetCredits = null;
      _coverageVerdictRows = const [];
      _coverageUserEngagedFullRun = false;
      _coverageUiPrefersAnalyzingPhase = false;
      _coverageStalePausedUpdatedAtMs = null;
      _coveragePlanSummaryBannerLoadAttempted = false;
    });
    try {
      final mode = await widget.gateway.getMode();
      if (!_isCurrent(generation)) return;
      final provider = await widget.gateway.resolveProvider();
      if (!_isCurrent(generation)) return;
      setState(() {
        _mode = mode;
        _hasProvider = provider != null;
      });
      int? platformCredits;
      if (mode == AiMode.platform && provider != null) {
        try {
          final quota = await provider.queryQuota();
          if (!_isCurrent(generation)) return;
          platformCredits = quota?.creditsRemaining;
        } catch (_) {
          if (!_isCurrent(generation)) return;
          platformCredits = null;
        }
      }
      if (!mounted) return;
      final l10n = context.l10n;
      final savedAnalysisOnDisk = _savedAnalysisFileExists(widget.snapshotId);
      setState(() {
        _phase = _Phase.precheck;
        _candidatesBootstrapPending = true;
        _useFullCoverage = AiCoverageCoordinator.instance.isAvailable;
        _coverageHydrating = false;
        _coverageHydrated = !_useFullCoverage;
        if (savedAnalysisOnDisk) {
          _hasExistingResult = true;
        }
      });
      final raw = await widget.gateway.buildCandidates(widget.snapshotId);
      if (!_isCurrent(generation)) return;
      if (raw == null || raw.isEmpty) {
        setState(() {
          _mode = mode;
          _platformCredits = platformCredits;
          _hasProvider = provider != null;
          _phase = _Phase.error;
          _error = l10n.aiErrorNativeUnavailable;
        });
        return;
      }
      if (raw.startsWith('error:')) {
        setState(() {
          _mode = mode;
          _platformCredits = platformCredits;
          _hasProvider = provider != null;
          _phase = _Phase.error;
          _error = raw;
        });
        return;
      }

      final _AiCandidatesBootstrap parsed;
      if (raw.startsWith('spill:')) {
        parsed = await compute(
          _parseAiCandidatesFromSpillFile,
          raw.substring('spill:'.length),
        );
      } else {
        parsed = await compute(_parseAndCompactCandidatesRaw, raw);
      }
      if (!_isCurrent(generation)) return;
      final preserveInteractivePhase =
          _phase == _Phase.results ||
          _phase == _Phase.deleting ||
          _phase == _Phase.analyzing;
      setState(() {
        _mode = mode;
        _platformCredits = platformCredits;
        _hasProvider = provider != null;
        _preClassified = parsed.preClassified;
        _preClassifiedTotalCount = parsed.preClassifiedTotal;
        _unknown = parsed.unknown;
        _unknownTotalCount = parsed.unknownTotal;
        _unknownCandidatesSpillPath = parsed.unknownCandidatesSpillPath;
        _sizeByPathSpillPath = parsed.sizeByPathSpillPath;
        _rebuildUnknownByPath();
        _sizeByPath
          ..clear()
          ..addAll(parsed.sizeByPath);
        _deleteTargetsByPath
          ..clear()
          ..addAll(parsed.deleteTargetsByPath);
        _estimatedTokens = parsed.estimatedTokens;
        _estimatedByokBatchTokens = parsed.estimatedByokBatchTokens;
        _hasExistingResult =
            parsed.hasExistingResult ||
            _hasExistingResult ||
            _verdicts.isNotEmpty;
        _truncated = parsed.truncated;
        _candidatesBeforeCap = parsed.candidatesBeforeCap;
        _resultCacheKey = parsed.resultCacheKey;
        _rootPath = parsed.rootPath.isNotEmpty ? parsed.rootPath : _rootPath;
        if (preserveInteractivePhase && _verdicts.isNotEmpty) {
          _verdicts = _verdicts.map(_withCandidateMeta).toList(growable: false);
        }
        _invalidateResultGroups();
        if (!preserveInteractivePhase) {
          _selected
            ..clear()
            ..addAll(parsed.selected);
        }
        _phase = preserveInteractivePhase ? _phase : _Phase.precheck;
        _candidatesBootstrapPending = false;
        _useFullCoverage = AiCoverageCoordinator.instance.isAvailable;
        _coverageHydrated = !_useFullCoverage;
      });
      if (!preserveInteractivePhase && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isCurrent(generation) || !mounted) return;
          final fullCoverageReady = AiCoverageCoordinator.instance.isAvailable;
          if (fullCoverageReady && !_useFullCoverage) {
            setState(() {
              _useFullCoverage = true;
              _coverageHydrated = false;
            });
          }
          if (!fullCoverageReady && !_useFullCoverage) {
            unawaited(_maybeAutoRestorePreviousSession(generation));
            return;
          }
          unawaited(() async {
            await _syncActiveCoverageJobAfterPrecheck(generation);
            if (!AiCoverageCoordinator.instance.isAvailable) {
              await _maybeAutoRestorePreviousSession(generation);
              return;
            }
            await _hydrateCoveragePrecheck(generation, mode, platformCredits);
            await _maybeAutoRestorePreviousSession(generation);
          }());
        });
      }
    } catch (error) {
      if (!_isCurrent(generation)) return;
      setState(() {
        _phase = _Phase.error;
        _error = error.toString();
      });
    }
  }

  Future<bool> _ensurePrivacyAccepted(int generation) async {
    final accepted = await widget.gateway.isPrivacyAccepted();
    if (!_isCurrent(generation)) return false;
    if (accepted) return true;
    setState(() => _phase = _Phase.privacy);
    if (!mounted) return false;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.aiPrivacyTitle),
        content: Text(l10n.aiPrivacyBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.scanActionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.aiPrivacyAccept),
          ),
        ],
      ),
    );
    if (!_isCurrent(generation)) return false;
    if (confirmed != true) {
      setState(() => _phase = _Phase.precheck);
      return false;
    }
    await widget.gateway.setPrivacyAccepted(true);
    return _isCurrent(generation);
  }

  Future<bool> _loadPreviousResult({int? bootstrapGeneration}) async {
    final generation = bootstrapGeneration ?? _beginOperation();
    final l10n = context.l10n;
    if (bootstrapGeneration == null) {
      setState(() => _error = null);
    }
    final key = _resultCacheKey.isNotEmpty
        ? _resultCacheKey
        : widget.snapshotId;
    final raw = await _loadSavedAnalysisRaw(
      cacheKey: key,
      snapshotId: widget.snapshotId,
    );
    return _applyLoadedResult(raw, l10n.aiLoadPreviousFailed, generation);
  }

  Future<String?> _loadSavedAnalysisRaw({
    required String cacheKey,
    required String snapshotId,
  }) async {
    final keys = <String>{
      if (cacheKey.isNotEmpty) cacheKey,
      if (snapshotId.isNotEmpty) snapshotId,
    }.toList(growable: false);
    if (keys.isEmpty) return null;
    final cacheRoot = SnapshotCache.cacheDir().path;
    return Isolate.run(() => _readAnalysisJsonFromCacheRoot(cacheRoot, keys));
  }

  Future<bool> _applyLoadedResult(
    String? raw,
    String failureMessage,
    int generation,
  ) async {
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) {
      if (!_isCurrent(generation)) return false;
      setState(() {
        _error = failureMessage;
        _phase = _Phase.precheck;
      });
      return false;
    }
    try {
      final parsed = await compute(_parseLoadedAnalysisJsonString, raw);
      if (!_isCurrent(generation)) return false;
      final loadedRootPath = parsed.loadedRootPath;
      final resultSizes = parsed.resultSizes;
      _sizeByPath.addAll(resultSizes);
      if (loadedRootPath.isNotEmpty) _rootPath = loadedRootPath;
      final verdicts = await compute(
        _buildLoadedVerdicts,
        _LoadedVerdictsBuildInput(
          entryMaps: parsed.entryMaps,
          candidateMetaByPath: _candidateCleanupMetaByPath(),
        ),
      );
      if (!_isCurrent(generation)) return false;
      if (verdicts.length >= _heavyResultsLayoutThreshold) {
        setState(() {
          _resetResultsPresentation();
          _selected.clear();
          _reviewDecisions.clear();
          _expandedGroupPaths.clear();
          _expandedGroupItemLimits.clear();
          _expandedReviewPaths.clear();
          _error = null;
          _phase = _Phase.results;
        });
        await _applyHeavyResultsPresentation(
          verdicts: verdicts,
          preserveUiState: false,
          resetPresentation: _resetResultsPresentation,
        );
        if (!_isCurrent(generation)) return false;
        return true;
      }
      setState(() {
        _resetResultsPresentation();
        _selected.clear();
        _reviewDecisions.clear();
        _expandedGroupPaths.clear();
        _expandedGroupItemLimits.clear();
        _expandedReviewPaths.clear();
        _verdicts = verdicts;
        _invalidateResultGroups();
        for (final verdict in verdicts) {
          if (verdict.verdict == 'review_needed') {
            _reviewDecisions[verdict.path] = _ReviewDecision.pending;
          }
        }
        _selected.addAll(_selectedPathsForResults(verdicts));
        _expandedGroupPaths.addAll(_defaultExpandedGroupPaths());
        _hasExistingResult = true;
        _error = null;
        _phase = _Phase.results;
      });
      return true;
    } catch (_) {
      if (!_isCurrent(generation)) return false;
      setState(() {
        _error = failureMessage;
        _phase = _Phase.precheck;
      });
      return false;
    }
  }

  Future<void> _startAnalysis() async {
    if (!_hasProvider || _analyzing) return;
    if (_useFullCoverage && !_coverageHydrated) return;
    await _ensureUnknownCandidatesLoaded();
    if (!mounted) return;
    if (_useFullCoverage) {
      return _startFullCoverageAnalysis();
    }
    final generation = _beginOperation();
    if (!await _ensurePrivacyAccepted(generation)) return;
    if (!_isCurrent(generation)) return;
    final provider = await widget.gateway.resolveProvider();
    if (!_isCurrent(generation)) return;
    if (provider == null) {
      setState(() => _hasProvider = false);
      return;
    }
    setState(() {
      _analyzing = true;
      _phase = _Phase.analyzing;
      _error = null;
      _resetResultsPresentation();
      _selected.clear();
      _reviewDecisions.clear();
      _expandedGroupPaths.clear();
      _expandedGroupItemLimits.clear();
      _expandedReviewPaths.clear();
      _invalidateResultGroups();
    });
    final mode = await widget.gateway.getMode();
    if (!_isCurrent(generation)) return;
    final providerLabel = mode == AiMode.platform ? 'platform' : 'byok';
    final stopwatch = Stopwatch()..start();
    var byokUsageRecorded = false;
    unawaited(
      Analytics.instance.track(AnalyticsEvents.aiAnalysisStarted, {
        'provider': providerLabel,
        'candidate_count': _displayUnknownCount,
      }),
    );
    try {
      final result = await provider.analyze(_unknown);
      final verdicts = result.verdicts;
      final model = provider is ByokAiProvider
          ? provider.model
          : 'deepseek-v4-flash';
      final byokUsage = provider is ByokAiProvider
          ? provider.lastTokenUsage
          : null;
      final inputTokens =
          byokUsage?.promptTokens ??
          (_estimatedTokens > 0
              ? _estimatedTokens
              : (_unknown.length * 8 + 200));
      final outputTokens = byokUsage?.completionTokens ?? verdicts.length * 40;
      final totalTokens = byokUsage?.totalTokens ?? inputTokens + outputTokens;
      if (provider is ByokAiProvider) {
        await _recordByokTokenUsage(
          inputTokens: inputTokens,
          outputTokens: outputTokens,
          totalTokens: totalTokens,
          estimated: !provider.hasReliableTokenUsage,
          partial: false,
        );
        byokUsageRecorded = true;
      }
      if (!_isCurrent(generation)) return;
      final cost = (inputTokens / 1e6) * 0.14 + (outputTokens / 1e6) * 0.28;
      final enrichedVerdicts = verdicts.map(_withCandidateMeta).toList();
      final entries = enrichedVerdicts
          .map(
            (verdict) => {
              'path': verdict.path,
              'size_bytes': _sizeByPath[verdict.path] ?? 0,
              'verdict': verdict.verdict,
              'confidence': verdict.confidence,
              'reason': verdict.reason,
              if (verdict.cleanupSource != null &&
                  verdict.cleanupSource!.isNotEmpty)
                'cleanup_source': verdict.cleanupSource,
              if (verdict.cleanupHint != null &&
                  verdict.cleanupHint!.isNotEmpty)
                'cleanup_hint': verdict.cleanupHint,
              if (verdict.retentionDays != null)
                'retention_days': verdict.retentionDays,
            },
          )
          .toList();
      var creditsUsed = 0;
      if (provider is PlatformAiProvider) {
        creditsUsed = provider.lastCreditsUsed;
      }
      final resultJson = jsonEncode({
        'schema_version': 1,
        'snapshot_id': widget.snapshotId,
        if (_resultCacheKey.isNotEmpty) 'cache_key': _resultCacheKey,
        if (_rootPath.isNotEmpty) 'root_path': _rootPath,
        'analyzed_at_ms': DateTime.now().millisecondsSinceEpoch,
        'mode': mode.name,
        'model': model,
        'entries': entries,
        'token_usage': {'input': inputTokens, 'output': outputTokens},
        'cost_estimate_usd': cost,
        'credits_used': creditsUsed,
      });
      if (!_isCurrent(generation)) return;
      widget.gateway.saveResult(widget.snapshotId, resultJson);
      if (!_isCurrent(generation)) return;
      unawaited(
        Analytics.instance.track(AnalyticsEvents.aiAnalysisCompleted, {
          'provider': providerLabel,
          'duration_ms': stopwatch.elapsedMilliseconds,
          'safe_count': enrichedVerdicts
              .where((verdict) => verdict.verdict == 'safe_to_remove')
              .length,
          'review_count': enrichedVerdicts
              .where((verdict) => verdict.verdict == 'review_needed')
              .length,
          'keep_count': enrichedVerdicts
              .where((verdict) => verdict.verdict == 'keep')
              .length,
        }),
      );
      if (!_isCurrent(generation)) return;
      setState(() {
        _resetResultsPresentation();
        _verdicts = enrichedVerdicts;
        _invalidateResultGroups();
        _reviewDecisions
          ..clear()
          ..addEntries(
            enrichedVerdicts
                .where((verdict) => verdict.verdict == 'review_needed')
                .map(
                  (verdict) => MapEntry(verdict.path, _ReviewDecision.pending),
                ),
          );
        _selected
          ..clear()
          ..addAll(_selectedPathsForResults(enrichedVerdicts));
        _expandedGroupPaths.addAll(_defaultExpandedGroupPaths());
        _hasExistingResult = true;
        _analyzing = false;
        _phase = _Phase.results;
      });
    } catch (error) {
      if (!byokUsageRecorded && provider is ByokAiProvider) {
        final partialUsage = provider.lastTokenUsage;
        if (partialUsage != null) {
          await _recordByokTokenUsage(
            inputTokens: partialUsage.promptTokens,
            outputTokens: partialUsage.completionTokens,
            totalTokens: partialUsage.totalTokens,
            estimated: !provider.hasReliableTokenUsage,
            partial: true,
          );
        }
      }
      if (!_isCurrent(generation)) return;
      final message = error.toString();
      if (message.contains('insufficient_credits')) {
        setState(() {
          _error = context.l10n.aiInsufficientCredits;
          _analyzing = false;
          _phase = _Phase.precheck;
          _platformCredits = 0;
        });
        return;
      }
      if (message.contains('session_expired')) {
        setState(() {
          _error = context.l10n.aiSettingsSessionExpired;
          _analyzing = false;
          _hasProvider = false;
          _phase = _Phase.precheck;
        });
        return;
      }
      final normalizedError = _normalizeAiError(error);
      unawaited(
        Analytics.instance.track(AnalyticsEvents.aiAnalysisFailed, {
          'provider': providerLabel,
          'error': normalizedError,
          'duration_ms': stopwatch.elapsedMilliseconds,
        }),
      );
      if (!_isCurrent(generation)) return;
      final configurationError = switch (normalizedError) {
        'invalid_api_key' ||
        'empty_api_key' ||
        'ai_contract_unavailable' ||
        'platform_api_unconfigured' ||
        'link_account_required' => true,
        _ => false,
      };
      setState(() {
        _analyzing = false;
        _phase = _Phase.precheck;
        _hasProvider = configurationError ? false : _hasProvider;
        _error = _localizedAiError(error);
      });
    }
  }

  /// Reads persisted job state for precheck banners (no verdict hydration).
  Future<void> _syncActiveCoverageJobAfterPrecheck(int generation) async {
    if (!AiCoverageCoordinator.instance.isAvailable) return;
    final state = await AiCoverageCoordinator.instance.loadJobState(
      widget.snapshotId,
    );
    if (!_isCurrent(generation) || !mounted || state == null) return;
    if (state.snapshotId != widget.snapshotId) return;

    final showsBanner =
        state.status == CoverageJobStatus.running ||
        state.status == CoverageJobStatus.paused;
    if (!showsBanner) return;

    setState(() => _coverageJobState = state);
    _scheduleCoveragePlanSummaryForBannerIfNeeded();
  }

  Future<CoverageJobState?> _loadCoverageJobStateForRestore() async {
    final cached = _coverageJobState ?? widget.debugCoverageJobState;
    if (cached != null && cached.snapshotId == widget.snapshotId) {
      return cached;
    }
    return AiCoverageCoordinator.instance.loadJobState(widget.snapshotId);
  }

  bool _coverageJobHasRestorableProgress(CoverageJobState state) {
    if (state.snapshotId != widget.snapshotId) return false;
    if (state.status == CoverageJobStatus.running ||
        state.status == CoverageJobStatus.idle) {
      return false;
    }
    return state.analyzedFiles > 0 ||
        state.localResolvedFiles > 0 ||
        state.usedTokens > 0 ||
        state.usedCredits > 0;
  }

  Future<bool> _coverageVerdictStoreHasRows() async {
    final store = CoverageVerdictStore(SnapshotCache.cacheDir());
    return (await store.fileByteLength(widget.snapshotId)) > 0;
  }

  Future<bool> _tryAutoRestoreCoverageResults(int generation) async {
    final state = await _loadCoverageJobStateForRestore();
    if (!_isCurrent(generation) || !mounted) return false;
    final hasStoredVerdicts = await _coverageVerdictStoreHasRows();
    final jobSuggestsRestore =
        state != null && _coverageJobHasRestorableProgress(state);
    if (!hasStoredVerdicts && !jobSuggestsRestore) return false;

    if (state != null && state.snapshotId == widget.snapshotId) {
      setState(() {
        _coverageJobState = state;
        _coverageUiPrefersAnalyzingPhase = false;
        _coverageUserEngagedFullRun = false;
      });
    }
    await _refreshVerdictsFromCoverageStore(
      incremental: false,
      allowNativeLocalBackfill: false,
      preferReadAll: hasStoredVerdicts,
    );
    if (!_isCurrent(generation) || !mounted || _verdicts.isEmpty) {
      return false;
    }
    setState(() {
      _phase = _Phase.results;
      _analyzing = false;
      _error = null;
      _hasExistingResult = true;
    });
    return true;
  }

  /// Reopens the last session (legacy saved JSON or persisted coverage verdicts).
  Future<void> _maybeAutoRestorePreviousSession(int generation) async {
    if (!_isCurrent(generation) || !mounted || _phase != _Phase.precheck) {
      return;
    }

    if (_useFullCoverage && AiCoverageCoordinator.instance.isAvailable) {
      if (await _tryAutoRestoreCoverageResults(generation)) return;
    }

    if (_hasExistingResult) {
      await _loadPreviousResult(bootstrapGeneration: generation);
    }
  }

  Future<void> _ensureCoveragePlanSummaryLoaded() async {
    if (!_useFullCoverage || _coveragePlanSummary != null) return;
    final summary = await AiCoverageCoordinator.instance.planSummary(
      widget.snapshotId,
    );
    if (!mounted) return;
    setState(() {
      _coveragePlanSummary = summary;
      _estimatedCoverageCredits = coveragePrecheckEstimatedCredits(summary);
    });
  }

  bool _coverageJobStateShowsBanner(CoverageJobState? state) {
    if (widget.debugCoverageJobState == null && !_useFullCoverage) {
      return false;
    }
    if (state == null || state.snapshotId != widget.snapshotId) return false;
    return state.status != CoverageJobStatus.idle &&
        state.status != CoverageJobStatus.cancelled &&
        state.status != CoverageJobStatus.completed;
  }

  void _scheduleCoveragePlanSummaryForBannerIfNeeded() {
    if (!_useFullCoverage || _coveragePlanSummary != null) return;
    if (_coveragePlanSummaryLoadInFlight ||
        _coveragePlanSummaryBannerLoadAttempted) {
      return;
    }
    final state = widget.debugCoverageJobState ?? _coverageJobState;
    if (!_coverageJobStateShowsBanner(state)) return;
    _coveragePlanSummaryLoadInFlight = true;
    unawaited(() async {
      try {
        await _ensureCoveragePlanSummaryLoaded();
      } finally {
        _coveragePlanSummaryLoadInFlight = false;
        _coveragePlanSummaryBannerLoadAttempted = true;
        if (mounted) setState(() {});
      }
    }());
  }

  bool _shouldShowResultsLocalPreviewHint() {
    if (!_useFullCoverage) return false;
    final job = widget.debugCoverageJobState ?? _coverageJobState;
    if (job == null) return true;
    if (job.status == CoverageJobStatus.paused) return true;
    return job.analyzedFiles == 0 && job.status == CoverageJobStatus.running;
  }

  Future<void> _openLocalOnlyResults() async {
    setState(() {
      _coverageUserEngagedFullRun = true;
      _phase = _Phase.results;
      _analyzing = false;
      _error = null;
    });
    await _refreshVerdictsFromCoverageStore(incremental: false);
    if (mounted) setState(() {});
  }

  Future<void> _hydrateCoveragePrecheck(
    int generation,
    AiMode mode,
    int? platformCredits,
  ) async {
    if (!AiCoverageCoordinator.instance.isAvailable) return;
    final budget = await AiSettingsStore.instance.coverageBudgetForMode(mode);
    if (!_isCurrent(generation) || !mounted) return;
    setState(() {
      _coverageBudgetCredits = budget.credits;
      _coverageHydrated = true;
      _coverageHydrating = true;
    });
    final summary = await AiCoverageCoordinator.instance.planSummary(
      widget.snapshotId,
    );
    if (!_isCurrent(generation) || !mounted) return;
    final estimatedCredits = coveragePrecheckEstimatedCredits(summary);
    int? runBudgetCredits;
    if (mode == AiMode.platform &&
        estimatedCredits != null &&
        platformCredits != null) {
      runBudgetCredits = await AiSettingsStore.instance.resolveRunBudgetCredits(
        estimatedCredits: estimatedCredits,
        accountBalance: platformCredits,
      );
    }
    if (!_isCurrent(generation) || !mounted) return;
    setState(() {
      _coveragePlanSummary = summary;
      _estimatedCoverageCredits = estimatedCredits;
      _runBudgetCredits = runBudgetCredits;
      _coverageHydrating = false;
    });
  }

  bool _isLightweightAnalyzingUi() {
    if (!_useFullCoverage || !_coverageUiPrefersAnalyzingPhase) return false;
    if (_phase != _Phase.analyzing) return false;
    final job = _coverageJobState;
    return _analyzing || job?.status == CoverageJobStatus.running;
  }

  List<CoverageVerdict> _coverageJobBannerVerdictRows() {
    if (_isLightweightAnalyzingUi()) return const [];
    return _coverageVerdictRows;
  }

  int _coverageJobCoalesceDelayMs() {
    if (_isLightweightAnalyzingUi()) return 1000;
    final pending = _pendingCoverageJobState;
    if (_phase == _Phase.analyzing &&
        _coverageUiPrefersAnalyzingPhase &&
        pending?.status == CoverageJobStatus.running) {
      return 1000;
    }
    return 150;
  }

  bool _shouldDeferCoverageJobUiDuringScroll() {
    if (_phase == _Phase.results || _phase == _Phase.deleting) {
      final status =
          _coverageJobState?.status ?? _pendingCoverageJobState?.status;
      if (status == CoverageJobStatus.paused ||
          status == CoverageJobStatus.completed ||
          status == CoverageJobStatus.cancelled) {
        return false;
      }
    }
    return _phase == _Phase.analyzing || _isLightweightAnalyzingUi();
  }

  Widget _wrapScrollHoldForRebuild(Widget child) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          if (_phase == _Phase.results || _phase == _Phase.deleting) {
            _resultsUserScrolling = true;
          }
          if (_shouldDeferCoverageJobUiDuringScroll()) {
            _deferCoverageJobUiForScroll = true;
          }
        } else if (notification is ScrollEndNotification) {
          if (_deferCoverageJobUiForScroll) {
            _deferCoverageJobUiForScroll = false;
            _flushPendingCoverageJobStateAfterScroll();
          }
          if (_phase == _Phase.results || _phase == _Phase.deleting) {
            _resultsUserScrolling = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _flushPendingCoverageVerdictRowsAfterScroll();
              _maybeLoadMoreCoverageVerdicts();
            });
          }
        }
        return false;
      },
      child: child,
    );
  }

  void _flushPendingCoverageJobStateAfterScroll() {
    if (_pendingCoverageJobState == null || !mounted) return;
    _coverageJobStateCoalesceTimer?.cancel();
    _coverageJobStateCoalesceTimer = null;
    // ScrollEndNotification is dispatched during layout; never setState here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _deferCoverageJobUiForScroll) return;
      final pending = _pendingCoverageJobState;
      if (pending == null) return;
      unawaited(_applyCoverageJobState(pending));
    });
  }

  void _maybeLoadMoreCoverageVerdicts() {
    if (_isLightweightAnalyzingUi()) return;
    if (!_useFullCoverage || !_resultsScrollController.hasClients) return;
    final position = _resultsScrollController.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels < position.maxScrollExtent - 240) return;
    if (_coverageVerdictRows.length <
        _coverageVerdictPageCount * _coverageVerdictPageSize) {
      return;
    }
    unawaited(_loadNextCoverageVerdictPage());
  }

  Future<void> _loadNextCoverageVerdictPage() async {
    if (_coverageVerdictPageLoadInFlight) return;
    _coverageVerdictPageLoadInFlight = true;
    try {
      final nextPageCount = _coverageVerdictPageCount + 1;
      final store = CoverageVerdictStore(SnapshotCache.cacheDir());
      final rows = await store.readPages(
        widget.snapshotId,
        pageCount: nextPageCount,
        pageSize: _coverageVerdictPageSize,
      );
      if (!mounted || rows.length <= _coverageVerdictRows.length) return;
      if (_resultsUserScrolling) {
        _coverageVerdictPageCount = nextPageCount;
        _queueCoverageVerdictRowsUntilScrollIdle(rows, preserveUiState: true);
        return;
      }
      setState(() => _coverageVerdictPageCount = nextPageCount);
      _applyCoverageVerdictRows(rows, preserveUiState: true);
    } finally {
      _coverageVerdictPageLoadInFlight = false;
    }
  }

  void _onCoverageJobState(CoverageJobState state) {
    if (state.snapshotId != widget.snapshotId || !mounted) return;
    _pendingCoverageJobState = state;
    _coverageJobStateCoalesceTimer?.cancel();
    _coverageJobStateCoalesceTimer = Timer(
      Duration(milliseconds: _coverageJobCoalesceDelayMs()),
      () {
        _coverageJobStateCoalesceTimer = null;
        if (_deferCoverageJobUiForScroll) return;
        final pending = _pendingCoverageJobState;
        if (pending == null || !mounted) return;
        unawaited(_applyCoverageJobState(pending));
      },
    );
  }

  void _markCoverageRunEngaged() {
    _coverageStalePausedUpdatedAtMs =
        _coverageJobState?.status == CoverageJobStatus.paused
        ? _coverageJobState!.updatedAtMs
        : null;
    _coverageUserEngagedFullRun = true;
    _coverageUiPrefersAnalyzingPhase = true;
    _analyzing = true;
    _phase = _Phase.analyzing;
    _error = null;
  }

  Future<void> _applyCoverageJobState(CoverageJobState state) async {
    if (state.snapshotId != widget.snapshotId) return;
    if (_deferCoverageJobUiForScroll) {
      _pendingCoverageJobState = state;
      return;
    }
    if (_phase == _Phase.results || _phase == _Phase.deleting) {
      final terminal =
          state.status == CoverageJobStatus.paused ||
          state.status == CoverageJobStatus.completed ||
          state.status == CoverageJobStatus.cancelled;
      if (terminal &&
          _verdicts.isNotEmpty &&
          state.pauseReason != CoveragePauseReason.failed) {
        if (!mounted) return;
        setState(() => _coverageJobState = state);
        return;
      }
    }
    // Persisted jobs surface on precheck as the banner only until the user
    // explicitly starts or resumes full coverage this visit.
    if (_phase == _Phase.precheck &&
        !_analyzing &&
        !_coverageUserEngagedFullRun) {
      if (!mounted) return;
      setState(() => _coverageJobState = state);
      _scheduleCoveragePlanSummaryForBannerIfNeeded();
      return;
    }
    if (coverageIgnoreStalePausedJobState(
      state: state,
      stalePausedUpdatedAtMs: _coverageStalePausedUpdatedAtMs,
    )) {
      return;
    }
    if (state.status == CoverageJobStatus.running) {
      _coverageStalePausedUpdatedAtMs = null;
    } else if (state.status == CoverageJobStatus.paused &&
        _coverageStalePausedUpdatedAtMs != null &&
        state.updatedAtMs != _coverageStalePausedUpdatedAtMs) {
      _coverageStalePausedUpdatedAtMs = null;
    }
    final incremental = _coverageVerdictByteOffset > 0 && _verdicts.isNotEmpty;
    final terminal =
        state.status == CoverageJobStatus.completed ||
        state.status == CoverageJobStatus.paused ||
        state.status == CoverageJobStatus.cancelled;
    if (terminal) {
      _coverageUiPrefersAnalyzingPhase = false;
    }
    final lightweightAnalyzing =
        _useFullCoverage &&
        _coverageUiPrefersAnalyzingPhase &&
        _phase == _Phase.analyzing &&
        state.status == CoverageJobStatus.running;
    var shouldRefreshVerdicts =
        !lightweightAnalyzing &&
        (state.analyzedFiles > 0 ||
            state.status == CoverageJobStatus.completed);
    if ((_phase == _Phase.results || _phase == _Phase.deleting) &&
        terminal &&
        _verdicts.isNotEmpty) {
      shouldRefreshVerdicts = false;
    }
    if (shouldRefreshVerdicts) {
      final now = DateTime.now();
      final running = state.status == CoverageJobStatus.running;
      final heavy =
          _coverageVerdictRows.length >= _heavyResultsLayoutThreshold ||
          state.analyzedFiles >= _heavyResultsLayoutThreshold;
      final minInterval = running && heavy
          ? const Duration(seconds: 4)
          : _coverageVerdictRefreshMinInterval;
      final dueByTime =
          _lastCoverageVerdictRefreshAt == null ||
          now.difference(_lastCoverageVerdictRefreshAt!) >= minInterval;
      final allowRefresh = terminal || (dueByTime && (!running || incremental));
      if (allowRefresh) {
        // Terminal transitions (completed/paused): paint job state first so
        // progress does not freeze while reading jsonl / heavy results layout.
        if (terminal) {
          _bumpCoverageVerdictPagesForTerminal(state);
          final inc = incremental;
          unawaited(() async {
            await _refreshVerdictsFromCoverageStore(incremental: inc);
            if (mounted) {
              _lastCoverageVerdictRefreshAt = DateTime.now();
            }
          }());
        } else {
          await _refreshVerdictsFromCoverageStore(incremental: incremental);
          _lastCoverageVerdictRefreshAt = now;
        }
      }
    }
    if (!mounted) return;
    final showResults =
        state.status == CoverageJobStatus.paused ||
        state.status == CoverageJobStatus.completed ||
        (!_coverageUiPrefersAnalyzingPhase &&
            ((state.status == CoverageJobStatus.running &&
                    state.analyzedFiles > 0) ||
                _verdicts.isNotEmpty));
    setState(() {
      _coverageJobState = state;
      _analyzing = state.status == CoverageJobStatus.running;
      if (showResults) {
        _phase = _Phase.results;
      } else if (state.status == CoverageJobStatus.running) {
        _phase = _Phase.analyzing;
      }
      if (state.pauseReason == CoveragePauseReason.failed) {
        _error = context.l10n.aiCoverageFailedReason(
          coverageFailedReasonCategory(
            context.l10n,
            state.pauseDetail,
            pauseMessage: state.pauseMessage,
          ),
        );
      } else if (state.status != CoverageJobStatus.paused ||
          state.pauseReason != CoveragePauseReason.failed) {
        _error = null;
      }
    });
    _scheduleCoveragePlanSummaryForBannerIfNeeded();
  }

  Future<List<CoverageVerdict>>
  _fetchAllLocalCoverageVerdictsFromEngine() async {
    final session = VolwardSession.instance;
    final engine = session?.treeCoverageEngine ?? session?.coverageEngine;
    if (engine == null) return const [];
    final rows = <CoverageVerdict>[];
    var cursor = 0;
    for (var pageIndex = 0; pageIndex < 256; pageIndex++) {
      final page = await engine.fetchLocalVerdictsPage(
        widget.snapshotId,
        cursor: cursor,
        limit: 5000,
      );
      if (page.verdicts.isEmpty) break;
      rows.addAll(page.verdicts);
      final next = page.nextCursor;
      if (next == null || next <= cursor) break;
      cursor = next;
    }
    return rows;
  }

  Future<void> _refreshVerdictsFromCoverageStore({
    bool incremental = false,
    bool allowNativeLocalBackfill = true,
    bool preferReadAll = false,
  }) async {
    if (_isLightweightAnalyzingUi()) return;
    try {
      final store = CoverageVerdictStore(SnapshotCache.cacheDir());
      List<CoverageVerdict> coverageVerdicts;
      if (incremental) {
        final chunk = await store.readAppendedSince(
          widget.snapshotId,
          _coverageVerdictByteOffset,
        );
        _coverageVerdictByteOffset = chunk.fileLength;
        if (chunk.appended.isEmpty) return;
        coverageVerdicts = _mergeCoverageVerdictRows(chunk.appended);
      } else {
        if (preferReadAll) {
          coverageVerdicts = await store.readAll(widget.snapshotId);
        } else {
          coverageVerdicts = await store.readPages(
            widget.snapshotId,
            pageCount: _coverageVerdictPageCount,
            pageSize: _coverageVerdictPageSize,
          );
        }
        _coverageVerdictByteOffset = await store.fileByteLength(
          widget.snapshotId,
        );
        if (coverageVerdicts.isEmpty) {
          if (_coverageVerdictByteOffset > 0) {
            return;
          }
          if (!allowNativeLocalBackfill) {
            return;
          }
          final localExpected =
              (_coveragePlanSummary?.localSafeFiles ?? 0) +
              (_coveragePlanSummary?.localKeepFiles ?? 0);
          final job = _coverageJobState;
          final jobExpectsLocal =
              job != null &&
              job.snapshotId == widget.snapshotId &&
              (job.localResolvedFiles > 0 || job.analyzedFiles > 0);
          if (localExpected > 0 ||
              jobExpectsLocal ||
              _displayPreClassifiedCount > 0) {
            final nativeLocal =
                await _fetchAllLocalCoverageVerdictsFromEngine();
            if (nativeLocal.isNotEmpty) {
              coverageVerdicts = nativeLocal;
              await store.appendAll(widget.snapshotId, nativeLocal);
              _coverageVerdictByteOffset = await store.fileByteLength(
                widget.snapshotId,
              );
            }
          }
        }
      }
      if (!mounted) return;
      await _applyCoverageVerdictRowsAsync(
        coverageVerdicts,
        preserveUiState: incremental,
      );
    } finally {
      if (mounted && _resultsLayoutPending && _verdicts.isEmpty) {
        setState(() => _resultsLayoutPending = false);
      }
    }
  }

  List<CoverageVerdict> _mergeCoverageVerdictRows(
    Iterable<CoverageVerdict> appended,
  ) {
    final byPath = {for (final row in _coverageVerdictRows) row.path: row};
    for (final row in appended) {
      byPath[row.path] = row;
    }
    final merged = byPath.values.toList();
    if (merged.length < _heavyResultsLayoutThreshold) {
      merged.sort((a, b) => a.path.compareTo(b.path));
    }
    return merged;
  }

  void _applyCoverageVerdictRows(
    List<CoverageVerdict> coverageVerdicts, {
    bool preserveUiState = false,
  }) {
    if (_resultsUserScrolling &&
        preserveUiState &&
        (_phase == _Phase.results || _phase == _Phase.deleting)) {
      _queueCoverageVerdictRowsUntilScrollIdle(
        coverageVerdicts,
        preserveUiState: preserveUiState,
      );
      return;
    }
    unawaited(
      _applyCoverageVerdictRowsAsync(
        coverageVerdicts,
        preserveUiState: preserveUiState,
      ),
    );
  }

  Future<void> _applyCoverageVerdictRowsAsync(
    List<CoverageVerdict> coverageVerdicts, {
    bool preserveUiState = false,
  }) async {
    if (_isLightweightAnalyzingUi()) return;
    final savedReview = preserveUiState
        ? Map<String, _ReviewDecision>.from(_reviewDecisions)
        : null;
    final savedSelected = preserveUiState ? Set<String>.from(_selected) : null;
    final savedExpandedGroups = preserveUiState
        ? Set<String>.from(_expandedGroupPaths)
        : null;
    final savedExpandedReviews = preserveUiState
        ? Set<String>.from(_expandedReviewPaths)
        : null;
    final savedPresentation = preserveUiState
        ? (
            query: _resultsQuery,
            filter: _resultFilterMode,
            sort: _resultSortMode,
          )
        : null;
    final verdicts = coverageVerdictsToAiVerdicts(
      coverageVerdicts,
    ).map(_withCandidateMeta).toList();
    for (final verdict in coverageVerdicts) {
      if (verdict.sizeBytes > 0) {
        _sizeByPath[verdict.path] = verdict.sizeBytes;
      }
    }
    if (verdicts.length >= _heavyResultsLayoutThreshold) {
      if (mounted) {
        setState(() {
          _coverageVerdictRows = coverageVerdicts;
          if (preserveUiState && savedPresentation != null) {
            _resultsQuery = savedPresentation.query;
            _resultFilterMode = savedPresentation.filter;
            _resultSortMode = savedPresentation.sort;
          } else {
            _resetResultsPresentation();
          }
        });
      }
      await _applyHeavyResultsPresentation(
        verdicts: verdicts,
        preserveUiState: preserveUiState,
        savedReview: savedReview,
        savedSelected: savedSelected,
        savedExpandedGroups: savedExpandedGroups,
        savedExpandedReviews: savedExpandedReviews,
        resetPresentation: _resetResultsPresentation,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _coverageVerdictRows = coverageVerdicts;
      if (preserveUiState && savedPresentation != null) {
        _resultsQuery = savedPresentation.query;
        _resultFilterMode = savedPresentation.filter;
        _resultSortMode = savedPresentation.sort;
      } else {
        _resetResultsPresentation();
      }
      _verdicts = verdicts;
      _invalidateResultGroups();
      if (preserveUiState && savedReview != null) {
        _reviewDecisions
          ..clear()
          ..addAll(savedReview);
        for (final verdict in verdicts) {
          if (verdict.verdict == 'review_needed' &&
              !_reviewDecisions.containsKey(verdict.path)) {
            _reviewDecisions[verdict.path] = _ReviewDecision.pending;
          }
        }
      } else {
        _reviewDecisions
          ..clear()
          ..addEntries(
            verdicts
                .where((verdict) => verdict.verdict == 'review_needed')
                .map(
                  (verdict) => MapEntry(verdict.path, _ReviewDecision.pending),
                ),
          );
      }
      if (preserveUiState && savedSelected != null) {
        _selected
          ..clear()
          ..addAll(savedSelected);
      } else {
        _selected
          ..clear()
          ..addAll(_selectedPathsForResults(verdicts));
      }
      if (preserveUiState && savedExpandedGroups != null) {
        _expandedGroupPaths
          ..clear()
          ..addAll(savedExpandedGroups);
      } else {
        _expandedGroupPaths.addAll(_defaultExpandedGroupPaths());
      }
      if (preserveUiState && savedExpandedReviews != null) {
        _expandedReviewPaths
          ..clear()
          ..addAll(savedExpandedReviews);
      }
      _hasExistingResult = verdicts.isNotEmpty;
      _resultsLayoutPending = false;
    });
  }

  Future<void> _startFullCoverageAnalysis() async {
    final generation = _beginOperation();
    await _ensureUnknownCandidatesLoaded();
    if (!mounted) return;
    if (!await _ensurePrivacyAccepted(generation)) return;
    if (!_isCurrent(generation)) return;
    final provider = await widget.gateway.resolveProvider();
    if (!_isCurrent(generation)) return;
    if (provider == null) {
      setState(() => _hasProvider = false);
      return;
    }
    final mode = await widget.gateway.getMode();
    if (!_isCurrent(generation)) return;
    setState(() {
      _markCoverageRunEngaged();
      _coverageCapBelowEstimate = false;
      _coverageVerdictByteOffset = 0;
      _coverageVerdictRows = const [];
      _resetResultsPresentation();
      _selected.clear();
      _reviewDecisions.clear();
      _expandedGroupPaths.clear();
      _expandedGroupItemLimits.clear();
      _expandedReviewPaths.clear();
      _invalidateResultGroups();
    });
    if (!_isCurrent(generation) || !mounted) return;
    // Do not await the heavy native plan/job work on this call stack — keeps
    // the analyzing spinner responsive while startFullCoverage runs.
    unawaited(
      _finishStartFullCoverage(
        generation: generation,
        mode: mode,
        provider: provider,
      ),
    );
  }

  Future<void> _finishStartFullCoverage({
    required int generation,
    required AiMode mode,
    required AiProvider provider,
  }) async {
    final result = await AiCoverageCoordinator.instance.startFullCoverage(
      snapshotId: widget.snapshotId,
      mode: mode,
      provider: provider,
      budgetCredits: _runBudgetCredits,
      preloadedPlanSummary: _coveragePlanSummary,
    );
    if (!mounted || !_isCurrent(generation)) return;
    if (result is StartCoverageBlocked &&
        result.reason == StartCoverageBlockedReason.capBelowEstimate) {
      setState(() {
        _analyzing = false;
        _coverageUiPrefersAnalyzingPhase = false;
        _phase = _Phase.precheck;
        _error = null;
        _coverageCapBelowEstimate = true;
      });
      return;
    }
    if (result is StartFullCoverageUnavailable) {
      setState(() {
        _analyzing = false;
        _coverageUiPrefersAnalyzingPhase = false;
        _phase = _Phase.precheck;
        _error = context.l10n.aiCoverageUnavailable;
      });
      return;
    }
    if (result is StartFullCoverageLocalOnly) {
      await _openLocalOnlyResults();
    }
  }

  Future<void> _resumeFullCoverage() async {
    final state = _coverageJobState;
    if (state != null && coverageJobNeedsClientLogicUpgrade(state)) {
      final l10n = context.l10n;
      final legacyOk = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.aiCoverageLegacyResumeTitle),
          content: Text(l10n.aiCoverageLegacyResumeBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.scanActionCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.aiCoverageLegacyResumeConfirm),
            ),
          ],
        ),
      );
      if (legacyOk != true || !mounted) return;
    }
    if (state?.pauseReason == CoveragePauseReason.failed) {
      final l10n = context.l10n;
      final count = state!.failedBatchPaths.isNotEmpty
          ? state.failedBatchPaths.length
          : 1;
      final resumeBody = state.creditsChargedNoVerdict > 0
          ? l10n.aiCoverageFailedResumeBody(
              state.creditsChargedNoVerdict,
              count,
            )
          : l10n.aiCoverageFailedResumeBodyNoCredit(count);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.aiCoverageFailedResumeTitle),
          content: Text(resumeBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.scanActionCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.aiCoverageFailedResumeConfirm),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final provider = await widget.gateway.resolveProvider();
    if (provider == null) {
      if (mounted) setState(() => _hasProvider = false);
      return;
    }
    setState(_markCoverageRunEngaged);
    await AiCoverageCoordinator.instance.prepareService(provider);
    final resumed = await AiCoverageCoordinator.instance.tryResumeCoverage(
      widget.snapshotId,
    );
    if (!resumed && mounted) {
      showTopToast(context, message: context.l10n.aiCoverageBusyOtherSnapshot);
    }
  }

  Future<void> _cancelFullCoverage() async {
    await AiCoverageCoordinator.instance.cancelCoverage(widget.snapshotId);
  }

  Future<void> _restartFullCoverage() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.aiCoverageRestartFullTitle),
        content: Text(l10n.aiCoverageRestartFullBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.scanActionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.aiCoverageRestartFullConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AiCoverageCoordinator.instance.cancelCoverage(widget.snapshotId);
    AiCoverageCoordinator.instance.invalidatePlanSummaryCache();
    if (!mounted) return;
    setState(() {
      _coveragePlanSummary = null;
      _coveragePlanSummaryBannerLoadAttempted = false;
      _coverageJobState = null;
    });
    await _startFullCoverageAnalysis();
  }

  Future<void> _raiseConfiguredCoverageCap() async {
    final estimated = _estimatedCoverageCredits;
    if (estimated == null) return;
    final currentLimit =
        _coverageBudgetCredits ?? AiSettingsStore.defaultCoverageBudgetCredits;
    final suggested = (estimated * 1.2).ceil();
    if (suggested <= currentLimit) return;
    final l10n = context.l10n;
    final controller = TextEditingController(text: '$suggested');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.aiCoverageRaiseBudgetTitle),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.aiSettingsCoverageBudgetCreditsHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.scanActionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.aiCoverageRaiseBudget),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final parsed = int.tryParse(controller.text.trim());
    if (parsed == null || parsed <= currentLimit) {
      if (mounted) {
        showTopToast(context, message: l10n.aiCoverageBudgetInvalid);
      }
      return;
    }
    await AiSettingsStore.instance.setCoverageBudgetCredits(parsed);
    if (!mounted) return;
    setState(() {
      _coverageBudgetCredits = parsed;
      _coverageCapBelowEstimate = false;
    });
  }

  bool _coverageJobBillingModeMismatch(CoverageJobState job) =>
      !coverageJobBillingMatchesMode(_mode, job);

  String? _coverageJobBillingModeMismatchBannerMessage(CoverageJobState job) {
    if (!_coverageJobBillingModeMismatch(job)) return null;
    final l10n = context.l10n;
    final targetMode = switch (coverageJobBillingKind(job)) {
      CoverageJobBillingKind.tokens => l10n.aiSettingsByokLabel,
      CoverageJobBillingKind.credits => l10n.aiSettingsPlatformLabel,
      CoverageJobBillingKind.unset => l10n.aiSettingsOffLabel,
    };
    return l10n.aiCoverageJobBillingModeMismatchBanner(targetMode);
  }

  Future<void> _showCoverageBillingModeMismatchDialog(
    CoverageJobState job,
  ) async {
    final l10n = context.l10n;
    final body = switch (coverageJobBillingKind(job)) {
      CoverageJobBillingKind.tokens =>
        l10n.aiCoverageJobBillingModeMismatchPlatform(
          job.budgetTokens,
          job.usedTokens,
        ),
      CoverageJobBillingKind.credits =>
        l10n.aiCoverageJobBillingModeMismatchByok(
          job.usedCredits,
          job.budgetCredits,
        ),
      CoverageJobBillingKind.unset =>
        l10n.aiCoverageJobBillingModeMismatchBanner(l10n.aiSettingsOffLabel),
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.aiCoverageJobBillingModeMismatchTitle),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.scanActionCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(_restartFullCoverage());
            },
            child: Text(l10n.aiCoverageRestartFull),
          ),
        ],
      ),
    );
  }

  Future<void> _raiseCoverageBudget() async {
    final state = _coverageJobState;
    if (state == null) return;
    if (_coverageJobBillingModeMismatch(state)) {
      await _showCoverageBillingModeMismatchDialog(state);
      return;
    }
    final l10n = context.l10n;
    final isTokenBudget = state.budgetTokens > 0;
    final currentLimit = isTokenBudget
        ? state.budgetTokens
        : state.budgetCredits;
    final settings = await AiSettingsStore.instance.coverageBudgetForMode(
      isTokenBudget ? AiMode.byok : AiMode.platform,
    );
    if (!mounted) return;
    final suggested = isTokenBudget
        ? coverageSuggestedTokenBudgetRaise(
            jobBudgetTokens: currentLimit,
            settingsBudgetTokens: settings.tokens,
          )
        : coverageSuggestedCreditBudgetRaise(
            jobBudgetCredits: currentLimit,
            settingsBudgetCredits: settings.credits,
          );
    final controller = TextEditingController(text: '$suggested');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.aiCoverageRaiseBudgetTitle),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isTokenBudget
                ? l10n.aiSettingsCoverageBudgetTokensHint
                : l10n.aiSettingsCoverageBudgetCreditsHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.scanActionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.aiCoverageRaiseBudget),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final parsed = int.tryParse(controller.text.trim());
    if (parsed == null || parsed <= currentLimit) {
      if (mounted) {
        showTopToast(context, message: l10n.aiCoverageBudgetInvalid);
      }
      return;
    }
    if (isTokenBudget) {
      await AiSettingsStore.instance.setCoverageBudgetTokens(parsed);
    } else {
      await AiSettingsStore.instance.setCoverageBudgetCredits(parsed);
    }
    final provider = await widget.gateway.resolveProvider();
    if (provider == null) {
      if (mounted) setState(() => _hasProvider = false);
      return;
    }
    if (mounted) setState(_markCoverageRunEngaged);
    await AiCoverageCoordinator.instance.prepareService(provider);
    final raised = await AiCoverageCoordinator.instance.tryRaiseBudgetAndResume(
      snapshotId: widget.snapshotId,
      budgetTokens: isTokenBudget ? parsed : 0,
      budgetCredits: isTokenBudget ? 0 : parsed,
    );
    if (!raised && mounted) {
      showTopToast(context, message: context.l10n.aiCoverageBusyOtherSnapshot);
    }
  }

  Widget? _buildCoverageBanner() {
    final state = widget.debugCoverageJobState ?? _coverageJobState;
    if (!_coverageJobStateShowsBanner(state)) return null;
    final job = state!;
    final billingMismatch = _coverageJobBillingModeMismatch(job);
    return CoverageJobBanner(
      state: job,
      verdictRows: _coverageJobBannerVerdictRows(),
      planSummary: _coveragePlanSummary,
      showPausedBeforeProgressNotice: _phase == _Phase.results,
      billingModeMismatch: billingMismatch,
      billingModeMismatchMessage: billingMismatch
          ? _coverageJobBillingModeMismatchBannerMessage(job)
          : null,
      onPause: job.status == CoverageJobStatus.running
          ? () => unawaited(AiCoverageCoordinator.instance.pauseCoverage())
          : null,
      onResume: job.status == CoverageJobStatus.paused && !billingMismatch
          ? () => unawaited(_resumeFullCoverage())
          : null,
      onCancel:
          (job.status == CoverageJobStatus.running ||
              job.status == CoverageJobStatus.paused)
          ? () => unawaited(_cancelFullCoverage())
          : null,
      onRaiseBudget:
          job.status == CoverageJobStatus.paused &&
              job.pauseReason == CoveragePauseReason.budget
          ? () => unawaited(_raiseCoverageBudget())
          : null,
      onRestart: coverageJobNeedsClientLogicUpgrade(job) || billingMismatch
          ? () => unawaited(_restartFullCoverage())
          : null,
    );
  }

  List<AiVerdict> _unanalyzedVerdicts() {
    final state = _coverageJobState;
    if (!_useFullCoverage || state == null) return const [];
    if (state.status == CoverageJobStatus.completed) return const [];
    final pending = state.totalUnclassified - state.analyzedFiles;
    if (pending <= 0) return const [];
    return buildUnanalyzedDisplayVerdicts(
      pendingFileCount: pending,
      previewCandidates: _unknown,
      verdictPaths: _verdicts.map((verdict) => verdict.path).toSet(),
      itemReason: context.l10n.aiCoverageUnanalyzedReason,
      aggregateSummaryReason: (remaining) =>
          context.l10n.aiCoverageUnanalyzedAggregate(remaining),
    );
  }

  Future<void> _recordByokTokenUsage({
    required int inputTokens,
    required int outputTokens,
    required int totalTokens,
    required bool estimated,
    required bool partial,
  }) async {
    try {
      final totals = await widget.gateway.recordByokTokenUsage(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: totalTokens,
        estimated: estimated,
        partial: partial,
      );
      unawaited(
        Analytics.instance.track(AnalyticsEvents.aiByokTokenUsageRecorded, {
          'input_tokens': inputTokens,
          'output_tokens': outputTokens,
          'total_tokens': totalTokens,
          'usage_source': partial
              ? estimated
                    ? 'estimate_partial'
                    : 'provider_partial'
              : estimated
              ? 'estimate'
              : 'provider',
          'cumulative_input_tokens': totals.inputTokens,
          'cumulative_output_tokens': totals.outputTokens,
          'cumulative_total_tokens': totals.totalTokens,
          'cumulative_analysis_count': totals.analysisCount,
          'cumulative_estimated_count': totals.estimatedAnalysisCount,
          'cumulative_partial_count': totals.partialAnalysisCount,
        }),
      );
    } catch (_) {
      // Usage accounting must not turn a completed AI request into failure.
    }
  }

  String _localizedAiError(Object error) {
    return switch (_normalizeAiError(error)) {
      'request_timeout' => context.l10n.aiErrorTimeout,
      'rate_limited_after_retries' => context.l10n.aiErrorRateLimited,
      'network_error' => context.l10n.aiErrorNetwork,
      'invalid_api_key' || 'empty_api_key' => context.l10n.aiNoApiKey,
      'ai_contract_unavailable' ||
      'platform_api_unconfigured' => context.l10n.aiContractUnavailable,
      'link_account_required' => context.l10n.aiSettingsSessionExpired,
      _ => context.l10n.aiErrorUnknown,
    };
  }

  static String _normalizeAiError(Object error) {
    final message = error.toString();
    for (final key in const [
      'invalid_api_key',
      'request_timeout',
      'rate_limited_after_retries',
      'empty_api_key',
      'insufficient_credits',
      'link_account_required',
      'session_expired',
      'ai_contract_unavailable',
      'platform_api_unconfigured',
    ]) {
      if (message.contains(key)) return key;
    }
    if (message.contains('api_error:')) return 'api_error';
    if (message.contains('network_error')) return 'network_error';
    return 'unknown';
  }

  List<String> _deleteTargets() {
    if (_retryTargets.isNotEmpty) return List.of(_retryTargets);
    final targets = <String>{};
    for (final path in _selected) {
      final deleteTarget = _deleteTargetsByPath[path];
      if (deleteTarget != null && deleteTarget.isNotEmpty) {
        targets.add(deleteTarget);
      } else {
        targets.add(path);
      }
    }
    return targets.toList();
  }

  Future<void> _deleteSelected() async {
    if (_deleting) return;
    final targets = _deleteTargets();
    if (targets.isEmpty) return;
    final returnToPrecheck =
        _phase == _Phase.precheck && _verdicts.isEmpty && !_analyzing;
    final selectedPaths = Set<String>.from(_selected);
    final generation = _beginOperation();
    final l10n = context.l10n;
    setState(() {
      _error = null;
      _partialDeleteFailedCount = null;
      _partialDeleteFreedBytes = null;
    });
    final Map<String, dynamic> preview;
    try {
      preview = await widget.gateway.deleteEntries(
        targets,
        snapshotId: widget.snapshotId,
        dryRun: true,
      );
      if (!_isCurrent(generation)) return;
    } catch (error) {
      if (!_isCurrent(generation)) return;
      setState(() => _error = l10n.deleteFailed(error.toString()));
      return;
    }
    final count = (preview['deleted_count'] as num?)?.toInt() ?? targets.length;
    final freed = (preview['freed_bytes'] as num?)?.toInt() ?? _selectedBytes;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmMessage(count, _formatBytes(freed))),
        actions: [
          AppleButton(
            label: l10n.scanActionCancel,
            variant: AppleButtonVariant.pearl,
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          AppleButton(
            label: l10n.deleteActionDelete,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (!_isCurrent(generation) || confirmed != true) return;
    var completed = false;
    setState(() {
      _deleting = true;
      _phase = _Phase.deleting;
    });
    widget.onDeletingChanged(true);
    try {
      final report = await widget.gateway.deleteEntries(
        targets,
        snapshotId: widget.snapshotId,
        rescanAfterDelete: true,
      );
      if (!_isCurrent(generation)) return;
      final error = report['error'];
      if (error != null) {
        setState(() {
          _phase = _Phase.results;
          _error = l10n.deleteFailed(error.toString());
        });
        return;
      }
      final failed = report['failed_paths'];
      final failedCount = failed is List ? failed.length : 0;
      final failedTargets = failed is List
          ? failed.whereType<String>().toList(growable: false)
          : const <String>[];
      final freedAfter = (report['freed_bytes'] as num?)?.toInt() ?? 0;
      final deletedCount =
          (report['deleted_count'] as num?)?.toInt() ??
          (targets.length - failedCount);
      if (!_isCurrent(generation)) return;
      unawaited(
        Analytics.instance.track(AnalyticsEvents.aiDeletionConfirmed, {
          'suggested_count': targets.length,
          'deleted_count': deletedCount,
          'freed_mb': freedAfter / 1e6,
        }),
      );
      if (failedCount > 0) {
        setState(() {
          _phase = returnToPrecheck ? _Phase.precheck : _Phase.results;
          _partialDeleteFailedCount = failedCount;
          _partialDeleteFreedBytes = freedAfter;
          _retryTargets = failedTargets;
          _error = l10n.aiWorkspacePartialDelete(
            failedCount,
            _formatBytes(freedAfter),
          );
        });
        return;
      }
      completed = true;
      _retryTargets = [];
      if (returnToPrecheck) {
        setState(() {
          _preClassified.removeWhere(
            (entry) => selectedPaths.contains(entry['path']?.toString() ?? ''),
          );
          _selected.removeWhere(selectedPaths.contains);
          if (_preClassifiedTotalCount != null) {
            _preClassifiedTotalCount =
                (_preClassifiedTotalCount! - selectedPaths.length).clamp(
                  0,
                  1 << 30,
                );
          }
          for (final path in selectedPaths) {
            _sizeByPath.remove(path);
            _deleteTargetsByPath.remove(path);
          }
        });
      }
    } catch (error) {
      if (!_isCurrent(generation)) return;
      setState(() {
        _phase = returnToPrecheck ? _Phase.precheck : _Phase.results;
        _error = l10n.deleteFailed(error.toString());
      });
    } finally {
      if (_isCurrent(generation)) {
        setState(() {
          _deleting = false;
          _phase = returnToPrecheck ? _Phase.precheck : _Phase.results;
        });
        widget.onDeletingChanged(false);
      }
    }
    if (completed && _isCurrent(generation)) widget.onDeleteCompleted();
  }

  void _toggle(String path, bool? selected) {
    setState(() {
      if (selected == true) {
        _selected.add(path);
      } else {
        _selected.remove(path);
      }
      if (_resultFilterMode == _ResultFilterMode.selected) {
        _invalidateVisibleGroups();
      }
    });
  }

  void _confirmReviewDecision(String path, _ReviewDecision decision) {
    setState(() {
      _reviewDecisions[path] = decision;
      switch (decision) {
        case _ReviewDecision.include:
          _selected.add(path);
          break;
        case _ReviewDecision.keep:
        case _ReviewDecision.pending:
          _selected.remove(path);
          break;
      }
      _invalidateVisibleGroups();
    });
  }

  void _toggleSafeGroup(Iterable<AiVerdict> items, bool selected) {
    setState(() {
      for (final item in items) {
        if (item.verdict != 'safe_to_remove') continue;
        if (selected) {
          _selected.add(item.path);
        } else {
          _selected.remove(item.path);
        }
      }
      if (_resultFilterMode == _ResultFilterMode.selected) {
        _invalidateVisibleGroups();
      }
    });
  }

  Set<String> _selectedPathsForResults(Iterable<AiVerdict> verdicts) {
    final aiPaths = verdicts.map((verdict) => verdict.path).toSet();
    final selected = <String>{
      ..._preClassifiedVerdicts(deletable: true)
          .where((verdict) => !aiPaths.contains(verdict.path))
          .map((verdict) => verdict.path),
    };
    for (final verdict in verdicts) {
      switch (verdict.verdict) {
        case 'safe_to_remove':
          selected.add(verdict.path);
          break;
        case 'review_needed':
          if ((_reviewDecisions[verdict.path] ?? _ReviewDecision.pending) ==
              _ReviewDecision.include) {
            selected.add(verdict.path);
          }
          break;
        case 'keep':
          break;
      }
    }
    return selected;
  }

  Set<String> _defaultExpandedGroupPaths() {
    return _expandedGroupPathsForPresentation(
      _normalizedResultGroups(),
      maxAutoExpandedRows: _maxDefaultExpandedResultRows,
    );
  }

  void _bumpCoverageVerdictPagesForTerminal(CoverageJobState state) {
    if (!_useFullCoverage || state.analyzedFiles <= 0) return;
    final needed = (state.analyzedFiles / _coverageVerdictPageSize).ceil();
    final target = needed.clamp(2, _maxCoverageVerdictPagesOnTerminal);
    if (target > _coverageVerdictPageCount) {
      _coverageVerdictPageCount = target;
    }
  }

  int get _selectedBytes =>
      _selected.fold(0, (total, path) => total + (_sizeByPath[path] ?? 0));

  static String _formatBytes(num? bytes) {
    if (bytes == null) return '-';
    final value = bytes.toInt();
    if (value < 1024) return '$value B';
    if (value < 1048576) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1073741824) {
      return '${(value / 1048576).toStringAsFixed(1)} MB';
    }
    return '${(value / 1073741824).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    return DecoratedBox(
      key: AiAnalysisWorkspace.workspaceKey,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          _WorkspaceHeader(
            phaseLabel: _phaseLabel(context),
            phaseStep: _phaseStep,
            onBack: _deleting ? null : widget.onExit,
          ),
          Divider(height: 1, color: tokens.dividerSoft),
          Expanded(child: _buildPhaseBody()),
        ],
      ),
    );
  }

  String _phaseLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (_phase) {
      _Phase.loading => l10n.aiWorkspacePhaseLoading,
      _Phase.precheck => l10n.aiWorkspacePhasePrecheck,
      _Phase.privacy => l10n.aiWorkspacePhasePrivacy,
      _Phase.analyzing => l10n.aiWorkspacePhaseAnalyzing,
      _Phase.results => l10n.aiWorkspacePhaseReview,
      _Phase.deleting => l10n.aiWorkspacePhaseDeleting,
      _Phase.error => l10n.aiWorkspacePhaseRecovery,
    };
  }

  int get _phaseStep => switch (_phase) {
    _Phase.loading || _Phase.error => 1,
    _Phase.precheck => 2,
    _Phase.privacy || _Phase.analyzing => 3,
    _Phase.results => 4,
    _Phase.deleting => 5,
  };

  Widget _buildPhaseBody() {
    return switch (_phase) {
      _Phase.loading => _buildProgressBody(
        label: context.l10n.aiWorkspacePhaseLoading,
        candidateCount: 0,
      ),
      _Phase.precheck || _Phase.privacy => _buildPrecheck(),
      _Phase.analyzing => _wrapScrollHoldForRebuild(_buildAnalyzingBody()),
      _Phase.results ||
      _Phase.deleting => _wrapScrollHoldForRebuild(_buildResults()),
      _Phase.error => _buildError(),
    };
  }

  String _modeLabel() {
    final l10n = context.l10n;
    return switch (_mode) {
      AiMode.platform => l10n.aiSettingsPlatformLabel,
      AiMode.byok => l10n.aiSettingsByokLabel,
      AiMode.off => l10n.aiSettingsOffLabel,
    };
  }

  Widget _buildAnalyzingBody() {
    if (_useFullCoverage &&
        _verdicts.isNotEmpty &&
        !_coverageUiPrefersAnalyzingPhase) {
      return _buildResults();
    }
    final l10n = context.l10n;
    final job = _coverageJobState;
    final useCoverageProgress =
        _useFullCoverage && job != null && job.snapshotId == widget.snapshotId;
    final subtitle = useCoverageProgress
        ? l10n.aiCoverageProgress(job.analyzedFiles, job.totalUnclassified)
        : '${l10n.scanProgressItems(job?.totalUnclassified ?? _unknown.length)} · ${_modeLabel()}';
    return ListView(
      padding: const EdgeInsets.all(AppleSpacing.lg),
      children: [
        if (_buildCoverageBanner() case final banner?) ...[
          banner,
          const SizedBox(height: AppleSpacing.lg),
        ],
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppleSpacing.md),
              Text(l10n.aiWorkspacePhaseAnalyzing, style: context.vwBodyStrong),
              const SizedBox(height: AppleSpacing.xs),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: context.vwCaption.copyWith(
                  color: context.volward.inkMuted80,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBody({
    required String label,
    required int candidateCount,
  }) {
    final tokens = context.volward;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppleSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppleSpacing.md),
            Text(label, style: context.vwBodyStrong),
            const SizedBox(height: AppleSpacing.xs),
            Text(
              '${context.l10n.scanProgressItems(candidateCount)} · ${_modeLabel()}',
              textAlign: TextAlign.center,
              style: AppleTypography.caption.copyWith(color: tokens.inkMuted80),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrecheck() {
    final l10n = context.l10n;
    final tokens = context.volward;
    final canAnalyze =
        _hasProvider &&
        !_candidatesBootstrapPending &&
        _canStartCoverage &&
        !(_mode == AiMode.platform && _platformCredits == 0) &&
        (!_useFullCoverage || _coverageHydrated) &&
        !_coveragePlanIsLocalOnly;
    final needsSettings =
        !_hasProvider || (_mode == AiMode.platform && _platformCredits == 0);
    final configurationMessage = !_hasProvider
        ? (_error ??
              (_mode == AiMode.platform
                  ? l10n.aiSettingsSessionExpired
                  : l10n.aiNoApiKey))
        : l10n.aiInsufficientCredits;
    return ListView(
      padding: const EdgeInsets.all(AppleSpacing.lg),
      children: [
        if (_buildCoverageBanner() case final banner?) ...[
          banner,
          const SizedBox(height: AppleSpacing.md),
        ],
        Text(
          l10n.aiPreCheckSafeTitle(_displayPreClassifiedCount),
          style: context.vwBodyStrong,
        ),
        const SizedBox(height: AppleSpacing.xs),
        ..._buildPrecheckAiEstimateLines(context),
        if (_mode == AiMode.platform &&
            _platformCredits != null &&
            !(_useFullCoverage && _estimatedCoverageCredits != null)) ...[
          const SizedBox(height: AppleSpacing.xs),
          Text(
            l10n.aiPrecheckCreditsCost(_platformCredits!),
            style: context.vwCaption,
          ),
        ],
        if (_useFullCoverage &&
            _mode == AiMode.platform &&
            _showsCoverageV3PrecheckBreakdown) ...[
          const SizedBox(height: AppleSpacing.xs),
          Text(
            l10n.aiCoverageLocalResolved(
              _coveragePlanSummary!.localSafeFiles! +
                  _coveragePlanSummary!.localKeepFiles!,
            ),
          ),
          if ((_coveragePlanMinApiCalls ?? 0) > 0) ...[
            Text(
              l10n.aiCoverageEstimatedTreeRounds(
                _coveragePlanSummary!.estimatedTreeCredits!,
              ),
            ),
            Text(
              l10n.aiCoverageEstimatedTailRounds(
                _coveragePlanSummary!.estimatedTailCredits!,
              ),
            ),
            Text(
              l10n.aiCoverageEstimatedCreditsTotal(_estimatedCoverageCredits!),
            ),
          ],
          if (_platformCredits != null)
            Text(l10n.aiCoverageAccountBalance(_platformCredits!)),
          if (_runBudgetCredits != null)
            Text(l10n.aiCoverageRunCapConfigured(_runBudgetCredits!)),
          if ((_coveragePlanMinApiCalls ?? 0) >= 10)
            Text(
              l10n.aiCoveragePurchaseFooterConditional,
              style: context.vwCaption,
            ),
        ] else if (_useFullCoverage &&
            _mode == AiMode.platform &&
            _estimatedCoverageCredits != null) ...[
          const SizedBox(height: AppleSpacing.xs),
          Text(l10n.aiCoverageEstimatedCredits(_estimatedCoverageCredits!)),
          if (_platformCredits != null)
            Text(l10n.aiCoverageAccountBalance(_platformCredits!)),
          if (_runBudgetCredits != null)
            Text(l10n.aiCoverageRunCapConfigured(_runBudgetCredits!)),
          if ((_coveragePlanMinApiCalls ?? _estimatedCoverageCredits!) >= 10)
            Text(
              l10n.aiCoveragePurchaseFooterConditional,
              style: context.vwCaption,
            ),
        ],
        if (_useFullCoverage &&
            _platformCredits != null &&
            _estimatedCoverageCredits != null &&
            _platformCredits! < _estimatedCoverageCredits!) ...[
          const SizedBox(height: AppleSpacing.xs),
          Text(
            l10n.aiCoverageInsufficientForEstimate(
              _estimatedCoverageCredits!,
              _platformCredits!,
            ),
            style: AppleTypography.caption.copyWith(color: tokens.warning),
          ),
        ],
        if (_useFullCoverage &&
            _mode == AiMode.platform &&
            _coverageCapBelowEstimate &&
            _estimatedCoverageCredits != null &&
            _coverageBudgetCredits != null) ...[
          const SizedBox(height: AppleSpacing.xs),
          Text(
            l10n.aiCoverageBudgetPausedCredits(
              (_estimatedCoverageCredits! * 1.2).ceil(),
              _coverageBudgetCredits!,
            ),
            style: AppleTypography.caption.copyWith(color: tokens.warning),
          ),
          const SizedBox(height: AppleSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: AppleButton(
              label: l10n.aiCoverageRaiseBudgetToEstimate,
              icon: Icons.trending_up_outlined,
              variant: AppleButtonVariant.pearl,
              onPressed: () => unawaited(_raiseConfiguredCoverageCap()),
            ),
          ),
        ],
        if (_useFullCoverage) ...[
          const SizedBox(height: AppleSpacing.xs),
          Text(
            _mode == AiMode.platform
                ? l10n.aiCoverageFullRunPlatformHint
                : l10n.aiCoverageFullRunHint,
            style: context.vwCaption,
          ),
          if (_mode == AiMode.platform &&
              _coverageBudgetCredits != null &&
              (_coverageJobState == null ||
                  _coverageJobState!.status == CoverageJobStatus.idle)) ...[
            const SizedBox(height: AppleSpacing.xxs),
            Text(
              l10n.aiCoverageRunBudgetConfigured(_coverageBudgetCredits!),
              style: context.vwCaptionStrong,
            ),
          ],
          if (_coverageHydrating) ...[
            const SizedBox(height: AppleSpacing.xs),
            Text(l10n.aiCoverageHydrating, style: context.vwCaption),
          ],
          if (_candidatesBootstrapPending) ...[
            const SizedBox(height: AppleSpacing.xs),
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppleSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.aiCandidatesBootstrapLoading,
                    style: context.vwCaption,
                  ),
                ),
              ],
            ),
          ],
          if (_mode == AiMode.platform &&
              _platformCredits != null &&
              _coverageBudgetCredits != null &&
              _platformCredits! < _coverageBudgetCredits!) ...[
            const SizedBox(height: AppleSpacing.xs),
            Text(
              l10n.aiCoveragePlatformBudgetWarning(
                _platformCredits!,
                _coverageBudgetCredits!,
              ),
              style: AppleTypography.caption.copyWith(color: tokens.warning),
            ),
          ],
        ],
        if (needsSettings) ...[
          const SizedBox(height: AppleSpacing.md),
          Text(
            configurationMessage,
            style: AppleTypography.caption.copyWith(color: tokens.warning),
          ),
          const SizedBox(height: AppleSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: AppleButton(
              key: AiAnalysisWorkspace.settingsKey,
              label: l10n.settingsTitle,
              icon: Icons.settings_outlined,
              variant: AppleButtonVariant.pearl,
              onPressed: widget.onOpenSettings,
            ),
          ),
        ] else if (_error != null) ...[
          const SizedBox(height: AppleSpacing.md),
          Text(
            _error!,
            style: AppleTypography.caption.copyWith(color: tokens.danger),
          ),
          const SizedBox(height: AppleSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: AppleButton(
              label: l10n.aiActionRetry,
              icon: Icons.refresh_outlined,
              variant: AppleButtonVariant.pearl,
              onPressed: _startAnalysis,
            ),
          ),
        ],
        if (_preClassified.isNotEmpty) ...[
          const SizedBox(height: AppleSpacing.lg),
          Text(
            l10n.aiPreCheckSafeSelectable(_displayPreClassifiedCount),
            style: context.vwCaptionStrong,
          ),
          const SizedBox(height: AppleSpacing.xxs),
          Wrap(
            spacing: AppleSpacing.sm,
            runSpacing: AppleSpacing.xxs,
            children: [
              TextButton(
                onPressed: () =>
                    _selectAllPrecheckDeletableShown(selected: true),
                child: Text(l10n.aiPreCheckSelectAllShown),
              ),
              if (_selected.isNotEmpty)
                TextButton(
                  onPressed: () =>
                      _selectAllPrecheckDeletableShown(selected: false),
                  child: Text(l10n.aiPreCheckClearSelection),
                ),
            ],
          ),
          const SizedBox(height: AppleSpacing.xxs),
          ..._preClassified
              .take(_preClassifiedPrecheckPreviewCap)
              .map(_preClassifiedTile),
          if (_displayPreClassifiedCount >
              _preClassifiedPrecheckPreviewCap) ...[
            const SizedBox(height: AppleSpacing.xxs),
            Text(
              l10n.aiCoverageFailedBatchPathsOverflow(
                _displayPreClassifiedCount - _preClassifiedPrecheckPreviewCap,
              ),
              style: context.vwFinePrint,
            ),
          ],
          if (_precheckSelectedDeletableCount > 0) ...[
            const SizedBox(height: AppleSpacing.md),
            Text(
              l10n.aiResultsSelectedForCleanup(
                _precheckSelectedDeletableCount,
                _formatBytes(_selectedBytes),
              ),
              style: context.vwCaptionStrong,
            ),
            const SizedBox(height: AppleSpacing.xs),
            AppleButton(
              key: AiAnalysisWorkspace.precheckDeleteKey,
              label: l10n.aiDeleteSelected(_precheckSelectedDeletableCount),
              icon: Icons.delete_outline,
              expanded: true,
              onPressed: _deleting ? null : _deleteSelected,
            ),
          ],
        ],
        if (_useFullCoverage &&
            _coverageHydrated &&
            _coveragePlanIsLocalOnly) ...[
          const SizedBox(height: AppleSpacing.md),
          Text(l10n.aiPreCheckLocalOnlyTitle, style: context.vwBodyStrong),
          const SizedBox(height: AppleSpacing.xxs),
          Text(l10n.aiPreCheckLocalOnlyBody, style: context.vwCaption),
          const SizedBox(height: AppleSpacing.sm),
          AppleButton(
            label: l10n.aiStartLocalOnly,
            icon: Icons.checklist_outlined,
            expanded: true,
            onPressed: () => unawaited(_openLocalOnlyResults()),
          ),
        ],
        const SizedBox(height: AppleSpacing.lg),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_hasExistingResult) ...[
              AppleButton(
                key: AiAnalysisWorkspace.loadPreviousKey,
                label: l10n.aiWorkspaceLoadPrevious,
                variant: AppleButtonVariant.secondary,
                expanded: true,
                onPressed: _loadPreviousResult,
              ),
              const SizedBox(height: AppleSpacing.xs),
            ],
            if (!_coveragePlanIsLocalOnly)
              AppleButton(
                key: _hasExistingResult
                    ? AiAnalysisWorkspace.analyzeAgainKey
                    : null,
                label: _hasExistingResult
                    ? l10n.aiWorkspaceAnalyzeAgain
                    : l10n.aiStartAnalysis,
                icon: Icons.auto_awesome_outlined,
                expanded: true,
                onPressed: canAnalyze ? _startAnalysis : null,
              ),
          ],
        ),
      ],
    );
  }

  Widget _preClassifiedTile(Map<String, dynamic> entry) {
    final path = entry['path'] as String? ?? '';
    final deletable = entry['deletable'] == true;
    final confidence = entry['confidence']?.toString() ?? '';
    final reason = entry['reason']?.toString() ?? '';
    final size = _asInt(entry['size_bytes']);
    return Material(
      color: Colors.transparent,
      child: CheckboxListTile(
        value: deletable ? _selected.contains(path) : false,
        onChanged: deletable ? (value) => _toggle(path, value) : null,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: _PathLabel(path),
        subtitle: Text(
          '${_formatBytes(size)} · $confidence'
          '${reason.isNotEmpty ? ' · $reason' : ''}',
        ),
      ),
    );
  }

  List<AiVerdict> _preClassifiedVerdicts({required bool deletable}) {
    final items = <AiVerdict>[];
    for (final entry in _preClassified) {
      final isDeletable = entry['deletable'] == true;
      if (isDeletable != deletable) continue;
      final path = entry['path'] as String? ?? '';
      if (path.isEmpty) continue;
      items.add(
        AiVerdict(
          path: path,
          verdict: deletable ? 'safe_to_remove' : 'keep',
          confidence: entry['confidence']?.toString() ?? 'high',
          reason: entry['reason']?.toString() ?? '',
        ),
      );
    }
    return items;
  }

  List<AiResultGroup> _normalizedResultGroups() {
    final cached = _normalizedGroupsCache;
    if (cached != null) return cached;
    final localSafe = _preClassifiedVerdicts(deletable: true);
    final localKeep = _preClassifiedVerdicts(deletable: false);
    final aiSafe = _verdicts
        .where((verdict) => verdict.verdict == 'safe_to_remove')
        .toList();
    final aiPaths = _verdicts.map((verdict) => verdict.path).toSet();
    final merged = [
      ...localSafe.where((verdict) => !aiPaths.contains(verdict.path)),
      ...aiSafe,
      ...localKeep,
      ..._verdicts.where((verdict) => verdict.verdict == 'review_needed'),
      ..._verdicts.where((verdict) => verdict.verdict == 'keep'),
      ..._unanalyzedVerdicts(),
    ];
    final directoryPaths = <String>{
      ..._unknown
          .where((candidate) => candidate.isDir)
          .map((candidate) => candidate.path),
      ..._preClassified
          .where((entry) => entry['is_dir'] == true)
          .map((entry) => entry['path']?.toString() ?? '')
          .where((path) => path.isNotEmpty),
    };
    var groups = groupAiResults(
      merged,
      _sizeByPath,
      rootPath: _rootPath,
      directoryPaths: directoryPaths,
    );
    if (_useFullCoverage && _rootPath.isNotEmpty) {
      groups = ensureFirstLevelDirectoryGroups(
        groups,
        _rootPath,
        _scanRootFirstLevelDirectoryPaths(),
      );
    }
    _normalizedGroupsCache = groups;
    return groups;
  }

  Set<String> _scanRootFirstLevelDirectoryPaths() {
    final root = normalizeFsPath(_rootPath);
    if (root.isEmpty) return const {};
    final dirs = <String>{};
    void consider(String path) {
      if (path.isEmpty) return;
      final bucket = firstLevelDirectoryUnderRoot(path, root);
      if (bucket == null || bucket == root) return;
      dirs.add(bucket);
    }

    for (final candidate in _unknown) {
      consider(candidate.path);
    }
    for (final entry in _preClassified) {
      consider(entry['path']?.toString() ?? '');
    }
    for (final row in _coverageVerdictRows) {
      consider(row.path);
    }
    for (final verdict in _verdicts) {
      consider(verdict.path);
    }
    return dirs;
  }

  _OverallResultSummaryData _overallResultSummaryFor(
    List<AiResultGroup> groups,
  ) {
    var safeBytes = 0;
    var reviewCount = 0;
    for (final group in groups) {
      for (final item in group.items) {
        switch (item.verdict) {
          case 'safe_to_remove':
            safeBytes += _sizeByPath[item.path] ?? 0;
            break;
          case 'review_needed':
            if (_isPendingReview(item)) reviewCount++;
            break;
          case 'keep':
            break;
        }
      }
    }
    return _OverallResultSummaryData(
      safeBytes: safeBytes,
      reviewCount: reviewCount,
    );
  }

  bool _isPendingReview(AiVerdict item) {
    return item.verdict == 'review_needed' &&
        (_reviewDecisions[item.path] ?? _ReviewDecision.pending) ==
            _ReviewDecision.pending;
  }

  int _pendingReviewCountFor(Iterable<AiVerdict> items) {
    return items.where(_isPendingReview).length;
  }

  List<_VisibleResultGroup> _visibleResultGroups(List<AiResultGroup> groups) {
    final cached = _visibleGroupsCache;
    if (cached != null) return cached;
    final requiredFirstLevel = _useFullCoverage
        ? _scanRootFirstLevelDirectoryPaths()
        : const <String>{};
    final scanRoot = normalizeFsPath(_rootPath);
    final visibleGroups = <_VisibleResultGroup>[];
    for (final group in groups) {
      if (_useFullCoverage &&
          scanRoot.isNotEmpty &&
          group.path == scanRoot &&
          group.reviewCount == 0 &&
          group.safeCount == 0) {
        continue;
      }
      final visibleItems = group.items
          .where(_matchesPresentationFilters)
          .toList(growable: false);
      final forceGroupRow =
          _useFullCoverage && requiredFirstLevel.contains(group.path);
      if (visibleItems.isEmpty && !forceGroupRow) continue;
      final sortedItems = visibleItems.isEmpty
          ? const <AiVerdict>[]
          : _sortedVisibleItems(visibleItems);
      if (sortedItems.isEmpty && !forceGroupRow) continue;
      visibleGroups.add(
        _VisibleResultGroup(
          group: group,
          items: sortedItems,
          totalBytes: visibleItems.fold<int>(
            0,
            (total, item) => total + (_sizeByPath[item.path] ?? 0),
          ),
        ),
      );
    }
    visibleGroups.sort((left, right) {
      final leftHasItems = left.items.isNotEmpty;
      final rightHasItems = right.items.isNotEmpty;
      if (leftHasItems && rightHasItems) {
        final itemOrder = _compareVisibleItems(
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
    _visibleGroupsCache = visibleGroups;
    return visibleGroups;
  }

  List<AiVerdict> _sortedVisibleItems(List<AiVerdict> items) {
    if (_resultSortMode == _ResultSortMode.size) {
      return [...items]..sort(_compareVisibleItems);
    }
    List<AiVerdict> sortBucket(Iterable<AiVerdict> bucket) {
      final list = bucket.toList(growable: false);
      return [...list]..sort((left, right) {
        final sizeOrder = (_sizeByPath[right.path] ?? 0).compareTo(
          _sizeByPath[left.path] ?? 0,
        );
        if (sizeOrder != 0) return sizeOrder;
        return left.path.compareTo(right.path);
      });
    }

    return [
      ...sortBucket(
        items.where(
          (item) =>
              item.verdict == 'review_needed' &&
              (_reviewDecisions[item.path] ?? _ReviewDecision.pending) ==
                  _ReviewDecision.pending,
        ),
      ),
      ...sortBucket(
        items.where(
          (item) =>
              item.verdict == 'review_needed' &&
              (_reviewDecisions[item.path] ?? _ReviewDecision.pending) ==
                  _ReviewDecision.include,
        ),
      ),
      ...sortBucket(
        items.where(
          (item) =>
              item.verdict == 'review_needed' &&
              (_reviewDecisions[item.path] ?? _ReviewDecision.pending) ==
                  _ReviewDecision.keep,
        ),
      ),
      ...sortBucket(items.where((item) => item.verdict == 'safe_to_remove')),
      ...sortBucket(items.where((item) => item.verdict == 'keep')),
      ...sortBucket(items.where((item) => item.verdict == 'unanalyzed')),
    ];
  }

  int _expandedItemLimitFor(String groupPath, int itemCount) {
    if (_showsFilteredItems) return itemCount;
    if (!_expandedGroupPaths.contains(groupPath)) return 0;
    final cap =
        _expandedGroupItemLimits[groupPath] ?? _expandedGroupInitialItemCap;
    return cap.clamp(0, itemCount);
  }

  void _toggleGroupExpanded(String path) {
    setState(() {
      if (_expandedGroupPaths.contains(path)) {
        _expandedGroupPaths.remove(path);
        _expandedGroupItemLimits.remove(path);
      } else {
        _expandedGroupPaths.add(path);
      }
      _resultListLayout = null;
    });
  }

  void _showMoreItemsInGroup(String groupPath, int total) {
    final current =
        _expandedGroupItemLimits[groupPath] ?? _expandedGroupInitialItemCap;
    setState(() {
      _expandedGroupItemLimits[groupPath] =
          (current + _expandedGroupItemCapStep).clamp(0, total);
      _resultListLayout = null;
    });
  }

  void _toggleReviewExpanded(String path) {
    setState(() {
      if (_expandedReviewPaths.contains(path)) {
        _expandedReviewPaths.remove(path);
      } else {
        _expandedReviewPaths
          ..clear()
          ..add(path);
      }
    });
  }

  bool? _safeGroupSelectionValue(Iterable<AiVerdict> items) {
    final safeItems = items
        .where((item) => item.verdict == 'safe_to_remove')
        .toList(growable: false);
    if (safeItems.isEmpty) return false;
    final selectedSafeCount = safeItems
        .where((item) => _selected.contains(item.path))
        .length;
    if (selectedSafeCount == 0) return false;
    if (selectedSafeCount == safeItems.length) return true;
    return null;
  }

  bool get _showsFilteredItems =>
      _resultsQuery.trim().isNotEmpty ||
      _resultFilterMode != _ResultFilterMode.all;

  bool _matchesPresentationFilters(AiVerdict item) {
    if (!_matchesResultFilter(item)) return false;
    if (_useFullCoverage &&
        _resultFilterMode == _ResultFilterMode.all &&
        item.verdict == 'keep') {
      return false;
    }
    return _matchesResultsQuery(item);
  }

  bool _matchesResultFilter(AiVerdict item) {
    return switch (_resultFilterMode) {
      _ResultFilterMode.all => true,
      _ResultFilterMode.review => _isPendingReview(item),
      _ResultFilterMode.selected => _selected.contains(item.path),
    };
  }

  bool _matchesResultsQuery(AiVerdict item) {
    final query = _resultsQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    final haystacks = <String>[
      item.path,
      item.reason,
      item.cleanupSource ?? '',
      _cleanupSourceLabel(item) ?? '',
      item.cleanupHint ?? '',
      _retentionHintLabel(item) ?? '',
      _cleanupMetaLabel(item) ?? '',
    ];
    return haystacks.any((value) => value.toLowerCase().contains(query));
  }

  int _compareVisibleItems(AiVerdict left, AiVerdict right) {
    if (_resultSortMode == _ResultSortMode.priority) {
      final priorityOrder = _priorityRank(left).compareTo(_priorityRank(right));
      if (priorityOrder != 0) return priorityOrder;
    }
    final sizeOrder = (_sizeByPath[right.path] ?? 0).compareTo(
      _sizeByPath[left.path] ?? 0,
    );
    if (sizeOrder != 0) return sizeOrder;
    return left.path.compareTo(right.path);
  }

  int _priorityRank(AiVerdict item) {
    return switch (item.verdict) {
      'review_needed' => switch (_reviewDecisions[item.path] ??
          _ReviewDecision.pending) {
        _ReviewDecision.pending => 0,
        _ReviewDecision.include => 1,
        _ReviewDecision.keep => 2,
      },
      'safe_to_remove' => 3,
      'keep' => 4,
      'unanalyzed' => 5,
      _ => 6,
    };
  }

  String _groupSummaryLabel(_VisibleResultGroup group) {
    if (_useFullCoverage && group.items.isEmpty) {
      final full = group.group;
      if (full.reviewCount == 0 && full.safeCount == 0) {
        return context.l10n.aiResultsGroupItems(0, _formatBytes(0));
      }
    }
    return context.l10n.aiResultsGroupItems(
      group.items.length,
      _formatBytes(group.totalBytes),
    );
  }

  List<String> _groupMetadataLabels(_VisibleResultGroup group) {
    final full = group.group;
    final itemSource = group.items.isEmpty && _useFullCoverage
        ? full.items
        : group.items;
    final visibleSafeCount = itemSource
        .where((item) => item.verdict == 'safe_to_remove')
        .length;
    final visibleSelectedCount = group.items
        .where((item) => _selected.contains(item.path))
        .length;
    return [
      context.l10n.aiResultsGroupSafe(visibleSafeCount),
      context.l10n.aiResultsGroupReview(_pendingReviewCountFor(itemSource)),
      context.l10n.aiResultsGroupKeep(
        itemSource.where((item) => item.verdict == 'keep').length,
      ),
      if (visibleSelectedCount > 0)
        context.l10n.aiResultsSelectedInGroup(visibleSelectedCount),
    ];
  }

  String _reviewStatusLabel(_ReviewDecision decision) {
    final l10n = context.l10n;
    return switch (decision) {
      _ReviewDecision.pending => l10n.aiResultsNeedsYourDecision,
      _ReviewDecision.include => l10n.aiResultsAddedToCleanup,
      _ReviewDecision.keep => l10n.aiResultsKeptOutOfCleanup,
    };
  }

  Widget _buildResultStreamRow(_ResultListRow row) {
    return RepaintBoundary(
      child: switch (row) {
        _ResultListGroupRow(:final visibleGroup) => _ResultGroupRow(
          key: row.key,
          group: visibleGroup.group,
          expanded: _expandedGroupPaths.contains(visibleGroup.group.path),
          selectionValue: _safeGroupSelectionValue(visibleGroup.items),
          onSelectionChanged:
              visibleGroup.items
                  .where((item) => item.verdict == 'safe_to_remove')
                  .isEmpty
              ? null
              : (value) => _toggleSafeGroup(visibleGroup.items, value == true),
          onTap: () => _toggleGroupExpanded(visibleGroup.group.path),
          summaryLabel: _groupSummaryLabel(visibleGroup),
          metadataLabels: _groupMetadataLabels(visibleGroup),
        ),
        _ResultListShowMoreRow(:final groupPath, :final shown, :final total) =>
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: row.key,
              onPressed: () => _showMoreItemsInGroup(groupPath, total),
              child: Text(
                context.l10n.aiResultsShowMoreInGroup(
                  (total - shown).clamp(1, total),
                ),
              ),
            ),
          ),
        _ResultListItemRow(:final item) => _ResultRow(
          key: row.key,
          item: item,
          sizeLabel: _formatBytes(_sizeByPath[item.path] ?? 0),
          selected: _selected.contains(item.path),
          reviewDecision:
              _reviewDecisions[item.path] ?? _ReviewDecision.pending,
          onChanged: item.verdict == 'safe_to_remove'
              ? (value) => _toggle(item.path, value)
              : null,
          onTap: switch (item.verdict) {
            'safe_to_remove' => () => _toggle(
              item.path,
              !_selected.contains(item.path),
            ),
            'review_needed' => () => _toggleReviewExpanded(item.path),
            _ => null,
          },
          expanded:
              item.verdict == 'review_needed' &&
              _expandedReviewPaths.contains(item.path),
          onDecisionChanged: item.verdict == 'review_needed'
              ? (decision) => _confirmReviewDecision(item.path, decision)
              : null,
          cleanupMeta: _cleanupMetaLabel(item),
          cleanupSource: _cleanupSourceLabel(item),
          retentionHint: _retentionHintLabel(item),
          reviewStatusLabel: _reviewStatusLabel(
            _reviewDecisions[item.path] ?? _ReviewDecision.pending,
          ),
        ),
      },
    );
  }

  Widget _buildResults() {
    if (_resultsLayoutPending && _verdicts.isEmpty) {
      final job = _coverageJobState;
      final loadingLabel =
          job != null &&
              job.status == CoverageJobStatus.running &&
              _useFullCoverage
          ? context.l10n.aiCoverageProgress(
              job.analyzedFiles,
              job.totalUnclassified,
            )
          : context.l10n.aiWorkspacePhaseReview;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppleSpacing.sm),
            Text(loadingLabel, style: context.vwCaption),
          ],
        ),
      );
    }
    final normalizedGroups = _normalizedResultGroups();
    final summary = _overallResultSummaryFor(normalizedGroups);
    final visibleGroups = _visibleResultGroups(normalizedGroups);
    final listLayout = _resultListLayoutFor(visibleGroups);
    final rowCount = listLayout.rowCount;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final horizontalPadding = wide ? AppleSpacing.lg : AppleSpacing.md;
        return Column(
          children: [
            if (_resultsLayoutPending)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: CustomScrollView(
                controller: _resultsScrollController,
                scrollCacheExtent: const ScrollCacheExtent.pixels(640),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppleSpacing.md,
                      horizontalPadding,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        key: AiAnalysisWorkspace.summaryKey,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_buildCoverageBanner() case final banner?) ...[
                            KeyedSubtree(
                              key: const Key('ai-analysis-coverage-progress'),
                              child: banner,
                            ),
                            const SizedBox(height: AppleSpacing.sm),
                          ],
                          Text(
                            context.l10n.aiResultsDecisionSummary(
                              _formatBytes(summary.safeBytes),
                              summary.reviewCount,
                            ),
                            key: AiAnalysisWorkspace.decisionSummaryKey,
                            style: context.vwBodyStrong,
                          ),
                          if (_shouldShowResultsLocalPreviewHint()) ...[
                            const SizedBox(height: AppleSpacing.xxs),
                            Text(
                              context.l10n.aiResultsLocalPreviewHint,
                              style: context.vwCaption,
                            ),
                          ],
                          if (normalizedGroups.isNotEmpty) ...[
                            const SizedBox(height: AppleSpacing.sm),
                            _buildResultsToolbar(wide: wide),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (rowCount == 0)
                    SliverFillRemaining(
                      child: _buildResultsEmptyState(
                        filtered: normalizedGroups.isNotEmpty,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      sliver: SliverList(
                        key: AiAnalysisWorkspace.resultsListKey,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final row = listLayout.rowAt(index);
                            if (row == null) return const SizedBox.shrink();
                            return _buildResultStreamRow(row);
                          },
                          childCount: rowCount,
                          addRepaintBoundaries: true,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _buildResultsActionBar(
              horizontalPadding: horizontalPadding,
              pendingReviewCount: summary.reviewCount,
            ),
          ],
        );
      },
    );
  }

  String? _coverageResultsEmptyJobHint(CoverageJobState? job) {
    if (job == null || job.snapshotId != widget.snapshotId) return null;
    final l10n = context.l10n;
    if (job.status == CoverageJobStatus.paused &&
        job.pauseReason == CoveragePauseReason.failed) {
      return coverageFailedReasonCategory(
        l10n,
        job.pauseDetail,
        pauseMessage: job.pauseMessage,
      );
    }
    if (job.status == CoverageJobStatus.running) {
      return l10n.aiCoverageProgress(job.analyzedFiles, job.totalUnclassified);
    }
    if (job.status == CoverageJobStatus.completed &&
        job.totalUnclassified == 0) {
      return '当前扫描快照里没有「未分类」文件，Full Coverage 没有可写入的结果。';
    }
    if (job.status == CoverageJobStatus.completed &&
        job.analyzedFiles == 0 &&
        job.totalUnclassified > 0) {
      return '分析已结束，但 verdict 文件为空。请 Restart full coverage；若仍失败，请确认已用最新 native 库重启应用。';
    }
    if (job.status == CoverageJobStatus.completed &&
        job.analyzedFiles < job.totalUnclassified) {
      return l10n.aiCoverageProgress(job.analyzedFiles, job.totalUnclassified);
    }
    return null;
  }

  Widget _buildResultsEmptyState({required bool filtered}) {
    final l10n = context.l10n;
    final job = _coverageJobState;
    final jobHint = _coverageResultsEmptyJobHint(job);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppleSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtered
                  ? Icons.search_off_rounded
                  : Icons.check_circle_outline_rounded,
              size: 28,
              color: context.volward.inkMuted48,
            ),
            const SizedBox(height: AppleSpacing.sm),
            Text(
              filtered ? l10n.aiResultsNoMatches : l10n.aiResultsEmpty,
              style: context.vwCaptionStrong,
            ),
            if (_error != null && _error!.trim().isNotEmpty) ...[
              const SizedBox(height: AppleSpacing.xs),
              Text(
                _error!,
                style: context.vwCaption.copyWith(
                  color: context.volward.danger,
                ),
                textAlign: TextAlign.center,
              ),
            ] else if (jobHint != null) ...[
              const SizedBox(height: AppleSpacing.xs),
              Text(
                jobHint,
                style: context.vwCaption,
                textAlign: TextAlign.center,
              ),
            ],
            if (filtered) ...[
              const SizedBox(height: AppleSpacing.xs),
              AppleButton(
                label: l10n.aiResultsResetFilters,
                icon: Icons.filter_alt_off_outlined,
                variant: AppleButtonVariant.pearl,
                onPressed: () => setState(() {
                  _resultsSearchController.clear();
                  _resultsQuery = '';
                  _resultFilterMode = _ResultFilterMode.all;
                  _invalidateVisibleGroups();
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultsToolbar({required bool wide}) {
    final tokens = context.volward;
    final searchField = DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfacePearl,
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        border: Border.all(color: tokens.hairline),
      ),
      child: TextField(
        controller: _resultsSearchController,
        onChanged: (value) => setState(() {
          _resultsQuery = value;
          _invalidateVisibleGroups();
        }),
        decoration: InputDecoration(
          isDense: true,
          hintText: context.l10n.aiResultsSearchHint,
          border: InputBorder.none,
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 18,
            color: tokens.inkMuted48,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppleSpacing.sm,
            vertical: AppleSpacing.sm,
          ),
          suffixIcon: _resultsQuery.isEmpty
              ? null
              : Tooltip(
                  message: context.l10n.aiResultsClearSearch,
                  child: IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () => setState(() {
                      _resultsSearchController.clear();
                      _resultsQuery = '';
                      _invalidateVisibleGroups();
                    }),
                  ),
                ),
        ),
      ),
    );
    final menus = Wrap(
      spacing: AppleSpacing.xs,
      runSpacing: AppleSpacing.xs,
      children: [
        IconButton(
          key: AiAnalysisWorkspace.searchToggleKey,
          tooltip: context.l10n.aiResultsSearchHint,
          icon: const Icon(Icons.search_rounded, size: 18),
          onPressed: () => setState(() {
            _resultsSearchExpanded = !_resultsSearchExpanded;
            if (!_resultsSearchExpanded) {
              _resultsSearchController.clear();
              _resultsQuery = '';
              _invalidateVisibleGroups();
            }
          }),
        ),
        _buildResultsMenuButton<_ResultFilterMode>(
          label: _resultFilterLabel(_resultFilterMode),
          initialValue: _resultFilterMode,
          onSelected: (value) => setState(() {
            _resultFilterMode = value;
            _invalidateVisibleGroups();
          }),
          items: _ResultFilterMode.values
              .map(
                (mode) => PopupMenuItem<_ResultFilterMode>(
                  value: mode,
                  child: Text(_resultFilterLabel(mode)),
                ),
              )
              .toList(),
        ),
        _buildResultsMenuButton<_ResultSortMode>(
          label: _resultSortLabel(_resultSortMode),
          initialValue: _resultSortMode,
          onSelected: (value) => setState(() {
            _resultSortMode = value;
            _invalidateVisibleGroups();
          }),
          items: _ResultSortMode.values
              .map(
                (mode) => PopupMenuItem<_ResultSortMode>(
                  value: mode,
                  child: Text(_resultSortLabel(mode)),
                ),
              )
              .toList(),
        ),
      ],
    );
    if (!_resultsSearchExpanded) return menus;
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          searchField,
          const SizedBox(height: AppleSpacing.xs),
          menus,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: searchField),
        const SizedBox(width: AppleSpacing.sm),
        menus,
      ],
    );
  }

  Widget _buildResultsMenuButton<T>({
    required String label,
    required T initialValue,
    required ValueChanged<T> onSelected,
    required List<PopupMenuEntry<T>> items,
  }) {
    final tokens = context.volward;
    return PopupMenuButton<T>(
      initialValue: initialValue,
      tooltip: null,
      onSelected: onSelected,
      color: tokens.canvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        side: BorderSide(color: tokens.hairline),
      ),
      itemBuilder: (context) => items,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfacePearl,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(color: tokens.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppleSpacing.sm,
            vertical: AppleSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: context.vwFinePrintInk),
              const SizedBox(width: AppleSpacing.xxs),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: tokens.inkMuted80,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _resultFilterLabel(_ResultFilterMode mode) {
    final l10n = context.l10n;
    return switch (mode) {
      _ResultFilterMode.all => l10n.aiResultsFilterAll,
      _ResultFilterMode.review => l10n.aiResultsFilterReview,
      _ResultFilterMode.selected => l10n.aiResultsFilterSelected,
    };
  }

  String _resultSortLabel(_ResultSortMode mode) {
    final l10n = context.l10n;
    return switch (mode) {
      _ResultSortMode.priority => l10n.aiResultsSortPriority,
      _ResultSortMode.size => l10n.aiResultsSortSize,
    };
  }

  Widget _buildResultsActionBar({
    required double horizontalPadding,
    required int pendingReviewCount,
  }) {
    final l10n = context.l10n;
    final tokens = context.volward;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(top: BorderSide(color: tokens.dividerSoft)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          AppleSpacing.sm,
          horizontalPadding,
          AppleSpacing.sm,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final deleteButton = AppleButton(
              key: AiAnalysisWorkspace.deleteKey,
              label: _deleting
                  ? l10n.deleteActionWorking
                  : l10n.aiDeleteSelected(_selected.length),
              icon: _deleting ? null : Icons.delete_outline,
              expanded: true,
              onPressed: _selected.isEmpty || _deleting
                  ? null
                  : _deleteSelected,
            );
            final body = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.aiResultsSelectedForCleanup(
                    _selected.length,
                    _formatBytes(_selectedBytes),
                  ),
                  key: AiAnalysisWorkspace.selectedSummaryKey,
                  style: context.vwCaptionStrong,
                ),
                const SizedBox(height: AppleSpacing.xxs),
                Text(
                  l10n.aiResultsPendingReviewExcluded(pendingReviewCount),
                  key: AiAnalysisWorkspace.pendingReviewKey,
                  style: context.vwFinePrint,
                ),
                if (_error != null && _partialDeleteFailedCount == null) ...[
                  const SizedBox(height: AppleSpacing.xxs),
                  Text(
                    _error!,
                    style: AppleTypography.caption.copyWith(
                      color: tokens.danger,
                    ),
                  ),
                ],
                if (_partialDeleteFailedCount != null &&
                    _partialDeleteFreedBytes != null) ...[
                  const SizedBox(height: AppleSpacing.xxs),
                  Text(
                    l10n.aiWorkspacePartialDelete(
                      _partialDeleteFailedCount!,
                      _formatBytes(_partialDeleteFreedBytes!),
                    ),
                    style: AppleTypography.caption.copyWith(
                      color: tokens.danger,
                    ),
                  ),
                ],
                if (_partialDeleteFailedCount != null) ...[
                  const SizedBox(height: AppleSpacing.xs),
                  Wrap(
                    spacing: AppleSpacing.xs,
                    runSpacing: AppleSpacing.xs,
                    children: [
                      AppleButton(
                        label: l10n.aiActionRetry,
                        icon: Icons.refresh_outlined,
                        variant: AppleButtonVariant.pearl,
                        onPressed: _deleting ? null : _deleteSelected,
                      ),
                      AppleButton(
                        label: l10n.aiWorkspaceReturn,
                        variant: AppleButtonVariant.pearl,
                        onPressed: _deleting ? null : widget.onExit,
                      ),
                    ],
                  ),
                ],
              ],
            );
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  body,
                  const SizedBox(height: AppleSpacing.sm),
                  deleteButton,
                ],
              );
            }
            final actions = ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
              child: deleteButton,
            );
            return Row(
              children: [
                Expanded(child: body),
                const SizedBox(width: AppleSpacing.md),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildError() {
    final l10n = context.l10n;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppleSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error ?? l10n.aiErrorUnknown,
              textAlign: TextAlign.center,
              style: AppleTypography.body.copyWith(
                color: context.volward.danger,
              ),
            ),
            const SizedBox(height: AppleSpacing.md),
            AppleButton(
              label: l10n.aiActionRetry,
              icon: Icons.refresh_outlined,
              onPressed: _bootstrap,
            ),
          ],
        ),
      ),
    );
  }

  String? _cleanupMetaLabel(AiVerdict item) {
    final parts = <String>[
      if (_cleanupSourceLabel(item) case final source?) source,
      if (_retentionHintLabel(item) case final retention?) retention,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? _cleanupSourceLabel(AiVerdict item) {
    final source = item.cleanupSource;
    if (source == null || source.isEmpty) return null;
    final l10n = context.l10n;
    return switch (source) {
      'ai_tool_cache' => l10n.aiCleanupSourceAiToolCache,
      'ai_generated_output' => l10n.aiCleanupSourceAiGeneratedOutput,
      'system_temp' => l10n.aiCleanupSourceSystemTemp,
      _ => source,
    };
  }

  String? _retentionHintLabel(AiVerdict item) {
    final parts = <String>[
      if (item.retentionDays != null)
        context.l10n.aiCleanupRetentionDays(item.retentionDays!),
      if (item.cleanupHint case final hint? when hint.isNotEmpty) hint,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

final class _ResultListLayout {
  _ResultListLayout({
    required this.groups,
    required this.prefixEnds,
    required this.expandedGroupPaths,
    required this.showsFilteredItems,
    required this.itemLimitFor,
  });

  final List<_VisibleResultGroup> groups;
  final List<int> prefixEnds;
  final Set<String> expandedGroupPaths;
  final bool showsFilteredItems;
  final int Function(String groupPath, int itemCount) itemLimitFor;

  int get rowCount => prefixEnds.isEmpty ? 0 : prefixEnds.last;

  static _ResultListLayout build({
    required List<_VisibleResultGroup> groups,
    required Set<String> expandedGroupPaths,
    required bool showsFilteredItems,
    required int Function(String groupPath, int itemCount) itemLimitFor,
  }) {
    final prefixEnds = <int>[0];
    for (final group in groups) {
      var span = 1;
      final showItems =
          expandedGroupPaths.contains(group.group.path) || showsFilteredItems;
      if (showItems) {
        final limit = itemLimitFor(group.group.path, group.items.length);
        span += limit;
        if (!showsFilteredItems && group.items.length > limit && limit > 0) {
          span += 1;
        }
      }
      prefixEnds.add(prefixEnds.last + span);
    }
    return _ResultListLayout(
      groups: groups,
      prefixEnds: prefixEnds,
      expandedGroupPaths: expandedGroupPaths,
      showsFilteredItems: showsFilteredItems,
      itemLimitFor: itemLimitFor,
    );
  }

  _ResultListRow? rowAt(int index) {
    if (index < 0 || index >= rowCount || groups.isEmpty) return null;
    var lo = 0;
    var hi = groups.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (prefixEnds[mid] <= index) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final group = groups[lo];
    final local = index - prefixEnds[lo];
    if (local == 0) {
      return _ResultListRow.group(group);
    }
    final showItems =
        expandedGroupPaths.contains(group.group.path) || showsFilteredItems;
    if (!showItems) return null;
    final limit = itemLimitFor(group.group.path, group.items.length);
    final itemIndex = local - 1;
    if (itemIndex < limit) {
      return _ResultListRow.item(group.group, group.items[itemIndex]);
    }
    if (itemIndex == limit &&
        !showsFilteredItems &&
        group.items.length > limit &&
        limit > 0) {
      return _ResultListRow.showMore(
        groupPath: group.group.path,
        shown: limit,
        total: group.items.length,
      );
    }
    return null;
  }
}

sealed class _ResultListRow {
  const _ResultListRow();

  factory _ResultListRow.group(_VisibleResultGroup group) = _ResultListGroupRow;

  factory _ResultListRow.item(AiResultGroup group, AiVerdict item) =
      _ResultListItemRow;

  factory _ResultListRow.showMore({
    required String groupPath,
    required int shown,
    required int total,
  }) = _ResultListShowMoreRow;

  Key get key;
}

final class _ResultListGroupRow extends _ResultListRow {
  const _ResultListGroupRow(this.visibleGroup);

  final _VisibleResultGroup visibleGroup;

  @override
  Key get key => ValueKey<String>('ai-result-group:${visibleGroup.group.path}');
}

final class _ResultListItemRow extends _ResultListRow {
  const _ResultListItemRow(this.group, this.item);

  final AiResultGroup group;
  final AiVerdict item;

  @override
  Key get key => ValueKey<String>('ai-result-item:${item.path}');
}

final class _ResultListShowMoreRow extends _ResultListRow {
  const _ResultListShowMoreRow({
    required this.groupPath,
    required this.shown,
    required this.total,
  });

  final String groupPath;
  final int shown;
  final int total;

  @override
  Key get key => ValueKey<String>('ai-result-show-more:$groupPath');
}

class _ResultGroupRow extends StatelessWidget {
  const _ResultGroupRow({
    super.key,
    required this.group,
    required this.expanded,
    required this.selectionValue,
    required this.onSelectionChanged,
    required this.onTap,
    required this.summaryLabel,
    required this.metadataLabels,
  });

  final AiResultGroup group;
  final bool expanded;
  final bool? selectionValue;
  final ValueChanged<bool?>? onSelectionChanged;
  final VoidCallback onTap;
  final String summaryLabel;
  final List<String> metadataLabels;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    final checkbox = Checkbox(
      key: Key('ai-group-toggle:${group.path}'),
      tristate: true,
      value: selectionValue,
      onChanged: onSelectionChanged,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: expanded ? tokens.surfacePearl : tokens.canvas,
        border: Border(bottom: BorderSide(color: tokens.dividerSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppleSpacing.sm,
              AppleSpacing.sm,
              AppleSpacing.xs,
              AppleSpacing.sm,
            ),
            child: SizedBox(
              width: 40,
              height: 40,
              child: FittedBox(fit: BoxFit.scaleDown, child: checkbox),
            ),
          ),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    0,
                    AppleSpacing.sm,
                    AppleSpacing.sm,
                    AppleSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedRotation(
                            turns: expanded ? 0.25 : 0,
                            duration: const Duration(milliseconds: 160),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: tokens.inkMuted80,
                            ),
                          ),
                          const SizedBox(width: AppleSpacing.xs),
                          Icon(
                            Icons.folder_outlined,
                            size: 18,
                            color: tokens.folderIcon,
                          ),
                          const SizedBox(width: AppleSpacing.xs),
                          Expanded(
                            child: _PathLabel(
                              group.path,
                              style: context.vwCaptionStrong,
                              maxLines: 2,
                            ),
                          ),
                          const SizedBox(width: AppleSpacing.sm),
                          Flexible(
                            child: Text(
                              summaryLabel,
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.vwFinePrintInk,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppleSpacing.xxs),
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 18 + AppleSpacing.xs,
                        ),
                        child: Wrap(
                          spacing: AppleSpacing.sm,
                          runSpacing: AppleSpacing.xxs,
                          children: [
                            for (
                              var index = 0;
                              index < metadataLabels.length;
                              index++
                            )
                              Text(
                                metadataLabels[index],
                                style: context.vwFinePrint.copyWith(
                                  color: switch (index) {
                                    0 => tokens.primary,
                                    1 => tokens.warning,
                                    _ => null,
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    super.key,
    required this.item,
    required this.sizeLabel,
    required this.selected,
    required this.reviewDecision,
    required this.onChanged,
    required this.onTap,
    required this.expanded,
    required this.onDecisionChanged,
    required this.cleanupMeta,
    required this.cleanupSource,
    required this.retentionHint,
    required this.reviewStatusLabel,
  });

  final AiVerdict item;
  final String sizeLabel;
  final bool selected;
  final _ReviewDecision reviewDecision;
  final ValueChanged<bool?>? onChanged;
  final VoidCallback? onTap;
  final bool expanded;
  final ValueChanged<_ReviewDecision>? onDecisionChanged;
  final String? cleanupMeta;
  final String? cleanupSource;
  final String? retentionHint;
  final String reviewStatusLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    final isSafe = item.verdict == 'safe_to_remove';
    final isReview = item.verdict == 'review_needed';
    final isUnanalyzed = item.verdict == 'unanalyzed';
    final subtitle = switch (item.verdict) {
      'safe_to_remove' => [
        item.confidence,
        if (item.reason.isNotEmpty) item.reason,
        if (cleanupMeta != null && cleanupMeta!.isNotEmpty) cleanupMeta!,
      ].join(' · '),
      'review_needed' => reviewStatusLabel,
      'unanalyzed' => item.reason,
      _ => [
        context.l10n.aiResultsMetricProtected,
        item.confidence,
        if (item.reason.isNotEmpty) item.reason,
        if (cleanupMeta != null && cleanupMeta!.isNotEmpty) cleanupMeta!,
      ].join(' · '),
    };
    final leading = switch (item.verdict) {
      'safe_to_remove' => Checkbox(
        key: Key('ai-item-toggle:${item.path}'),
        value: selected,
        onChanged: onChanged,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      'review_needed' => Icon(
        Icons.pending_actions_outlined,
        size: 18,
        color: tokens.warning,
      ),
      'unanalyzed' => Icon(
        Icons.hourglass_empty_outlined,
        size: 18,
        color: tokens.inkMuted48,
      ),
      _ => Icon(Icons.lock_outline, size: 18, color: tokens.inkMuted48),
    };
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PathLabel(item.path, style: context.vwCaptionStrong, maxLines: 2),
        const SizedBox(height: AppleSpacing.xxs),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.vwFinePrint.copyWith(
            color: isReview
                ? tokens.warning
                : isUnanalyzed
                ? tokens.inkMuted80
                : null,
          ),
        ),
      ],
    );
    final sizeText = Text(
      sizeLabel,
      textAlign: TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.vwCaptionStrong,
    );
    final reviewDisclosure = isReview
        ? AnimatedRotation(
            turns: expanded ? 0.25 : 0,
            duration: const Duration(milliseconds: 160),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: tokens.warning,
            ),
          )
        : null;
    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppleSpacing.sm,
        vertical: AppleSpacing.xs,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 40, child: leading),
                    const SizedBox(width: AppleSpacing.xs),
                    Expanded(child: titleBlock),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 40 + AppleSpacing.xs,
                    top: AppleSpacing.xxs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      sizeText,
                      if (reviewDisclosure != null) reviewDisclosure,
                    ],
                  ),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 40, child: leading),
              const SizedBox(width: AppleSpacing.xs),
              Expanded(child: titleBlock),
              const SizedBox(width: AppleSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: reviewDisclosure == null ? 88 : 110,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      sizeText,
                      if (reviewDisclosure != null) reviewDisclosure,
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    final rowBody = onTap == null
        ? body
        : Semantics(
            expanded: isReview ? expanded : null,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: body,
              ),
            ),
          );
    final showsDetails = expanded && isReview && onDecisionChanged != null;
    final row = DecoratedBox(
      decoration: BoxDecoration(
        color: isSafe && selected ? tokens.canvasParchment : tokens.canvas,
        border: Border(bottom: BorderSide(color: tokens.dividerSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: AppleSpacing.lg),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                rowBody,
                if (showsDetails)
                  Padding(
                    key: Key('ai-review-detail:${item.path}'),
                    padding: const EdgeInsets.fromLTRB(
                      AppleSpacing.sm + 40 + AppleSpacing.xs,
                      0,
                      AppleSpacing.sm,
                      AppleSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ResultDetailLine(
                          label: context.l10n.aiResultsDetailSize,
                          value: sizeLabel,
                        ),
                        _ResultDetailLine(
                          label: context.l10n.aiResultsDetailConfidence,
                          value: item.confidence,
                        ),
                        if (item.reason.isNotEmpty)
                          _ResultDetailLine(
                            label: context.l10n.aiResultsDetailReason,
                            value: item.reason,
                          ),
                        if (cleanupSource != null && cleanupSource!.isNotEmpty)
                          _ResultDetailLine(
                            label: context.l10n.aiResultsDetailCleanupSource,
                            value: cleanupSource!,
                          ),
                        if (retentionHint != null && retentionHint!.isNotEmpty)
                          _ResultDetailLine(
                            label: context.l10n.aiResultsDetailRetentionHint,
                            value: retentionHint!,
                          ),
                        const SizedBox(height: AppleSpacing.xs),
                        _ReviewDecisionButtons(
                          path: item.path,
                          decision: reviewDecision,
                          onChanged: onDecisionChanged!,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return row;
  }
}

class _ReviewDecisionButtons extends StatelessWidget {
  const _ReviewDecisionButtons({
    required this.path,
    required this.decision,
    required this.onChanged,
  });

  final String path;
  final _ReviewDecision decision;
  final ValueChanged<_ReviewDecision> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppleSpacing.xs,
      runSpacing: AppleSpacing.xs,
      children: [
        AppleButton(
          key: Key('ai-review-include:$path'),
          label: context.l10n.aiResultsAddToCleanup,
          icon: Icons.add_task_outlined,
          onPressed: decision == _ReviewDecision.include
              ? null
              : () => onChanged(_ReviewDecision.include),
        ),
        AppleButton(
          key: Key('ai-review-keep:$path'),
          label: context.l10n.aiResultsKeepItem,
          icon: Icons.lock_outline,
          variant: AppleButtonVariant.pearl,
          onPressed: decision == _ReviewDecision.keep
              ? null
              : () => onChanged(_ReviewDecision.keep),
        ),
      ],
    );
  }
}

class _ResultDetailLine extends StatelessWidget {
  const _ResultDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppleSpacing.xxs),
      child: Text('$label: $value', softWrap: true, style: context.vwFinePrint),
    );
  }
}

class _VisibleResultGroup {
  const _VisibleResultGroup({
    required this.group,
    required this.items,
    required this.totalBytes,
  });

  final AiResultGroup group;
  final List<AiVerdict> items;
  final int totalBytes;
}

class _OverallResultSummaryData {
  const _OverallResultSummaryData({
    required this.safeBytes,
    required this.reviewCount,
  });

  final int safeBytes;
  final int reviewCount;
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.phaseLabel,
    required this.phaseStep,
    required this.onBack,
  });

  final String phaseLabel;
  final int phaseStep;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.volward;
    final phaseSemantics = '$phaseLabel, step $phaseStep of 5';
    final phaseIndicator = Semantics(
      value: phaseSemantics,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var step = 1; step <= 5; step++) ...[
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: step <= phaseStep
                      ? tokens.primary
                      : tokens.inkMuted48.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
              ),
              if (step < 5) const SizedBox(width: AppleSpacing.xxs),
            ],
          ],
        ),
      ),
    );
    final title = Text(
      l10n.aiWorkspaceTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.vwBodyStrong.copyWith(fontSize: 15, height: 1.12),
    );
    return DecoratedBox(
      key: AiAnalysisWorkspace.headerKey,
      decoration: BoxDecoration(color: tokens.canvas),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppleSpacing.md,
            vertical: AppleSpacing.xs,
          ),
          child: Row(
            children: [
              AppleButton(
                key: AiAnalysisWorkspace.backKey,
                label: l10n.aiWorkspaceBack,
                icon: Icons.arrow_back,
                variant: AppleButtonVariant.pearl,
                onPressed: onBack,
              ),
              const SizedBox(width: AppleSpacing.xs),
              Expanded(child: title),
              const SizedBox(width: AppleSpacing.sm),
              phaseIndicator,
            ],
          ),
        ),
      ),
    );
  }
}

class _PathLabel extends StatelessWidget {
  const _PathLabel(this.path, {this.style, this.maxLines = 2});

  final String path;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      value: path,
      child: Text(
        path,
        maxLines: maxLines,
        softWrap: true,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}
