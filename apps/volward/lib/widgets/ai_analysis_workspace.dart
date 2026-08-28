import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ai/ai_analysis_gateway.dart';
import '../ai/ai_provider.dart';
import '../ai/ai_settings_store.dart';
import '../ai/byok_ai_provider.dart';
import '../ai/platform_ai_provider.dart';
import '../analytics/analytics.dart';
import '../analytics/analytics_events.dart';
import '../ai/ai_result_groups.dart';
import '../l10n/l10n.dart';
import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';
import 'apple_widgets.dart';

class _AiCandidatesBootstrap {
  const _AiCandidatesBootstrap({
    required this.preClassified,
    required this.unknown,
    required this.sizeByPath,
    required this.deleteTargetsByPath,
    required this.estimatedTokens,
    required this.hasExistingResult,
    required this.truncated,
    required this.candidatesBeforeCap,
    required this.selected,
    required this.resultCacheKey,
    required this.rootPath,
  });

  final List<Map<String, dynamic>> preClassified;
  final List<AiCandidate> unknown;
  final Map<String, int> sizeByPath;
  final Map<String, String> deleteTargetsByPath;
  final int estimatedTokens;
  final bool hasExistingResult;
  final bool truncated;
  final int candidatesBeforeCap;
  final Set<String> selected;
  final String resultCacheKey;
  final String rootPath;
}

enum _ReviewDecision { pending, include, keep }

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

_AiCandidatesBootstrap _parseAiCandidatesPayload(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('ai candidates payload is not an object');
  }
  final map = Map<String, dynamic>.from(decoded);
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

  final selected = <String>{};
  for (final entry in preClassified) {
    if (entry['confidence'] == 'high' && entry['deletable'] == true) {
      final path = entry['path'] as String?;
      if (path != null) selected.add(path);
    }
  }

  return _AiCandidatesBootstrap(
    preClassified: preClassified,
    unknown: unknown,
    sizeByPath: sizeByPath,
    deleteTargetsByPath: deleteTargetsByPath,
    estimatedTokens: _asInt(map['estimated_input_tokens']),
    hasExistingResult: map['has_existing_result'] == true,
    truncated: map['truncated'] == true,
    candidatesBeforeCap: _asInt(map['candidates_total_before_cap']),
    selected: selected,
    resultCacheKey: map['result_cache_key']?.toString() ?? '',
    rootPath: map['root_path']?.toString() ?? '',
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
  });

  static const workspaceKey = Key('ai-analysis-workspace');
  static const backKey = Key('ai-analysis-back');
  static const loadPreviousKey = Key('ai-analysis-load-previous');
  static const analyzeAgainKey = Key('ai-analysis-analyze-again');
  static const settingsKey = Key('ai-analysis-open-settings');
  static const resultsListKey = Key('ai-analysis-results-list');
  static const summaryKey = Key('ai-analysis-summary');
  static const deleteKey = Key('ai-analysis-delete');
  static const headerKey = Key('ai-analysis-header');

  final String snapshotId;
  final String targetLabel;
  final VoidCallback onExit;
  final VoidCallback onOpenSettings;
  final ValueChanged<bool> onDeletingChanged;
  final VoidCallback onDeleteCompleted;
  final AiAnalysisGateway gateway;

  @override
  State<AiAnalysisWorkspace> createState() => _AiAnalysisWorkspaceState();
}

class _AiAnalysisWorkspaceState extends State<AiAnalysisWorkspace> {
  _Phase _phase = _Phase.loading;
  String? _error;
  List<Map<String, dynamic>> _preClassified = [];
  List<AiCandidate> _unknown = [];
  int _estimatedTokens = 0;
  bool _hasExistingResult = false;
  bool _truncated = false;
  int _candidatesBeforeCap = 0;
  String _resultCacheKey = '';
  String _rootPath = '';
  List<AiVerdict> _verdicts = [];
  final Set<String> _selected = {};
  final Map<String, _ReviewDecision> _reviewDecisions = {};
  final Set<String> _expandedGroupPaths = {};
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
  double _headerCollapseProgress = 0;

