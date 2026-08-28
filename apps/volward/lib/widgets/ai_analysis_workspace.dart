import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ai/ai_analysis_gateway.dart';
import '../ai/ai_provider.dart';
import '../ai/ai_settings_store.dart';
import '../ai/byok_ai_provider.dart';
import '../ai/platform_ai_provider.dart';
import '../analytics/analytics.dart';
import '../analytics/analytics_events.dart';
import '../ai/ai_result_groups.dart';
import '../l10n/l10n.dart';
import '../l10n/generated/app_localizations.dart';
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
  static const showAllResultsKey = Key('ai-analysis-show-all-results');
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
  bool _showAllResults = false;
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
      _showAllResults = false;
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
        _sizeByPath.addAll(resultSizes);
        _verdicts = verdicts;
        for (final verdict in verdicts) {
          if (verdict.verdict == 'safe_to_remove') {
            _selected.add(verdict.path);
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
      for (final verdict in enrichedVerdicts) {
        if (verdict.verdict == 'safe_to_remove') _selected.add(verdict.path);
      }
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

  List<_VerdictGroupView> _groupViewsForVerdict({
    required List<AiResultGroup> groups,
    required String verdict,
  }) {
    final views = <_VerdictGroupView>[];
    for (final group in groups) {
      final items = group.items
          .where((item) => item.verdict == verdict)
          .toList(growable: false);
      if (items.isEmpty) continue;
      views.add(
        _VerdictGroupView(
          path: group.path,
          items: items,
          totalBytes: items.fold<int>(
            0,
            (total, item) => total + (_sizeByPath[item.path] ?? 0),
          ),
        ),
      );
    }
    return views;
  }

  List<AiVerdict> _flattenGroupViews(List<_VerdictGroupView> groups) {
    return groups
        .expand((group) => group.items)
        .toList(growable: false);
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

  Widget _buildResults() {
    final l10n = context.l10n;
    final normalizedGroups = _normalizedResultGroups();
    final safeGroups = _groupViewsForVerdict(
      groups: normalizedGroups,
      verdict: 'safe_to_remove',
    );
    final reviewGroups = _groupViewsForVerdict(
      groups: normalizedGroups,
      verdict: 'review_needed',
    );
    final keepGroups = _groupViewsForVerdict(
      groups: normalizedGroups,
      verdict: 'keep',
    );
    final safe = _flattenGroupViews(safeGroups);
    final review = _flattenGroupViews(reviewGroups);
    final keep = _flattenGroupViews(keepGroups);
    final summary = _resultSummaryFor(safe: safe, review: review, keep: keep);
    final topSuggestions = [...safe, ...review];
    topSuggestions.sort((a, b) {
      int rank(AiVerdict item) => switch (item.verdict) {
        'safe_to_remove' => 0,
        'review_needed' => 1,
        _ => 2,
      };
      final actionableDiff = (rank(a) == 2 ? 1 : 0).compareTo(
        rank(b) == 2 ? 1 : 0,
      );
      if (actionableDiff != 0) return actionableDiff;
      final sizeDiff = (_sizeByPath[b.path] ?? 0).compareTo(
        _sizeByPath[a.path] ?? 0,
      );
      if (sizeDiff != 0) return sizeDiff;
      final rankDiff = rank(a).compareTo(rank(b));
      if (rankDiff != 0) return rankDiff;
      return a.path.compareTo(b.path);
    });
    final visibleTopSuggestions = topSuggestions
        .take(8)
        .toList(growable: false);
    final resultChildren = <Widget>[
      _buildResultsOverview(summary: summary),
      if (_showAllResults) ...[
        const SizedBox(height: AppleSpacing.lg),
        _verdictSection(
          title: l10n.aiVerdictSafe(safe.length),
          groups: safeGroups,
          selectable: true,
        ),
        _verdictSection(
          title: l10n.aiVerdictReview(review.length),
          groups: reviewGroups,
          selectable: true,
        ),
        _verdictSection(
          title: l10n.aiVerdictKeep(keep.length),
          groups: keepGroups,
          selectable: false,
        ),
      ] else ...[
        const SizedBox(height: AppleSpacing.lg),
        _buildTopSuggestions(l10n: l10n, items: visibleTopSuggestions),
      ],
      if (!_showAllResults) ...[
        const SizedBox(height: AppleSpacing.xs),
        TextButton(
          key: AiAnalysisWorkspace.showAllResultsKey,
          onPressed: () => setState(() => _showAllResults = true),
          child: Text(l10n.aiShowAllResults),
        ),
      ],
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return ListView(
            key: AiAnalysisWorkspace.resultsListKey,
            controller: _resultsScrollController,
            padding: const EdgeInsets.all(AppleSpacing.lg),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: resultChildren,
                    ),
                  ),
                  const SizedBox(width: AppleSpacing.lg),
                  SizedBox(
                    key: AiAnalysisWorkspace.summaryKey,
                    width: 260,
                    child: _buildSelectionSummary(),
                  ),
                ],
              ),
            ],
          );
        }
        return ListView(
          key: AiAnalysisWorkspace.resultsListKey,
          controller: _resultsScrollController,
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
              key: AiAnalysisWorkspace.summaryKey,
              width: double.infinity,
              child: _buildSelectionSummary(compact: true),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppleSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: resultChildren,
              ),
            ),
          ],
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

  Widget _buildTopSuggestions({
    required AppLocalizations l10n,
    required List<AiVerdict> items,
  }) {
    return _RecommendedResultsCard(
      title: l10n.aiResultsRecommendedTitle,
      subtitle: l10n.aiResultsRecommendedSubtitle,
      countLabel: l10n.aiResultsTopLimit(items.length),
      child: _ResultRowList(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return _ResultRow(
            item: item,
            sizeLabel: _formatBytes(_sizeByPath[item.path] ?? 0),
            statusLabel: _statusLabel(item),
            statusColor: _statusColor(item),
            selected: _selected.contains(item.path),
            selectable: item.verdict != 'keep',
            onChanged: item.verdict == 'keep'
                ? null
                : (value) => _toggle(item.path, value),
            cleanupMeta: _cleanupMetaLabel(item),
          );
        },
      ),
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

  Widget _verdictSection({
    required String title,
    required List<_VerdictGroupView> groups,
    required bool selectable,
  }) {
    if (groups.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppleSpacing.md),
      child: _RecommendedResultsCard(
        title: title,
        subtitle: '',
        countLabel: groups.fold<int>(
          0,
          (total, group) => total + group.items.length,
        ).toString(),
        child: _GroupedResultList(
          groups: groups,
          selectable: selectable,
          itemBuilder: _verdictTile,
        ),
      ),
    );
  }

  Widget _verdictTile({required AiVerdict item, required bool selectable}) {
    final selected = _selected.contains(item.path);
    return _ResultRow(
      item: item,
      sizeLabel: _formatBytes(_sizeByPath[item.path] ?? 0),
      statusLabel: _statusLabel(item),
      statusColor: _statusColor(item),
      selected: selected,
      selectable: selectable,
      onChanged: selectable ? (value) => _toggle(item.path, value) : null,
      cleanupMeta: _cleanupMetaLabel(item),
    );
  }

  String _statusLabel(AiVerdict item) {
    final l10n = context.l10n;
    return switch (item.verdict) {
      'safe_to_remove' => l10n.aiResultsStatusSafe,
      'review_needed' => l10n.aiResultsStatusReview,
      _ => l10n.aiResultsStatusKeep,
    };
  }

  Color _statusColor(AiVerdict item) {
    final tokens = context.volward;
    return switch (item.verdict) {
      'safe_to_remove' => const Color(0xFF267A42),
      'review_needed' => tokens.warning,
      _ => tokens.inkMuted48,
    };
  }

  String? _cleanupMetaLabel(AiVerdict item) {
    final source = item.cleanupSource;
    final hint = item.cleanupHint;
    final days = item.retentionDays;
    if ((source == null || source.isEmpty) &&
        (hint == null || hint.isEmpty) &&
        days == null) {
      return null;
    }
    final l10n = context.l10n;
    final sourceLabel = switch (source) {
      'ai_tool_cache' => l10n.aiCleanupSourceAiToolCache,
      'ai_generated_output' => l10n.aiCleanupSourceAiGeneratedOutput,
      'system_temp' => l10n.aiCleanupSourceSystemTemp,
      _ => null,
    };
    final parts = <String>[
      if (sourceLabel != null) sourceLabel,
      if (days != null) l10n.aiCleanupRetentionDays(days),
      if (hint != null && hint.isNotEmpty) hint,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _RecommendedResultsCard extends StatelessWidget {
  const _RecommendedResultsCard({
    required this.title,
    required this.subtitle,
    required this.countLabel,
    required this.child,
  });

  final String title;
  final String subtitle;
  final String countLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.hairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppleSpacing.sm,
                vertical: AppleSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppleSpacing.xs,
                      children: [
                        Text(title, style: context.vwCaptionStrong),
                        Text(subtitle, style: context.vwFinePrint),
                      ],
                    ),
                  ),
                  Text(countLabel, style: context.vwFinePrint),
                ],
              ),
            ),
            Divider(height: 1, color: tokens.dividerSoft),
            child,
          ],
        ),
      ),
    );
  }
}

