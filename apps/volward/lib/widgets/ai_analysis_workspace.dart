import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ai/ai_analysis_gateway.dart';
import '../ai/ai_provider.dart';
import '../ai/ai_settings_store.dart';
import '../ai/byok_ai_provider.dart';
import '../ai/platform_ai_provider.dart';
import '../analytics/analytics.dart';
import '../analytics/analytics_events.dart';
import '../l10n/l10n.dart';
import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';
import 'apple_widgets.dart';

class _AiCandidatesBootstrap {
  const _AiCandidatesBootstrap({
    required this.preClassified,
    required this.unknown,
    required this.sizeByPath,
    required this.memberPathsByPath,
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
  final Map<String, List<String>> memberPathsByPath;
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
  final memberPathsByPath = <String, List<String>>{};
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
        if (candidate.deleteMemberPaths.isNotEmpty) {
          memberPathsByPath[candidate.path] = candidate.deleteMemberPaths;
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
    memberPathsByPath: memberPathsByPath,
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
  final Map<String, List<String>> _memberPathsByPath = {};
  bool _hasProvider = false;
  bool _analyzing = false;
  bool _deleting = false;
  int? _partialDeleteFailedCount;
  int? _partialDeleteFreedBytes;
  List<String> _retryTargets = [];
  AiMode _mode = AiMode.off;
  int? _platformCredits;
  int _operationGeneration = 0;

  int _beginOperation() => ++_operationGeneration;
  bool _isCurrent(int generation) =>
      mounted && generation == _operationGeneration;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _operationGeneration++;
    super.dispose();
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
    setState(() {
      _phase = _Phase.loading;
      _error = null;
      _sizeByPath.clear();
      _memberPathsByPath.clear();
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
        _memberPathsByPath
          ..clear()
          ..addAll(parsed.memberPathsByPath);
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
          AiVerdict(
            path: path,
            verdict: entry['verdict']?.toString() ?? '',
            confidence: entry['confidence']?.toString() ?? '',
            reason: entry['reason']?.toString() ?? '',
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
    unawaited(
      Analytics.instance.track(AnalyticsEvents.aiAnalysisStarted, {
        'provider': providerLabel,
        'candidate_count': _unknown.length,
      }),
    );
    try {
      final verdicts = await provider.analyze(_unknown);
      if (!_isCurrent(generation)) return;
      final model = provider is ByokAiProvider
          ? provider.model
          : 'deepseek-v4-flash';
      final inputTokens = _estimatedTokens > 0
          ? _estimatedTokens
          : (_unknown.length * 8 + 200);
      final outputTokens = verdicts.length * 40;
      final cost = (inputTokens / 1e6) * 0.14 + (outputTokens / 1e6) * 0.28;
      final entries = verdicts
          .map(
            (verdict) => {
              'path': verdict.path,
              'size_bytes': _sizeByPath[verdict.path] ?? 0,
              'verdict': verdict.verdict,
              'confidence': verdict.confidence,
              'reason': verdict.reason,
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
      for (final verdict in verdicts) {
        if (verdict.verdict == 'safe_to_remove') _selected.add(verdict.path);
      }
      if (!_isCurrent(generation)) return;
      unawaited(
        Analytics.instance.track(AnalyticsEvents.aiAnalysisCompleted, {
          'provider': providerLabel,
          'duration_ms': stopwatch.elapsedMilliseconds,
          'safe_count': verdicts
              .where((verdict) => verdict.verdict == 'safe_to_remove')
              .length,
          'review_count': verdicts
              .where((verdict) => verdict.verdict == 'review_needed')
              .length,
          'keep_count': verdicts
              .where((verdict) => verdict.verdict == 'keep')
              .length,
        }),
      );
      if (!_isCurrent(generation)) return;
      setState(() {
        _verdicts = verdicts;
        _hasExistingResult = true;
        _analyzing = false;
        _phase = _Phase.results;
      });
    } catch (error) {
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
      final members = _memberPathsByPath[path];
      if (members != null && members.isNotEmpty) {
        targets.addAll(members);
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

  Widget _buildResults() {
    final l10n = context.l10n;
    final safe = _verdicts
        .where((verdict) => verdict.verdict == 'safe_to_remove')
        .toList();
    final review = _verdicts
        .where((verdict) => verdict.verdict == 'review_needed')
        .toList();
    final keep = _verdicts
        .where((verdict) => verdict.verdict == 'keep')
        .toList();
    final resultsList = ListView(
      key: AiAnalysisWorkspace.resultsListKey,
      padding: const EdgeInsets.all(AppleSpacing.lg),
      children: [
        if (_preClassified.isNotEmpty) ...[
          Text(
            l10n.aiPreCheckSafeSelectable(_preClassified.length),
            style: context.vwCaptionStrong,
          ),
          ..._preClassified.map(_preClassifiedTile),
          const SizedBox(height: AppleSpacing.md),
        ],
        _verdictSection(
          title: l10n.aiVerdictSafe(safe.length),
          items: safe,
          selectable: true,
        ),
        _verdictSection(
          title: l10n.aiVerdictReview(review.length),
          items: review,
          selectable: true,
        ),
        _verdictSection(
          title: l10n.aiVerdictKeep(keep.length),
          items: keep,
          selectable: false,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: resultsList),
              const VerticalDivider(width: 1),
              SizedBox(
                key: AiAnalysisWorkspace.summaryKey,
                width: 260,
                child: _buildSelectionSummary(),
              ),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(
              key: AiAnalysisWorkspace.summaryKey,
              width: double.infinity,
              child: _buildSelectionSummary(compact: true),
            ),
            const Divider(height: 1),
            Expanded(child: resultsList),
          ],
        );
      },
    );
  }

  Widget _buildSelectionSummary({bool compact = false}) {
    final l10n = context.l10n;
    final tokens = context.volward;
    return Padding(
      padding: EdgeInsets.all(compact ? AppleSpacing.sm : AppleSpacing.lg),
      child: Column(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.aiWorkspaceSelectedSummary(
              _selected.length,
              _formatBytes(_selectedBytes),
            ),
            style: context.vwBodyStrong,
          ),
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
          if (!compact) const Spacer(),
          SizedBox(height: compact ? AppleSpacing.xs : AppleSpacing.md),
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
    required List<AiVerdict> items,
    required bool selectable,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    final tokens = context.volward;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppleTypography.captionStrong.copyWith(color: tokens.ink),
        ),
        const SizedBox(height: AppleSpacing.xs),
        ...items.map(
          (item) => _verdictTile(item: item, selectable: selectable),
        ),
        const SizedBox(height: AppleSpacing.md),
      ],
    );
  }

  Widget _verdictTile({required AiVerdict item, required bool selectable}) {
    final size = _sizeByPath[item.path] ?? 0;
    final subtitle =
        '${_formatBytes(size)} · ${item.confidence} · ${item.reason}';
    if (!selectable) {
      return Material(
        color: Colors.transparent,
        child: ListTile(
          enabled: false,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline, size: 20),
          title: _PathLabel(item.path),
          subtitle: Text(subtitle),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: CheckboxListTile(
        value: _selected.contains(item.path),
        onChanged: (value) => _toggle(item.path, value),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: _PathLabel(item.path),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.targetLabel,
    required this.phaseLabel,
    required this.phaseStep,
    required this.onBack,
  });

  final String targetLabel;
  final String phaseLabel;
  final int phaseStep;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.volward;
    final phaseSemantics = '$phaseLabel, step $phaseStep of 5';
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppleSpacing.md,
          vertical: AppleSpacing.sm,
        ),
        child: Row(
          children: [
            IconButton(
              key: AiAnalysisWorkspace.backKey,
              tooltip: l10n.aiWorkspaceBack,
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
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
                    style: context.vwBodyStrong,
                  ),
                  if (targetLabel.isNotEmpty)
                    Text(
                      targetLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.vwFinePrint,
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