  int _beginOperation() => ++_operationGeneration;
  bool _isCurrent(int generation) =>
      mounted && generation == _operationGeneration;

  AiVerdict _withCandidateMeta(AiVerdict verdict) {
    AiCandidate? candidate;
    for (final item in _unknown) {
      if (item.path == verdict.path) {
        candidate = item;
        break;
      }
    }
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
    _resultsScrollController.addListener(_updateHeaderCollapseProgress);
    _bootstrap();
  }

  @override
  void dispose() {
    _operationGeneration++;
    _resultsScrollController
      ..removeListener(_updateHeaderCollapseProgress)
      ..dispose();
    super.dispose();
  }

  void _updateHeaderCollapseProgress() {
    if (!_resultsScrollController.hasClients) return;
    final nextProgress = (_resultsScrollController.offset / 64)
        .clamp(0.0, 1.0)
        .toDouble();
    if ((nextProgress - _headerCollapseProgress).abs() < 0.01) return;
    setState(() => _headerCollapseProgress = nextProgress);
  }

  void _resetResultsScroll() {
    if (_resultsScrollController.hasClients) {
      _resultsScrollController.jumpTo(0);
    }
    _headerCollapseProgress = 0;
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
      _phase = _Phase.loading;
      _error = null;
      _sizeByPath.clear();
      _deleteTargetsByPath.clear();
      _selected.clear();
      _reviewDecisions.clear();
      _expandedGroupPaths.clear();
      _expandedReviewPaths.clear();
      _preClassified = [];
      _unknown = [];
      _verdicts = [];
      _analyzing = false;
      _deleting = false;
      _estimatedTokens = 0;
      _hasExistingResult = false;
      _truncated = false;
      _candidatesBeforeCap = 0;
      _resultCacheKey = '';
      _rootPath = '';
      _partialDeleteFailedCount = null;
      _partialDeleteFreedBytes = null;
      _retryTargets = [];
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

      final parsed = await compute(_parseAiCandidatesPayload, raw);
      if (!_isCurrent(generation)) return;
      setState(() {
        _mode = mode;
        _platformCredits = platformCredits;
        _hasProvider = provider != null;
        _preClassified = parsed.preClassified;
        _unknown = parsed.unknown;
        _sizeByPath
          ..clear()
          ..addAll(parsed.sizeByPath);
        _deleteTargetsByPath
          ..clear()
          ..addAll(parsed.deleteTargetsByPath);
        _estimatedTokens = parsed.estimatedTokens;
        _hasExistingResult = parsed.hasExistingResult;
        _truncated = parsed.truncated;
        _candidatesBeforeCap = parsed.candidatesBeforeCap;
        _resultCacheKey = parsed.resultCacheKey;
        _rootPath = parsed.rootPath;
        _selected
          ..clear()
          ..addAll(parsed.selected);
        _phase = _Phase.precheck;
      });
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

  Future<bool> _loadPreviousResult() async {
    final generation = _beginOperation();
    final l10n = context.l10n;
    final key = _resultCacheKey.isNotEmpty
        ? _resultCacheKey
        : widget.snapshotId;
    var raw = widget.gateway.loadResult(key);
    if ((raw == null || raw.isEmpty || raw.startsWith('error:')) &&
        key != widget.snapshotId) {
      raw = widget.gateway.loadResult(widget.snapshotId);
    }
    return _applyLoadedResult(raw, l10n.aiLoadPreviousFailed, generation);
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
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('expected object');
      final map = Map<String, dynamic>.from(decoded);
      final entriesRaw = map['entries'];
      if (entriesRaw is! List) throw const FormatException('missing entries');
      final verdicts = <AiVerdict>[];
      final resultSizes = <String, int>{};
      for (final rawEntry in entriesRaw) {
        if (rawEntry is! Map) continue;
        final entry = Map<String, dynamic>.from(rawEntry);
        final path = entry['path'] as String?;
        if (path == null || path.isEmpty) continue;
        resultSizes[path] = _asInt(entry['size_bytes']);
        verdicts.add(
          _withCandidateMeta(
            AiVerdict(
              path: path,
              verdict: entry['verdict']?.toString() ?? '',
              confidence: entry['confidence']?.toString() ?? '',
              reason: entry['reason']?.toString() ?? '',
              cleanupSource: entry['cleanup_source'] as String?,
              cleanupHint: entry['cleanup_hint'] as String?,
              retentionDays: entry['retention_days'] as int?,
            ),
          ),
        );
      }
      if (!_isCurrent(generation)) return false;
      setState(() {
        _selected.clear();
        _reviewDecisions.clear();
        _expandedGroupPaths.clear();
        _expandedReviewPaths.clear();
        _sizeByPath.addAll(resultSizes);
        _verdicts = verdicts;
        for (final verdict in verdicts) {
          if (verdict.verdict == 'safe_to_remove') {
            _selected.add(verdict.path);
          }
        }
        for (final verdict in verdicts) {
          if (verdict.verdict == 'review_needed') {
            _reviewDecisions[verdict.path] = _ReviewDecision.pending;
          }
        }
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
      _selected.clear();
      _reviewDecisions.clear();
      _expandedGroupPaths.clear();
      _expandedReviewPaths.clear();
    });
    final mode = await widget.gateway.getMode();
    if (!_isCurrent(generation)) return;
    final providerLabel = mode == AiMode.platform ? 'platform' : 'byok';
    final stopwatch = Stopwatch()..start();
    var byokUsageRecorded = false;
    unawaited(
      Analytics.instance.track(AnalyticsEvents.aiAnalysisStarted, {
        'provider': providerLabel,
        'candidate_count': _unknown.length,
      }),
    );
    try {
      final verdicts = await provider.analyze(_unknown);
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
        _verdicts = enrichedVerdicts;
        _selected
          ..clear()
          ..addAll(
            enrichedVerdicts
                .where((verdict) => verdict.verdict == 'safe_to_remove')
                .map((verdict) => verdict.path),
          );
        _reviewDecisions
          ..clear()
          ..addEntries(
            enrichedVerdicts
                .where((verdict) => verdict.verdict == 'review_needed')
                .map(
                  (verdict) => MapEntry(verdict.path, _ReviewDecision.pending),
                ),
          );
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
          _phase = _Phase.results;
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
    } catch (error) {
      if (!_isCurrent(generation)) return;
      setState(() {
        _phase = _Phase.results;
        _error = l10n.deleteFailed(error.toString());
      });
    } finally {
      if (_isCurrent(generation)) {
        setState(() {
          _deleting = false;
          _phase = _Phase.results;
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
    });
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
    final headerCollapseProgress =
        _phase == _Phase.results || _phase == _Phase.deleting
        ? _headerCollapseProgress
        : 0.0;
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
            targetLabel: widget.targetLabel,
            phaseLabel: _phaseLabel(context),
            phaseStep: _phaseStep,
            collapseProgress: headerCollapseProgress,
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
      _Phase.analyzing => _buildProgressBody(
        label: context.l10n.aiWorkspacePhaseAnalyzing,
        candidateCount: _unknown.length,
      ),
      _Phase.results || _Phase.deleting => _buildResults(),
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
        _hasProvider && !(_mode == AiMode.platform && _platformCredits == 0);
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
        Text(
          l10n.aiPreCheckSafeTitle(_preClassified.length),
          style: context.vwBodyStrong,
        ),
        const SizedBox(height: AppleSpacing.xs),
        Text(
          l10n.aiPreCheckUnknownTitle(_unknown.length, _estimatedTokens),
          style: context.vwCaption,
        ),
        if (_truncated) ...[
          const SizedBox(height: AppleSpacing.xs),
          Text(
            l10n.aiTruncatedNotice(_unknown.length, _candidatesBeforeCap),
            style: AppleTypography.caption.copyWith(color: tokens.warning),
          ),
        ],
        if (_mode == AiMode.platform && _platformCredits != null) ...[
          const SizedBox(height: AppleSpacing.xs),
          Text(
            l10n.aiPrecheckCreditsCost(_platformCredits!),
            style: context.vwCaption,
          ),
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
            l10n.aiPreCheckSafeSelectable(_preClassified.length),
            style: context.vwCaptionStrong,
          ),
          const SizedBox(height: AppleSpacing.xs),
          ..._preClassified.map(_preClassifiedTile),
        ],
        const SizedBox(height: AppleSpacing.lg),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_hasExistingResult) ...[
              AppleButton(
                key: AiAnalysisWorkspace.loadPreviousKey,
                label: l10n.aiWorkspaceLoadPrevious,
                variant: AppleButtonVariant.pearl,
                expanded: true,
                onPressed: _loadPreviousResult,
              ),
              const SizedBox(height: AppleSpacing.xs),
            ],
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
    ];
    return groupAiResults(merged, _sizeByPath);
  }