class _ResultRowList extends StatelessWidget {
  const _ResultRowList({
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SizedBox.shrink();
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}

class _GroupedResultList extends StatelessWidget {
  const _GroupedResultList({
    required this.groups,
    required this.selectable,
    required this.itemBuilder,
  });

  final List<_VerdictGroupView> groups;
  final bool selectable;
  final Widget Function({required AiVerdict item, required bool selectable})
      itemBuilder;

  @override
  Widget build(BuildContext context) {
    final entries = <_GroupedResultEntry>[];
    for (final group in groups) {
      entries.add(_GroupedResultEntry.header(group));
      for (final item in group.items) {
        entries.add(_GroupedResultEntry.item(group, item));
      }
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return switch (entry) {
          _GroupedResultEntryHeader(:final group) => _GroupHeaderRow(
              path: group.path,
              itemCount: group.items.length,
              totalBytes: group.totalBytes,
            ),
          _GroupedResultEntryItem(:final item) =>
            itemBuilder(item: item, selectable: selectable),
        };
      },
    );
  }
}

class _GroupHeaderRow extends StatelessWidget {
  const _GroupHeaderRow({
    required this.path,
    required this.itemCount,
    required this.totalBytes,
  });

  final String path;
  final int itemCount;
  final int totalBytes;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(
          bottom: BorderSide(color: tokens.dividerSoft),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppleSpacing.sm,
          vertical: AppleSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(path, style: context.vwCaptionStrong),
            ),
            const SizedBox(width: AppleSpacing.sm),
            Text(
              '$itemCount · ${_AiAnalysisWorkspaceState._formatBytes(totalBytes)}',
              style: context.vwFinePrint,
            ),
          ],
        ),
      ),
    );
  }
}

