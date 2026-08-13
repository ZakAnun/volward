import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ai/ai_provider.dart';
import 'ai/ai_settings_store.dart';
import 'ai/byok_ai_provider.dart';
import 'ai/platform_ai_provider.dart';
import 'analytics/analytics.dart';
import 'analytics/analytics_events.dart';
import 'l10n/l10n.dart';
import 'theme/apple_tokens.dart';
import 'theme/volward_tokens.dart';
import 'volward_session.dart';
import 'widgets/apple_widgets.dart';

/// Parsed AI candidates payload (built off the UI isolate).
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

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}

_AiCandidatesBootstrap _parseAiCandidatesPayload(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('ai candidates payload is not an object');
  }
  final map = Map<String, dynamic>.from(decoded);

  final sizeByPath = <String, int>{};
  final memberPathsByPath = <String, List<String>>{};
  final pre = <Map<String, dynamic>>[];
  final preRaw = map['pre_classified'];
  if (preRaw is List) {
    for (final e in preRaw) {
      if (e is Map) {
        final entry = Map<String, dynamic>.from(e);
        pre.add(entry);
        final path = entry['path'] as String?;
        if (path != null) {
          sizeByPath[path] = _asInt(entry['size_bytes']);
        }
      }
    }
  }

  final unknown = <AiCandidate>[];
  final unkRaw = map['unknown_candidates'];
  if (unkRaw is List) {
    for (final e in unkRaw) {
      if (e is Map) {
        final c = AiCandidate.fromJson(Map<String, dynamic>.from(e));
        unknown.add(c);
        sizeByPath[c.path] = c.sizeBytes;
        if (c.memberPaths.isNotEmpty) {
          memberPathsByPath[c.path] = c.memberPaths;
        }
      }
    }
  }

  final selected = <String>{};
  for (final e in pre) {
    if (e['confidence'] == 'high' && e['deletable'] == true) {
      final path = e['path'] as String?;
      if (path != null) selected.add(path);
    }
  }

  return _AiCandidatesBootstrap(
    preClassified: pre,
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

/// AI-assisted disk cleanup: pre-check → analyze → review verdicts → delete.
class AiAnalysisPage extends StatefulWidget {
  const AiAnalysisPage({super.key, required this.snapshotId});

  final String snapshotId;

  @override
  State<AiAnalysisPage> createState() => _AiAnalysisPageState();
}

enum _Phase { loading, precheck, analyzing, results, error }

/// Choice when a previous AI result already exists for this snapshot.
enum _ExistingResultChoice { loadPrevious, reanalyze, cancel }

class _AiAnalysisPageState extends State<AiAnalysisPage> {
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

  /// Aggregate candidate path → the files it stands for. Deleting an aggregate
  /// must target these instead of the shared parent directory.
  final Map<String, List<String>> _memberPathsByPath = {};

  bool _hasProvider = false;
  bool _analyzing = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _phase = _Phase.loading;
      _error = null;
      _sizeByPath.clear();
      _memberPathsByPath.clear();
      _selected.clear();
      _preClassified = [];
      _unknown = [];
      _verdicts = [];
      _truncated = false;
      _candidatesBeforeCap = 0;
    });
    try {
      final provider = await AiSettingsStore.instance.resolveProvider();
      if (!mounted) return;
      // Read after the first await: initState calls this synchronously, and
      // inherited widgets are not available until initState returns.
      final l10n = context.l10n;
      final raw = await VolwardSession.instance?.buildAiCandidatesJsonAsync(
        widget.snapshotId,
      );
      if (!mounted) return;
      if (raw == null || raw.isEmpty) {
        setState(() {
          _hasProvider = provider != null;
          _phase = _Phase.error;
          _error = l10n.aiErrorNativeUnavailable;
        });
        return;
      }
      if (raw.startsWith('error:')) {
        setState(() {
          _hasProvider = provider != null;
          _phase = _Phase.error;
          _error = raw;
        });
        return;
      }

      // Top-level [compute] — do not wrap in an instance-method closure; that
      // captures State/Scaffold and fails Isolate sendability checks.
      final parsed = await compute(_parseAiCandidatesPayload, raw);
      if (!mounted) return;

      setState(() {
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
      if (_hasExistingResult && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _phase != _Phase.precheck) return;
          _offerExistingResult();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.toString();
      });
    }
  }

  static String _fmt(num? bytes) {
    if (bytes == null) return '—';
    final b = bytes.toInt();
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(2)} GB';
  }

  Future<bool> _ensurePrivacyAccepted() async {
    final store = AiSettingsStore.instance;
    if (await store.isPrivacyAccepted()) return true;
    if (!mounted) return false;
    final l10n = context.l10n;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.aiPrivacyTitle),
        content: Text(l10n.aiPrivacyBody),
        actions: [
          AppleButton(
            label: l10n.scanActionCancel,
            variant: AppleButtonVariant.pearl,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          AppleButton(
            label: l10n.aiPrivacyAccept,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
    await store.setPrivacyAccepted(true);
    return true;
  }

  Future<_ExistingResultChoice> _promptExistingResult() async {
    if (!mounted) return _ExistingResultChoice.cancel;
    final l10n = context.l10n;
    final choice = await showDialog<_ExistingResultChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.aiOverwriteTitle),
        content: Text(l10n.aiOverwriteBody),
        actions: [
          AppleButton(
            label: l10n.scanActionCancel,
            variant: AppleButtonVariant.pearl,
            onPressed: () =>
                Navigator.pop(ctx, _ExistingResultChoice.cancel),
          ),
          AppleButton(
            label: l10n.aiActionLoadPrevious,
            variant: AppleButtonVariant.pearl,
            onPressed: () =>
                Navigator.pop(ctx, _ExistingResultChoice.loadPrevious),
          ),
          AppleButton(
            label: l10n.aiActionContinue,
            onPressed: () =>
                Navigator.pop(ctx, _ExistingResultChoice.reanalyze),
          ),
        ],
      ),
    );
    return choice ?? _ExistingResultChoice.cancel;
  }

  Future<void> _offerExistingResult() async {
    final choice = await _promptExistingResult();
    if (!mounted) return;
    switch (choice) {
      case _ExistingResultChoice.loadPrevious:
        await _loadPreviousResult();
      case _ExistingResultChoice.reanalyze:
      case _ExistingResultChoice.cancel:
        break;
    }
  }

  Future<bool> _loadPreviousResult() async {
    final l10n = context.l10n;
    final key = _resultCacheKey.isNotEmpty
        ? _resultCacheKey
        : widget.snapshotId;
    final raw = VolwardSession.instance?.loadAiResultJson(key);
    if ((raw == null || raw.isEmpty || raw.startsWith('error:')) &&
        key != widget.snapshotId) {
      // Legacy saves were keyed only by snapshot_id.
      final legacy = VolwardSession.instance?.loadAiResultJson(
        widget.snapshotId,
      );
      return _applyLoadedResult(legacy, l10n.aiLoadPreviousFailed);
    }
    return _applyLoadedResult(raw, l10n.aiLoadPreviousFailed);
  }

  Future<bool> _applyLoadedResult(String? raw, String failureMessage) async {
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) {
      if (!mounted) return false;
      setState(() {
        _error = failureMessage;
        _phase = _Phase.precheck;
      });
      return false;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('expected object');
      }
      final map = Map<String, dynamic>.from(decoded);
      final entriesRaw = map['entries'];
      if (entriesRaw is! List) {
        throw const FormatException('missing entries');
      }

      final verdicts = <AiVerdict>[];
      for (final e in entriesRaw) {
        if (e is! Map) continue;
        final entry = Map<String, dynamic>.from(e);
        final path = entry['path'] as String?;
        if (path == null || path.isEmpty) continue;
        _sizeByPath[path] = _asInt(entry['size_bytes']);
        verdicts.add(
          AiVerdict(
            path: path,
            verdict: entry['verdict']?.toString() ?? '',
            confidence: entry['confidence']?.toString() ?? '',
            reason: entry['reason']?.toString() ?? '',
          ),
        );
      }

      if (!mounted) return false;
      setState(() {
        _verdicts = verdicts;
        for (final v in verdicts) {
          if (v.verdict == 'safe_to_remove') {
            _selected.add(v.path);
          }
        }
        _hasExistingResult = true;
        _error = null;
        _phase = _Phase.results;
      });
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _error = failureMessage;
        _phase = _Phase.precheck;
      });
      return false;
    }
  }

  Future<void> _startAnalysis() async {
    if (!_hasProvider || _analyzing) return;
    if (!await _ensurePrivacyAccepted()) return;

    if (_hasExistingResult) {
      final choice = await _promptExistingResult();
      if (!mounted) return;
      switch (choice) {
        case _ExistingResultChoice.cancel:
          return;
        case _ExistingResultChoice.loadPrevious:
          await _loadPreviousResult();
          return;
        case _ExistingResultChoice.reanalyze:
          break;
      }
    }

    final provider = await AiSettingsStore.instance.resolveProvider();
    if (provider == null) {
      setState(() => _hasProvider = false);
      return;
    }

    setState(() {
      _analyzing = true;
      _phase = _Phase.analyzing;
      _error = null;
    });

    final mode = await AiSettingsStore.instance.getMode();
    final providerLabel = mode == AiMode.platform ? 'platform' : 'byok';
    final sw = Stopwatch()..start();
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

      final inputTokens = _estimatedTokens > 0
          ? _estimatedTokens
          : (_unknown.length * 8 + 200);
      final outputTokens = verdicts.length * 40;
      // DeepSeek-V4-Flash list rates (approx.): ~$0.14/MTok in, ~$0.28/MTok out.
      final cost =
          (inputTokens / 1e6) * 0.14 + (outputTokens / 1e6) * 0.28;

      final entries = verdicts
          .map(
            (v) => {
              'path': v.path,
              'size_bytes': _sizeByPath[v.path] ?? 0,
              'verdict': v.verdict,
              'confidence': v.confidence,
              'reason': v.reason,
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

      VolwardSession.instance?.saveAiResultJson(
        widget.snapshotId,
        resultJson,
      );

      for (final v in verdicts) {
        if (v.verdict == 'safe_to_remove') {
          _selected.add(v.path);
        }
      }

      unawaited(
        Analytics.instance.track(AnalyticsEvents.aiAnalysisCompleted, {
          'provider': providerLabel,
          'duration_ms': sw.elapsedMilliseconds,
          'safe_count': verdicts
              .where((v) => v.verdict == 'safe_to_remove')
              .length,
          'review_count':
              verdicts.where((v) => v.verdict == 'review_needed').length,
          'keep_count': verdicts.where((v) => v.verdict == 'keep').length,
        }),
      );

      if (!mounted) return;
      setState(() {
        _verdicts = verdicts;
        _hasExistingResult = true;
        _analyzing = false;
        _phase = _Phase.results;
      });
    } catch (e) {
      unawaited(
        Analytics.instance.track(AnalyticsEvents.aiAnalysisFailed, {
          'provider': providerLabel,
          'error': _normalizeAiError(e),
          'duration_ms': sw.elapsedMilliseconds,
        }),
      );
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _phase = _Phase.precheck;
        _error = e.toString();
      });
    }
  }

  static String _normalizeAiError(Object e) {
    final s = e.toString();
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
      if (s.contains(key)) return key;
    }
    if (s.contains('api_error:')) return 'api_error';
    if (s.contains('network_error')) return 'network_error';
    return 'unknown';
  }

  /// Expands the selection into real delete targets: an aggregate candidate
  /// stands for the files folded into it, never for its parent directory,
  /// which may also hold data the user never selected.
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

  Future<void> _deleteSelected() async {
    final session = VolwardSession.instance;
    if (session == null) return;
    final targets = _deleteTargets();
    if (targets.isEmpty) return;

    final l10n = context.l10n;
    final Map<String, dynamic> preview;
    try {
      preview = await session.deleteEntries(targets, dryRun: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = l10n.deleteFailed(e.toString()));
      return;
    }
    if (!mounted) return;
    final count = (preview['deleted_count'] as num?)?.toInt() ?? targets.length;
    final freed = (preview['freed_bytes'] as num?)?.toInt() ?? _selectedBytes;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmMessage(count, _fmt(freed))),
        actions: [
          AppleButton(
            label: l10n.scanActionCancel,
            variant: AppleButtonVariant.pearl,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          AppleButton(
            label: l10n.deleteActionDelete,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final report = await session.deleteEntries(
        targets,
        rescanAfterDelete: true,
      );
      if (!mounted) return;
      final error = report['error'];
      if (error != null) {
        setState(() => _error = l10n.deleteFailed(error.toString()));
        return;
      }
      final failed = report['failed_paths'];
      final failedCount = failed is List ? failed.length : 0;
      final freedAfter = (report['freed_bytes'] as num?)?.toInt() ?? 0;
      final deletedCount =
          (report['deleted_count'] as num?)?.toInt() ??
          (targets.length - failedCount);
      unawaited(
        Analytics.instance.track(AnalyticsEvents.aiDeletionConfirmed, {
          'suggested_count': targets.length,
          'deleted_count': deletedCount,
          'freed_mb': freedAfter / 1e6,
        }),
      );
      if (failedCount > 0) {
        setState(() {
          _error = l10n.deleteSuccessWithFailures(failedCount, _fmt(freedAfter));
        });
        return;
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = l10n.deleteFailed(e.toString()));
    }
  }

  void _toggle(String path, bool? value) {
    setState(() {
      if (value == true) {
        _selected.add(path);
      } else {
        _selected.remove(path);
      }
    });
  }

  int get _selectedBytes {
    var sum = 0;
    for (final p in _selected) {
      sum += _sizeByPath[p] ?? 0;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: v.canvasParchment,
      appBar: AppBar(
        title: Text(l10n.aiAnalysisTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          tooltip: l10n.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.error => _ErrorBody(
          message: _error ?? l10n.aiErrorUnknown,
          retryLabel: l10n.aiActionRetry,
          onRetry: _bootstrap,
        ),
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
        _Phase.precheck => _buildPrecheck(v),
        _Phase.results => _buildResults(v),
      },
    );
  }

  Widget _buildPrecheck(VolwardTokens v) {
    final l10n = context.l10n;
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
              Text(
                l10n.aiPreCheckSafeTitle(_preClassified.length),
                style: AppleTypography.tagline.copyWith(color: v.ink),
              ),
              const SizedBox(height: AppleSpacing.xs),
              Text(
                l10n.aiPreCheckUnknownTitle(
                  _unknown.length,
                  _estimatedTokens,
                ),
                style: AppleTypography.body.copyWith(color: v.inkMuted80),
              ),
              if (_truncated) ...[
                const SizedBox(height: AppleSpacing.xs),
                Text(
                  l10n.aiTruncatedNotice(_unknown.length, _candidatesBeforeCap),
                  style: AppleTypography.caption.copyWith(color: v.warning),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppleSpacing.sm),
                Text(
                  _error!,
                  style: AppleTypography.caption.copyWith(color: v.danger),
                ),
              ],
              if (!_hasProvider) ...[
                const SizedBox(height: AppleSpacing.sm),
                Text(
                  VolwardSession.instance != null &&
                          !VolwardSession.instance!.hasAiContractApi
                      ? l10n.aiContractUnavailable
                      : l10n.aiNoApiKey,
                  style: AppleTypography.caption.copyWith(color: v.warning),
                ),
              ],
              const SizedBox(height: AppleSpacing.lg),
              if (_preClassified.isNotEmpty) ...[
                Text(
                  l10n.aiPreCheckSafeSelectable(_preClassified.length),
                  style: AppleTypography.captionStrong.copyWith(color: v.ink),
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
                    label: l10n.scanActionCancel,
                    variant: AppleButtonVariant.pearl,
                    expanded: true,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                if (_hasExistingResult) ...[
                  const SizedBox(width: AppleSpacing.sm),
                  Expanded(
                    child: AppleButton(
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
                    label: l10n.aiStartAnalysis,
                    expanded: true,
                    onPressed: _hasProvider ? _startAnalysis : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _preClassifiedTile(Map<String, dynamic> e) {
    final path = e['path'] as String? ?? '';
    final deletable = e['deletable'] == true;
    final confidence = e['confidence']?.toString() ?? '';
    final reason = e['reason']?.toString() ?? '';
    final size = _asInt(e['size_bytes']);
    final checked = _selected.contains(path);

    return CheckboxListTile(
      value: deletable ? checked : false,
      onChanged: deletable ? (val) => _toggle(path, val) : null,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: Text(path, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_fmt(size)} · $confidence'
        '${reason.isNotEmpty ? ' · $reason' : ''}',
      ),
    );
  }

  Widget _buildResults(VolwardTokens v) {
    final l10n = context.l10n;
    final safe = _verdicts
        .where((x) => x.verdict == 'safe_to_remove')
        .toList();
    final review = _verdicts
        .where((x) => x.verdict == 'review_needed')
        .toList();
    final keep = _verdicts.where((x) => x.verdict == 'keep').toList();

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
              Text(
                l10n.aiAnalysisTitle,
                style: AppleTypography.tagline.copyWith(color: v.ink),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppleSpacing.sm),
                Text(
                  _error!,
                  style: AppleTypography.caption.copyWith(color: v.danger),
                ),
              ],
              const SizedBox(height: AppleSpacing.lg),
              if (_preClassified.isNotEmpty) ...[
                Text(
                  l10n.aiPreCheckSafeSelectable(_preClassified.length),
                  style: AppleTypography.captionStrong.copyWith(color: v.ink),
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
              label:
                  '${l10n.aiDeleteSelected(_selected.length)} (${_fmt(_selectedBytes)})',
              expanded: true,
              onPressed: _selected.isEmpty ? null : _deleteSelected,
            ),
          ),
        ),
      ],
    );
  }

  Widget _verdictSection({
    required String title,
    required List<AiVerdict> items,
    required bool selectable,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    final v = context.volward;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppleTypography.captionStrong.copyWith(color: v.ink),
        ),
        const SizedBox(height: AppleSpacing.xs),
        ...items.map((item) {
          final size = _sizeByPath[item.path] ?? 0;
          if (!selectable) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.lock_outline, size: 20, color: v.inkMuted48),
              title: Text(
                item.path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${_fmt(size)} · ${item.reason}'),
            );
          }
          return CheckboxListTile(
            value: _selected.contains(item.path),
            onChanged: (val) => _toggle(item.path, val),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(
              item.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_fmt(size)} · ${item.confidence} · ${item.reason}',
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
    final v = context.volward;
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
                    style: AppleTypography.body.copyWith(color: v.danger),
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