  _ResultSummaryData _resultSummaryFor({
    required List<AiVerdict> safe,
    required List<AiVerdict> review,
    required List<AiVerdict> keep,
  }) {
    int bytesFor(Iterable<AiVerdict> items) {
      return items.fold<int>(
        0,
        (total, item) => total + (_sizeByPath[item.path] ?? 0),
      );
    }

    final l10n = context.l10n;
    final selectedSafeCount = safe
        .where((item) => _selected.contains(item.path))
        .length;
    return _ResultSummaryData(
      safe: _ResultBucketData(
        title: l10n.aiResultsMetricSafeTitle,
        count: safe.length,
        detail: l10n.aiResultsMetricTotalSize(_formatBytes(bytesFor(safe))),
      ),
      review: _ResultBucketData(
        title: l10n.aiResultsMetricReviewTitle,
        count: review.length,
        detail: l10n.aiResultsMetricTotalSize(_formatBytes(bytesFor(review))),
      ),
      keep: _ResultBucketData(
        title: l10n.aiResultsMetricKeepTitle,
        count: keep.length,
        detail: l10n.aiResultsMetricProtected,
      ),
      selectedSafeCount: selectedSafeCount,
      selectedBytes: _selectedBytes,
    );
  }

  List<_ResultListRow> _resultRows(List<AiResultGroup> groups) {
    final rows = <_ResultListRow>[];
    for (final group in groups) {
      rows.add(_ResultListRow.group(group));
      if (_expandedGroupPaths.contains(group.path)) {
        for (final item in group.items) {
          rows.add(_ResultListRow.item(group, item));
        }
      }
    }
    return rows;
  }