class _VerdictGroupView {
  const _VerdictGroupView({
    required this.path,
    required this.items,
    required this.totalBytes,
  });

  final String path;
  final List<AiVerdict> items;
  final int totalBytes;
}

sealed class _GroupedResultEntry {
  const _GroupedResultEntry();

  factory _GroupedResultEntry.header(_VerdictGroupView group) =
      _GroupedResultEntryHeader;

  factory _GroupedResultEntry.item(_VerdictGroupView group, AiVerdict item) =
      _GroupedResultEntryItem;
}

final class _GroupedResultEntryHeader extends _GroupedResultEntry {
  const _GroupedResultEntryHeader(this.group);

  final _VerdictGroupView group;
}

final class _GroupedResultEntryItem extends _GroupedResultEntry {
  const _GroupedResultEntryItem(this.group, this.item);

  final _VerdictGroupView group;
  final AiVerdict item;
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.item,
    required this.sizeLabel,
    required this.statusLabel,
    required this.statusColor,
    required this.selected,
    required this.selectable,
    required this.onChanged,
    required this.cleanupMeta,
  });

  final AiVerdict item;
  final String sizeLabel;
  final String statusLabel;
  final Color statusColor;
  final bool selected;
  final bool selectable;
  final ValueChanged<bool?>? onChanged;
  final String? cleanupMeta;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    final subtitleParts = <String>[
      item.confidence,
      if (item.reason.isNotEmpty) item.reason,
      if (cleanupMeta != null && cleanupMeta!.isNotEmpty) cleanupMeta!,
    ];
    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppleSpacing.sm,
        vertical: 10,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: selectable
                ? Checkbox(
                    value: selected,
                    onChanged: onChanged,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )
                : Icon(Icons.lock_outline, size: 18, color: tokens.inkMuted48),
          ),
          const SizedBox(width: AppleSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _PathLabel(item.path),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: AppleSpacing.xxs),
                  Text(
                    subtitleParts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.vwFinePrint,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppleSpacing.sm),
          SizedBox(
            width: 88,
            child: Text(
              sizeLabel,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.vwCaptionStrong,
            ),
          ),
          const SizedBox(width: AppleSpacing.sm),
          SizedBox(
            width: 72,
            child: Text(
              statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.vwCaptionStrong.copyWith(color: statusColor),
            ),
          ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.dividerSoft)),
      ),
      child: selectable
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onChanged?.call(!selected),
                child: body,
              ),
            )
          : body,
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
  const _PathLabel(this.path);

  final String path;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      value: path,
      child: Tooltip(
        message: path,
        child: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
