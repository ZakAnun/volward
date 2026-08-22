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
        if (candidate.memberPaths.isNotEmpty) {
          memberPathsByPath[candidate.path] = candidate.memberPaths;
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
      _estimatedTokens = 0;
      _hasExistingResult = false;
      _truncated = false;
      _candidatesBeforeCap = 0;
      _resultCacheKey = '';
      _rootPath = '';
    });
    try {
      final mode = await widget.gateway.getMode();
      if (!_isCurrent(generation)) return;
      final provider = await widget.gateway.resolveProvider();
      if (!_isCurrent(generation)) return;
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
    return false;
  }

  Future<void> _acceptPrivacy() async {
    final generation = _beginOperation();
    await widget.gateway.setPrivacyAccepted(true);
    if (!_isCurrent(generation)) return;
    setState(() => _phase = _Phase.precheck);
    await _startAnalysis();
  }

  void _declinePrivacy() {
    final generation = _beginOperation();
    if (!_isCurrent(generation)) return;
    setState(() => _phase = _Phase.precheck);
  }

  Future<bool> _loadPreviousResult() async {
    final generation = _beginOperation();
    final l10n = context.l10n;
    final key =
        _resultCacheKey.isNotEmpty ? _resultCacheKey : widget.snapshotId;
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
      final model =
          provider is ByokAiProvider ? provider.model : 'deepseek-v4-flash';
      final inputTokens =
          _estimatedTokens > 0 ? _estimatedTokens : (_unknown.length * 8 + 200);
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
          'keep_count':
              verdicts.where((verdict) => verdict.verdict == 'keep').length,
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
      unawaited(
        Analytics.instance.track(AnalyticsEvents.aiAnalysisFailed, {
          'provider': providerLabel,
          'error': _normalizeAiError(error),
          'duration_ms': stopwatch.elapsedMilliseconds,
        }),
      );
      if (!_isCurrent(generation)) return;
      setState(() {
        _analyzing = false;
        _phase = _Phase.precheck;
        _error = message;
      });
    }
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
    ]) {
      if (message.contains(key)) return key;
    }
    if (message.contains('api_error:')) return 'api_error';
    if (message.contains('network_error')) return 'network_error';
    return 'unknown';
  }

  List<String> _deleteTargets() {
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

  void _setDeleting(bool value, int generation, {_Phase? phase}) {
    if (!_isCurrent(generation)) return;
    setState(() {
      _deleting = value;
      if (phase != null) _phase = phase;
    });
    if (_isCurrent(generation)) widget.onDeletingChanged(value);
  }

  Future<void> _deleteSelected() async {
    if (_deleting) return;
    final targets = _deleteTargets();
    if (targets.isEmpty) return;
    final generation = _beginOperation();
    final l10n = context.l10n;
    final Map<String, dynamic> preview;
    try {
      preview = await widget.gateway.deleteEntries(targets, dryRun: true);
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
    _setDeleting(true, generation, phase: _Phase.deleting);
    try {
      final report = await widget.gateway.deleteEntries(
        targets,
        rescanAfterDelete: true,
      );
      if (!_isCurrent(generation)) return;
      final error = report['error'];
      if (error != null) {
        _setDeleting(false, generation, phase: _Phase.results);
        if (!_isCurrent(generation)) return;
        setState(() => _error = l10n.deleteFailed(error.toString()));
        return;
      }
      final failed = report['failed_paths'];
      final failedCount = failed is List ? failed.length : 0;
      final freedAfter = (report['freed_bytes'] as num?)?.toInt() ?? 0;
      final deletedCount = (report['deleted_count'] as num?)?.toInt() ??
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
        _setDeleting(false, generation, phase: _Phase.results);
        if (!_isCurrent(generation)) return;
        setState(() {
          _error = l10n.deleteSuccessWithFailures(
            failedCount,
            _formatBytes(freedAfter),
          );
        });
        return;
      }
      _setDeleting(false, generation, phase: _Phase.results);
      if (!_isCurrent(generation)) return;
      widget.onDeleteCompleted();
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _setDeleting(false, generation, phase: _Phase.results);
      if (!_isCurrent(generation)) return;
      setState(() => _error = l10n.deleteFailed(error.toString()));
    }
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

  int get _selectedBytes => _selected.fold(
        0,
        (total, path) => total + (_sizeByPath[path] ?? 0),
      );

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
    final l10n = context.l10n;
    return DecoratedBox(
      key: AiAnalysisWorkspace.workspaceKey,
      decoration: BoxDecoration(color: tokens.canvasParchment),
      child: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.error => _ErrorBody(
            message: _error ?? l10n.aiErrorUnknown,
            retryLabel: l10n.aiActionRetry,
            onRetry: _bootstrap,
          ),
        _Phase.privacy => _buildPrivacy(tokens),
        _Phase.analyzing => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: AppleSpacing.md),
                Text(l10n.aiAnalyzing),
              ],
            ),
          ),
        _Phase.precheck => _buildPrecheck(tokens),
        _Phase.results => _buildResults(tokens),
        _Phase.deleting => _buildDeleting(),
      },
    );
  }

  Widget _buildPrivacy(VolwardTokens tokens) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppleSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.aiPrivacyTitle,
              style: AppleTypography.tagline.copyWith(color: tokens.ink),
            ),
            const SizedBox(height: AppleSpacing.sm),
            Text(
              l10n.aiPrivacyBody,
              style: AppleTypography.body.copyWith(color: tokens.inkMuted80),
            ),
            const SizedBox(height: AppleSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: AppleButton(
                    key: AiAnalysisWorkspace.backKey,
                    label: l10n.scanActionCancel,
                    variant: AppleButtonVariant.pearl,
                    expanded: true,
                    onPressed: _declinePrivacy,
                  ),
                ),
                const SizedBox(width: AppleSpacing.sm),
                Expanded(
                  child: AppleButton(
                    label: l10n.aiPrivacyAccept,
                    expanded: true,
                    onPressed: _acceptPrivacy,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrecheck(VolwardTokens tokens) {
    final l10n = context.l10n;
    final canAnalyze =
        _hasProvider && !(_mode == AiMode.platform && _platformCredits == 0);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppleSpacing.lg,
              AppleSpacing.sm,
              AppleSpacing.lg,
              AppleSpacing.lg,
            ),
            children: [
              if (widget.targetLabel.isNotEmpty) ...[
                Text(
                  widget.targetLabel,
                  style: AppleTypography.captionStrong.copyWith(
                    color: tokens.inkMuted80,
                  ),
                ),
                const SizedBox(height: AppleSpacing.xs),
              ],
              Text(
                l10n.aiPreCheckSafeTitle(_preClassified.length),
                style: AppleTypography.tagline.copyWith(color: tokens.ink),
              ),
              const SizedBox(height: AppleSpacing.xs),
              Text(
                l10n.aiPreCheckUnknownTitle(_unknown.length, _estimatedTokens),
                style: AppleTypography.body.copyWith(color: tokens.inkMuted80),
              ),
              if (_truncated) ...[
                const SizedBox(height: AppleSpacing.xs),
                Text(
                  l10n.aiTruncatedNotice(
                    _unknown.length,
                    _candidatesBeforeCap,
                  ),
                  style:
                      AppleTypography.caption.copyWith(color: tokens.warning),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppleSpacing.sm),
                Text(
                  _error!,
                  style: AppleTypography.caption.copyWith(color: tokens.danger),
                ),
              ],
              if (!_hasProvider) ...[
                const SizedBox(height: AppleSpacing.sm),
                Text(
                  _mode == AiMode.platform
                      ? l10n.aiSettingsSessionExpired
                      : l10n.aiNoApiKey,
                  style:
                      AppleTypography.caption.copyWith(color: tokens.warning),
                ),
                const SizedBox(height: AppleSpacing.sm),
                IconButton(
                  key: AiAnalysisWorkspace.settingsKey,
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: l10n.aiAnalysisTitle,
                  onPressed: widget.onOpenSettings,
                ),
              ],
              if (_mode == AiMode.platform && _platformCredits != null) ...[
                const SizedBox(height: AppleSpacing.sm),
                Text(
                  l10n.aiPrecheckCreditsCost(_platformCredits!),
                  style: AppleTypography.caption.copyWith(
                    color: tokens.inkMuted80,
                  ),
                ),
                if (_platformCredits == 0)
                  Text(
                    l10n.aiInsufficientCredits,
                    style: AppleTypography.caption.copyWith(
                      color: tokens.warning,
                    ),
                  ),
              ],
              const SizedBox(height: AppleSpacing.lg),
              if (_preClassified.isNotEmpty) ...[
                Text(
                  l10n.aiPreCheckSafeSelectable(_preClassified.length),
                  style: AppleTypography.captionStrong.copyWith(
                    color: tokens.ink,
                  ),
                ),
                const SizedBox(height: AppleSpacing.xs),
                ..._preClassified.map(_preClassifiedTile),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppleSpacing.lg,
              AppleSpacing.sm,
              AppleSpacing.lg,
              AppleSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppleButton(
                    key: AiAnalysisWorkspace.backKey,
                    label: l10n.scanActionCancel,
                    variant: AppleButtonVariant.pearl,
                    expanded: true,
                    onPressed: widget.onExit,
                  ),
                ),
                if (_hasExistingResult) ...[
                  const SizedBox(width: AppleSpacing.sm),
                  Expanded(
                    child: AppleButton(
                      key: AiAnalysisWorkspace.loadPreviousKey,
                      label: l10n.aiActionLoadPrevious,
                      variant: AppleButtonVariant.pearl,
                      expanded: true,
                      onPressed: _loadPreviousResult,
                    ),
                  ),
                ],
                const SizedBox(width: AppleSpacing.sm),
                Expanded(
                  child: AppleButton(
                    key: _hasExistingResult
                        ? AiAnalysisWorkspace.analyzeAgainKey
                        : null,
                    label: _hasExistingResult
                        ? l10n.aiActionContinue
                        : l10n.aiStartAnalysis,
                    expanded: true,
                    onPressed: canAnalyze ? _startAnalysis : null,
                  ),
                ),
              ],
            ),
          ),
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
    return CheckboxListTile(
      value: deletable ? _selected.contains(path) : false,
      onChanged: deletable ? (value) => _toggle(path, value) : null,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: Text(path, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_formatBytes(size)} - $confidence'
        '${reason.isNotEmpty ? ' - $reason' : ''}',
      ),
    );
  }

  Widget _buildResults(VolwardTokens tokens) {
    final l10n = context.l10n;
    final safe = _verdicts
        .where((verdict) => verdict.verdict == 'safe_to_remove')
        .toList();
    final review = _verdicts
        .where((verdict) => verdict.verdict == 'review_needed')
        .toList();
    final keep =
        _verdicts.where((verdict) => verdict.verdict == 'keep').toList();
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: AiAnalysisWorkspace.resultsListKey,
            padding: const EdgeInsets.fromLTRB(
              AppleSpacing.lg,
              AppleSpacing.sm,
              AppleSpacing.lg,
              AppleSpacing.lg,
            ),
            children: [
              Text(
                l10n.aiAnalysisTitle,
                key: AiAnalysisWorkspace.summaryKey,
                style: AppleTypography.tagline.copyWith(color: tokens.ink),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppleSpacing.sm),
                Text(
                  _error!,
                  style: AppleTypography.caption.copyWith(color: tokens.danger),
                ),
              ],
              const SizedBox(height: AppleSpacing.lg),
              if (_preClassified.isNotEmpty) ...[
                Text(
                  l10n.aiPreCheckSafeSelectable(_preClassified.length),
                  style: AppleTypography.captionStrong.copyWith(
                    color: tokens.ink,
                  ),
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
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppleSpacing.lg,
              AppleSpacing.sm,
              AppleSpacing.lg,
              AppleSpacing.md,
            ),
            child: AppleButton(
              key: AiAnalysisWorkspace.deleteKey,
              label:
                  '${l10n.aiDeleteSelected(_selected.length)} (${_formatBytes(_selectedBytes)})',
              expanded: true,
              onPressed: _selected.isEmpty ? null : _deleteSelected,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeleting() {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppleSpacing.md),
          Text(l10n.deleteActionDelete),
        ],
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
        ...items.map((item) {
          final size = _sizeByPath[item.path] ?? 0;
          if (!selectable) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.lock_outline,
                size: 20,
                color: tokens.inkMuted48,
              ),
              title: Text(
                item.path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${_formatBytes(size)} - ${item.reason}'),
            );
          }
          return CheckboxListTile(
            value: _selected.contains(item.path),
            onChanged: (value) => _toggle(item.path, value),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(
              item.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_formatBytes(size)} - ${item.confidence} - ${item.reason}',
            ),
          );
        }),
        const SizedBox(height: AppleSpacing.md),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppleSpacing.lg),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: SelectableText(
                    message,
                    textAlign: TextAlign.center,
                    style: AppleTypography.body.copyWith(color: tokens.danger),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppleSpacing.md),
            AppleButton(label: retryLabel, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