  void _toggleGroupExpanded(String path) {
    setState(() {
      if (!_expandedGroupPaths.add(path)) {
        _expandedGroupPaths.remove(path);
      }
    });
  }

  void _toggleReviewExpanded(String path) {
    setState(() {
      if (!_expandedReviewPaths.add(path)) {
        _expandedReviewPaths.remove(path);
      }
    });
  }

  bool? _safeGroupSelectionValue(AiResultGroup group) {
    if (group.safeCount == 0) return false;
    final selectedSafeCount = group.items
        .where((item) => item.verdict == 'safe_to_remove')
        .where((item) => _selected.contains(item.path))
        .length;
    if (selectedSafeCount == 0) return false;
    if (selectedSafeCount == group.safeCount) return true;
    return null;
  }

  String _formatCount(int count) {
    return NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(count);
  }

  String _itemCountLabel(int count) {
    final formatted = _formatCount(count);
    return count == 1 ? '$formatted item' : '$formatted items';
  }

  String _groupSummaryLabel(AiResultGroup group) {
    return '${_itemCountLabel(group.items.length)} · ${_formatBytes(group.totalBytes)}';
  }

  String _groupMetadataLabel(AiResultGroup group) {
    return [
      '${context.l10n.aiResultsStatusSafe} ${_formatCount(group.safeCount)}',
      '${context.l10n.aiResultsStatusReview} ${_formatCount(group.reviewCount)}',
      '${context.l10n.aiResultsStatusKeep} ${_formatCount(group.keepCount)}',
    ].join(' · ');
  }

  String _reviewStatusLabel(_ReviewDecision decision) {
    return switch (decision) {
      _ReviewDecision.pending => 'Needs your decision',
      _ReviewDecision.include => 'Added to cleanup',
      _ReviewDecision.keep => 'Kept out of cleanup',
    };
  }

  Widget _buildWideResultsHeader(_ResultSummaryData summary) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildResultsOverview(summary: summary)),
        const SizedBox(width: AppleSpacing.lg),
        SizedBox(
          key: AiAnalysisWorkspace.summaryKey,
          width: 260,
          child: _buildSelectionSummary(),
        ),
      ],
    );
  }

  Widget _buildWideRowShell({required Widget child, required bool first}) {
    return Padding(
      padding: EdgeInsets.only(top: first ? AppleSpacing.lg : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: child),
          const SizedBox(width: AppleSpacing.lg),
          const SizedBox(width: 260),
        ],
      ),
    );
  }

  Widget _buildResultStreamRow(_ResultListRow row) {
    return switch (row) {
      _ResultListGroupRow(:final group) => _ResultGroupRow(
        key: row.key,
        group: group,
        expanded: _expandedGroupPaths.contains(group.path),
        selectionValue: _safeGroupSelectionValue(group),
        onSelectionChanged: group.safeCount == 0
            ? null
            : (value) => _toggleSafeGroup(group.items, value == true),
        onTap: () => _toggleGroupExpanded(group.path),
        summaryLabel: _groupSummaryLabel(group),
        metadataLabel: _groupMetadataLabel(group),
      ),
      _ResultListItemRow(:final item) => _ResultRow(
        key: row.key,
        item: item,
        sizeLabel: _formatBytes(_sizeByPath[item.path] ?? 0),
        selected: _selected.contains(item.path),
        reviewDecision: _reviewDecisions[item.path] ?? _ReviewDecision.pending,
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
    };
  }

  Widget _buildResults() {
    final normalizedGroups = _normalizedResultGroups();
    final safe = normalizedGroups
        .expand((group) => group.items)
        .where((item) => item.verdict == 'safe_to_remove')
        .toList(growable: false);
    final review = normalizedGroups
        .expand((group) => group.items)
        .where((item) => item.verdict == 'review_needed')
        .toList(growable: false);
    final keep = normalizedGroups
        .expand((group) => group.items)
        .where((item) => item.verdict == 'keep')
        .toList(growable: false);
    final summary = _resultSummaryFor(safe: safe, review: review, keep: keep);
    final rows = _resultRows(normalizedGroups);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        if (constraints.maxWidth >= 720) {
          return ListView.builder(
            key: AiAnalysisWorkspace.resultsListKey,
            controller: _resultsScrollController,
            padding: const EdgeInsets.all(AppleSpacing.lg),
            itemCount: rows.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildWideResultsHeader(summary);
              }
              return _buildWideRowShell(
                first: index == 1,
                child: _buildResultStreamRow(rows[index - 1]),
              );
            },
          );
        }
        return ListView.builder(
          key: AiAnalysisWorkspace.resultsListKey,
          controller: _resultsScrollController,
          padding: EdgeInsets.zero,
          itemCount: rows.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return SizedBox(
                key: AiAnalysisWorkspace.summaryKey,
                width: double.infinity,
                child: _buildSelectionSummary(compact: true),
              );
            }
            if (index == 1) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppleSpacing.lg,
                      AppleSpacing.lg,
                      AppleSpacing.lg,
                      AppleSpacing.lg,
                    ),
                    child: _buildResultsOverview(summary: summary),
                  ),
                ],
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppleSpacing.lg),
              child: _buildResultStreamRow(rows[index - 2]),
            );
          },
        );
      },
    );
  }

  Widget _buildResultsOverview({required _ResultSummaryData summary}) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.aiResultsSummaryEyebrow, style: context.vwFinePrintInk),
        const SizedBox(height: AppleSpacing.xs),
        Text(
          l10n.aiResultsSelectedForCleanup(_formatBytes(summary.selectedBytes)),
          style: context.vwBodyStrong.copyWith(fontSize: 26, height: 1.18),
        ),
        const SizedBox(height: AppleSpacing.xs),
        Text(
          l10n.aiResultsSelectedReviewBody(
            summary.selectedSafeCount,
            summary.review.count,
          ),
          style: context.vwCaption,
        ),
        const SizedBox(height: AppleSpacing.md),
        _ResultMetricCards(
          buckets: [summary.safe, summary.review, summary.keep],
        ),
      ],
    );
  }

  Widget _buildSelectionSummary({bool compact = false}) {
    final l10n = context.l10n;
    final tokens = context.volward;
    return Padding(
      padding: EdgeInsets.all(compact ? AppleSpacing.sm : AppleSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.aiResultsSelectedLabel, style: context.vwFinePrintInk),
          const SizedBox(height: AppleSpacing.xxs),
          Text(
            l10n.aiResultsSelectedCount(_selected.length),
            style: context.vwBodyStrong.copyWith(fontSize: compact ? 18 : 22),
          ),
          const SizedBox(height: AppleSpacing.xxs),
          Text(_formatBytes(_selectedBytes), style: context.vwCaption),
          const SizedBox(height: AppleSpacing.md),
          Divider(height: 1, color: tokens.dividerSoft),
          const SizedBox(height: AppleSpacing.md),
          Text(
            l10n.aiResultsDeleteGuidanceTitle,
            style: context.vwCaptionStrong,
          ),
          const SizedBox(height: AppleSpacing.xs),
          Text(l10n.aiResultsDeleteGuidanceBody, style: context.vwCaption),
          if (_error != null && _partialDeleteFailedCount == null) ...[
            const SizedBox(height: AppleSpacing.xs),
            Text(
              _error!,
              style: AppleTypography.caption.copyWith(color: tokens.danger),
            ),
          ],
          if (_partialDeleteFailedCount != null &&
              _partialDeleteFreedBytes != null) ...[
            const SizedBox(height: AppleSpacing.xs),
            Text(
              l10n.aiWorkspacePartialDelete(
                _partialDeleteFailedCount!,
                _formatBytes(_partialDeleteFreedBytes!),
              ),
              style: AppleTypography.caption.copyWith(color: tokens.danger),
            ),
          ],
          if (_partialDeleteFailedCount != null) ...[
            const SizedBox(height: AppleSpacing.xs),
            AppleButton(
              label: l10n.aiActionRetry,
              icon: Icons.refresh_outlined,
              variant: AppleButtonVariant.pearl,
              expanded: true,
              onPressed: _deleting ? null : _deleteSelected,
            ),
            const SizedBox(height: AppleSpacing.xs),
            AppleButton(
              label: l10n.aiWorkspaceReturn,
              variant: AppleButtonVariant.pearl,
              expanded: true,
              onPressed: _deleting ? null : widget.onExit,
            ),
          ],
          const SizedBox(height: AppleSpacing.md),
          AppleButton(
            key: AiAnalysisWorkspace.deleteKey,
            label: _deleting
                ? l10n.deleteActionWorking
                : l10n.aiDeleteSelected(_selected.length),
            icon: _deleting ? null : Icons.delete_outline,
            expanded: true,
            onPressed: _selected.isEmpty || _deleting ? null : _deleteSelected,
          ),
        ],
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

sealed class _ResultListRow {
  const _ResultListRow();

  factory _ResultListRow.group(AiResultGroup group) = _ResultListGroupRow;

  factory _ResultListRow.item(AiResultGroup group, AiVerdict item) =
      _ResultListItemRow;

  Key get key;
}

final class _ResultListGroupRow extends _ResultListRow {
  const _ResultListGroupRow(this.group);

  final AiResultGroup group;

  @override
  Key get key => ValueKey<String>('ai-result-group:${group.path}');
}

final class _ResultListItemRow extends _ResultListRow {
  const _ResultListItemRow(this.group, this.item);

  final AiResultGroup group;
  final AiVerdict item;

  @override
  Key get key => ValueKey<String>('ai-result-item:${item.path}');
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
    required this.metadataLabel,
  });

  final AiResultGroup group;
  final bool expanded;
  final bool? selectionValue;
  final ValueChanged<bool?>? onSelectionChanged;
  final VoidCallback onTap;
  final String summaryLabel;
  final String metadataLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.canvas,
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
              width: 28,
              child: Checkbox(
                key: Key('ai-group-toggle:${group.path}'),
                tristate: true,
                value: selectionValue,
                onChanged: onSelectionChanged,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
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
                          Expanded(
                            child: _PathLabel(
                              group.path,
                              style: context.vwCaptionStrong,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppleSpacing.xxs),
                      Text(
                        summaryLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.vwCaption,
                      ),
                      const SizedBox(height: AppleSpacing.xxs),
                      Text(
                        metadataLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.vwFinePrint,
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
    final subtitle = switch (item.verdict) {
      'safe_to_remove' => [
        selected ? 'Selected' : 'Not selected',
        item.confidence,
        if (item.reason.isNotEmpty) item.reason,
        if (cleanupMeta != null && cleanupMeta!.isNotEmpty) cleanupMeta!,
      ].join(' · '),
      'review_needed' => reviewStatusLabel,
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
      _ => Icon(Icons.lock_outline, size: 18, color: tokens.inkMuted48),
    };
    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppleSpacing.sm,
        vertical: AppleSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 28, child: leading),
          const SizedBox(width: AppleSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _PathLabel(item.path, style: context.vwCaptionStrong),
                const SizedBox(height: AppleSpacing.xxs),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.vwFinePrint.copyWith(
                    color: isReview ? tokens.warning : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppleSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(
              width: 88,
              child: Text(
                sizeLabel,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.vwCaptionStrong,
              ),
            ),
          ),
        ],
      ),
    );
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
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: body),
            ),
          ),
        ],
      ),
    );
    if (!expanded || !isReview || onDecisionChanged == null) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.canvas,
            border: Border(bottom: BorderSide(color: tokens.dividerSoft)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppleSpacing.xl + 28,
              0,
              AppleSpacing.lg,
              AppleSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.path, style: context.vwFinePrint),
                const SizedBox(height: AppleSpacing.xs),
                _ResultDetailLine(label: 'Size', value: sizeLabel),
                _ResultDetailLine(label: 'Confidence', value: item.confidence),
                if (item.reason.isNotEmpty)
                  _ResultDetailLine(label: 'Reason', value: item.reason),
                if (cleanupSource != null && cleanupSource!.isNotEmpty)
                  _ResultDetailLine(
                    label: 'Cleanup source',
                    value: cleanupSource!,
                  ),
                if (retentionHint != null && retentionHint!.isNotEmpty)
                  _ResultDetailLine(
                    label: 'Retention hint',
                    value: retentionHint!,
                  ),
                const SizedBox(height: AppleSpacing.sm),
                _ReviewDecisionButtons(
                  decision: reviewDecision,
                  onChanged: onDecisionChanged!,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewDecisionButtons extends StatelessWidget {
  const _ReviewDecisionButtons({
    required this.decision,
    required this.onChanged,
  });

  final _ReviewDecision decision;
  final ValueChanged<_ReviewDecision> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppleSpacing.xs,
      runSpacing: AppleSpacing.xs,
      children: [
        AppleButton(
          label: 'Add to cleanup',
          icon: Icons.add_task_outlined,
          onPressed: decision == _ReviewDecision.include
              ? null
              : () => onChanged(_ReviewDecision.include),
        ),
        AppleButton(
          label: 'Keep this item',
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
      child: Text('$label: $value', style: context.vwFinePrint),
    );
  }
}

class _ResultBucketData {
  const _ResultBucketData({
    required this.title,
    required this.count,
    required this.detail,
  });

  final String title;
  final int count;
  final String detail;
}

class _ResultSummaryData {
  const _ResultSummaryData({
    required this.safe,
    required this.review,
    required this.keep,
    required this.selectedSafeCount,
    required this.selectedBytes,
  });

  final _ResultBucketData safe;
  final _ResultBucketData review;
  final _ResultBucketData keep;
  final int selectedSafeCount;
  final int selectedBytes;
}

class _ResultMetricCards extends StatelessWidget {
  const _ResultMetricCards({required this.buckets});

  final List<_ResultBucketData> buckets;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            children: [
              for (var index = 0; index < buckets.length; index++) ...[
                _ResultMetricCard(bucket: buckets[index]),
                if (index != buckets.length - 1)
                  const SizedBox(height: AppleSpacing.xs),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < buckets.length; index++) ...[
              Expanded(child: _ResultMetricCard(bucket: buckets[index])),
              if (index != buckets.length - 1)
                const SizedBox(width: AppleSpacing.xs),
            ],
          ],
        );
      },
    );
  }
}

class _ResultMetricCard extends StatelessWidget {
  const _ResultMetricCard({required this.bucket});

  final _ResultBucketData bucket;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppleSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(bucket.title, style: context.vwFinePrintInk),
            const SizedBox(height: AppleSpacing.xs),
            Text(
              bucket.count.toString(),
              style: context.vwBodyStrong.copyWith(fontSize: 23, height: 1.12),
            ),
            const SizedBox(height: AppleSpacing.xxs),
            Text(
              bucket.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.vwFinePrint,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.targetLabel,
    required this.phaseLabel,
    required this.phaseStep,
    required this.collapseProgress,
    required this.onBack,
  });

  final String targetLabel;
  final String phaseLabel;
  final int phaseStep;
  final double collapseProgress;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.volward;
    final phaseSemantics = '$phaseLabel, step $phaseStep of 5';
    final t = collapseProgress.clamp(0.0, 1.0).toDouble();
    final verticalPadding = ui.lerpDouble(AppleSpacing.sm, AppleSpacing.xs, t)!;
    final targetProgress = 1 - t;
    return DecoratedBox(
      key: AiAnalysisWorkspace.headerKey,
      decoration: BoxDecoration(
        color: tokens.canvas.withValues(alpha: ui.lerpDouble(0, 0.72, t)!),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppleSpacing.md,
            vertical: verticalPadding,
          ),
          child: Row(
            children: [
              Tooltip(
                message: l10n.aiWorkspaceBack,
                child: AppleButton(
                  key: AiAnalysisWorkspace.backKey,
                  label: l10n.aiWorkspaceBack,
                  icon: Icons.arrow_back,
                  variant: AppleButtonVariant.pearl,
                  onPressed: onBack,
                ),
              ),
              const SizedBox(width: AppleSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.aiWorkspaceTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.vwBodyStrong.copyWith(
                        fontSize: ui.lerpDouble(17, 15, t),
                        height: ui.lerpDouble(1.24, 1.12, t),
                      ),
                    ),
                    if (targetLabel.isNotEmpty)
                      ClipRect(
                        child: Align(
                          alignment: Alignment.topLeft,
                          heightFactor: targetProgress,
                          child: Opacity(
                            opacity: targetProgress,
                            child: Text(
                              targetLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.vwFinePrint,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppleSpacing.sm),
              Semantics(
                value: phaseSemantics,
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(phaseLabel, style: context.vwCaptionStrong),
                      const SizedBox(width: AppleSpacing.xs),
                      for (var step = 1; step <= 5; step++) ...[
                        Container(
                          width: 6,
                          height: 6,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PathLabel extends StatelessWidget {
  const _PathLabel(this.path, {this.style});

  final String path;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      value: path,
      child: Tooltip(
        message: path,
        child: Text(
          path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}
