import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../../ai/ai_debug_log.dart';
import '../../../ai/ai_provider.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../analytics/analytics_events.dart';
import '../../../ai/byok_ai_provider.dart';
import '../../../ai/platform_ai_provider.dart';
import '../../../snapshot_cache.dart';
import '../models/ai_analysis_workspace_display_state.dart';
import '../ports/workspace_ports.dart';
import 'ai_analysis_coverage_start_flow.dart';
import 'ai_analysis_workspace_presentation_prep.dart';
import 'ai_analysis_workspace_reporting_flow.dart';
import 'ai_analysis_workspace_result_helpers.dart';

/// Context-free bridge for the quick-analysis and bootstrap/result
/// application orchestration. The page controller keeps narrow accessors and
/// delegates the method bodies to this module.
abstract interface class AiQuickFlowHost implements AiCoverageStartFlowHost {
  int beginOperation();
  int get heavyResultsLayoutThreshold;
  WorkspaceAnalyticsPort get analytics;

  void resetForBootstrap();
  void setScopeExpandedManual(bool? value);
  void setLoadedEmptySuggestions(bool value);
  Future<void> invalidateConclusionNarrative();
  Future<void> startFullCoverageAnalysis();
}

Map<String, CandidateCleanupMeta> quickCandidateCleanupMetaByPath(
  Map<String, AiCandidate> unknownByPath,
) {
  return {
    for (final entry in unknownByPath.entries)
      entry.key: CandidateCleanupMeta(
        cleanupSource: entry.value.cleanupSource,
        cleanupHint: entry.value.cleanupHint,
        retentionDays: entry.value.retentionDays,
      ),
  };
}

Future<String?> quickLoadSavedAnalysisRaw({
  required String cacheKey,
  required String snapshotId,
}) async {
  final keys = <String>{
    if (cacheKey.isNotEmpty) cacheKey,
    if (snapshotId.isNotEmpty) snapshotId,
  }.toList(growable: false);
  if (keys.isEmpty) return null;
  final cacheRoot = SnapshotCache.cacheDir().path;
  return Isolate.run(() => readAnalysisJsonFromCacheRoot(cacheRoot, keys));
}

Future<void> quickBootstrap(AiQuickFlowHost host) async {
  host.resetForBootstrap();
  int? generation;
  try {
    await host.bootstrap.initialize();
    generation = host.bootstrap.lastGeneration;
    final currentGeneration = generation;
    if (currentGeneration == null || !host.isCurrent(currentGeneration)) {
      return;
    }
    unawaited(host.loadNarrativeSettings());
    final mode = host.bootstrap.mode;
    final platformCredits = host.bootstrap.platformCredits;
    if (host.disposed) return;
    final l10n = host.messages.l10n;
    final fullCoverageAvailable = host.coverageJobs.isAvailable;
    volwardAiDebugLog(
      'workspace bootstrap pre-candidates snapshot=${host.snapshotId} '
      'fullCoverageAvailable=$fullCoverageAvailable '
      'sessionReady=${host.coverageAccess.sessionReady} '
      'sessionCoverage=${host.coverageAccess.hasCoverageApi}',
    );
    host.mutate(() {
      host.phase = AiWorkspaceDisplayState.results;
      host.setResultsViewOverview();
      host.coverage.useFullCoverage = fullCoverageAvailable;
      host.coverage.hydrating = false;
      host.coverage.hydrated = !fullCoverageAvailable;
    });
    final raw = host.bootstrap.candidatesRaw;
    volwardAiDebugLog(
      'workspace awaiting native buildCandidates snapshot=${host.snapshotId} '
      'buildCandidates returned len=${raw?.length ?? 0} '
      'prefix=${raw == null || raw.isEmpty ? "null" : (raw.length > 48 ? "${raw.substring(0, 48)}…" : raw)}',
    );
    if (!host.isCurrent(currentGeneration)) return;
    if (raw == null || raw.isEmpty) {
      host.mutate(() {
        host.phase = AiWorkspaceDisplayState.error;
        final bootstrapError = host.bootstrap.error;
        host.error =
            bootstrapError == null || bootstrapError == 'native_unavailable'
            ? l10n.aiErrorNativeUnavailable
            : bootstrapError;
      });
      return;
    }
    if (raw.startsWith('error:')) {
      host.mutate(() {
        host.phase = AiWorkspaceDisplayState.error;
        host.error = raw;
      });
      return;
    }
    if (host.bootstrap.error != null) {
      host.mutate(() {
        host.phase = AiWorkspaceDisplayState.error;
        host.error = host.bootstrap.error;
      });
      return;
    }
    if (!host.isCurrent(currentGeneration)) return;
    final preserveInteractivePhase =
        host.phase == AiWorkspaceDisplayState.results ||
        host.phase == AiWorkspaceDisplayState.deleting ||
        host.phase == AiWorkspaceDisplayState.analyzing;
    host.mutate(() {
      host.bootstrap.markExistingResult(
        host.bootstrap.hasExistingResult || host.verdicts.isNotEmpty,
      );
      if (preserveInteractivePhase && host.verdicts.isNotEmpty) {
        host.resultsController.replaceVerdicts(
          host.verdicts
              .map(
                (verdict) =>
                    withCandidateMeta(verdict, host.bootstrap.unknownByPath),
              )
              .toList(growable: false),
        );
      }
      host.invalidateResultGroups();
      if (!preserveInteractivePhase) {
        host.resultsController.setSelectedPaths(
          host.bootstrap.initialSelectedPaths,
        );
      }
      if (!preserveInteractivePhase) {
        host.phase = AiWorkspaceDisplayState.results;
        host.setResultsViewOverview();
      }
      host.coverage.useFullCoverage = host.coverageJobs.isAvailable;
      host.coverage.hydrated = !host.coverage.useFullCoverage;
    });
    volwardAiDebugLog(
      'workspace bootstrap post-candidates useFullCoverage=${host.coverage.useFullCoverage} '
      'unknown=${host.bootstrap.unknownTotalCount ?? host.bootstrap.unknown.length} '
      'preClassified=${host.bootstrap.preClassifiedTotalCount ?? host.bootstrap.preClassified.length} '
      'truncated=${host.bootstrap.truncated} candidatesError=${raw.startsWith('error:') ? raw : 'none'}',
    );
    if (host.disposed) return;
    host.presenter?.schedulePostFrame(() {
      if (!host.isCurrent(currentGeneration) || host.disposed) return;
      if (preserveInteractivePhase &&
          (host.verdicts.isNotEmpty || host.analyzing || host.deleting)) {
        return;
      }
      final fullCoverageReady = host.coverageJobs.isAvailable;
      if (fullCoverageReady && !host.coverage.useFullCoverage) {
        volwardAiDebugLog(
          'workspace promoting Quick→Full after session became available',
        );
        host.mutate(() {
          host.coverage.useFullCoverage = true;
          host.coverage.hydrated = false;
        });
      }
      if (!fullCoverageReady && !host.coverage.useFullCoverage) {
        unawaited(
          coverageMaybeAutoRestorePreviousSession(host, currentGeneration),
        );
        return;
      }
      unawaited(() async {
        await coverageSyncActiveJobAfterPrecheck(host, currentGeneration);
        if (!host.coverageJobs.isAvailable) {
          await coverageMaybeAutoRestorePreviousSession(
            host,
            currentGeneration,
          );
          return;
        }
        await coverageHydratePrecheck(
          host,
          generation: currentGeneration,
          mode: mode,
          platformCredits: platformCredits,
        );
        await coverageMaybeAutoRestorePreviousSession(host, currentGeneration);
      }());
    });
  } catch (error) {
    if (generation != null && !host.isCurrent(generation)) return;
    host.mutate(() {
      host.phase = AiWorkspaceDisplayState.error;
      host.error = error.toString();
    });
  }
}

/// Refreshes mode, provider, quota and coverage plan estimate without
/// rebuilding candidates.
Future<void> quickBootstrapPrecheckContext(
  AiQuickFlowHost host,
  int generation,
) async {
  if (!host.isCurrent(generation) || host.disposed) return;
  if (host.bootstrap.candidatesPending) return;
  try {
    final refreshed = await host.bootstrap.refreshPrecheckContext(
      generation: generation,
    );
    if (!refreshed || !host.isCurrent(generation) || host.disposed) return;
    unawaited(host.loadNarrativeSettings());
    final mode = host.bootstrap.mode;
    final platformCredits = host.bootstrap.platformCredits;
    if (host.phase == AiWorkspaceDisplayState.analyzing ||
        host.phase == AiWorkspaceDisplayState.results ||
        host.phase == AiWorkspaceDisplayState.deleting) {
      return;
    }
    if (!host.coverageJobs.isAvailable) return;
    await coverageHydratePrecheck(
      host,
      generation: generation,
      mode: mode,
      platformCredits: platformCredits,
    );
  } catch (error) {
    if (!host.isCurrent(generation) || host.disposed) return;
    volwardAiDebugLog('bootstrapPrecheckContext error=$error');
  }
}

Future<bool> quickLoadPreviousResult(
  AiQuickFlowHost host, {
  int? bootstrapGeneration,
}) async {
  final generation = bootstrapGeneration ?? host.beginOperation();
  final l10n = host.messages.l10n;
  if (bootstrapGeneration == null) {
    host.mutate(() => host.error = null);
  }
  await host.bootstrap.loadPreviousResult(generation: generation);
  if (!host.isCurrent(generation)) return false;
  return quickApplyLoadedResult(
    host,
    host.bootstrap.previousResultRaw,
    l10n.aiLoadPreviousFailed,
    generation,
    bootstrapGeneration: bootstrapGeneration,
  );
}

Future<bool> quickApplyLoadedResult(
  AiQuickFlowHost host,
  String? raw,
  String failureMessage,
  int generation, {
  int? bootstrapGeneration,
}) async {
  if (raw == null || raw.isEmpty || raw.startsWith('error:')) {
    if (!host.isCurrent(generation)) return false;
    if (bootstrapGeneration == null) {
      host.mutate(() {
        host.error = failureMessage;
        host.enterOverviewHub();
      });
    }
    return false;
  }
  try {
    final parsed = await compute(parseLoadedAnalysisJsonString, raw);
    if (!host.isCurrent(generation)) return false;
    host.bootstrap.addSizes(parsed.resultSizes);
    host.bootstrap.updateRootPath(parsed.loadedRootPath);
    final verdicts = await compute(
      buildLoadedVerdicts,
      LoadedVerdictsBuildInput(
        entryMaps: parsed.entryMaps,
        candidateMetaByPath: quickCandidateCleanupMetaByPath(
          host.bootstrap.unknownByPath,
        ),
      ),
    );
    if (!host.isCurrent(generation)) return false;
    if (host.analyzing) return false;
    if (verdicts.length >= host.heavyResultsLayoutThreshold) {
      host.mutate(() {
        host.resetResultsPresentation();
        host.resultsController.reset();
        host.error = null;
        host.enterResultsPhase(showOverview: true);
      });
      await host.applyHeavyResultsPresentation(
        verdicts: verdicts,
        preserveUiState: false,
        savedReview: null,
        savedSelected: null,
        savedExpandedGroups: null,
        savedExpandedReviews: null,
      );
      if (!host.isCurrent(generation)) return false;
      unawaited(host.maybeRunConclusionNarrative(fresh: false));
      return true;
    }
    host.mutate(() {
      host.resetResultsPresentation();
      host.resultsController.applyVerdicts(
        verdicts,
        selectedPaths: selectedPathsForResults(
          verdicts: verdicts,
          preClassified: host.bootstrap.preClassified,
          reviewDecisions: host.resultsController.reviewDecisions,
        ),
      );
      host.invalidateResultGroups();
      host.resultsController.setExpandedGroupPaths(
        host.defaultExpandedGroupPaths(),
      );
      host.bootstrap.markExistingResult(true);
      host.setLoadedEmptySuggestions(verdicts.isEmpty);
      host.error = null;
      host.enterResultsPhase(showOverview: true);
    });
    unawaited(host.maybeRunConclusionNarrative(fresh: false));
    return true;
  } catch (_) {
    if (!host.isCurrent(generation)) return false;
    host.mutate(() {
      host.error = failureMessage;
      host.enterOverviewHub();
    });
    return false;
  }
}

Future<void> quickStartAnalysis(AiQuickFlowHost host) async {
  if (!host.bootstrap.hasProvider || host.analyzing) return;
  final entryGeneration = host.operationGeneration;
  await host.ensureUnknownCandidatesLoaded();
  if (!host.isCurrent(entryGeneration)) return;
  if (host.coverage.useFullCoverage) {
    volwardAiDebugLog(
      'startAnalysis → Full coverage snapshot=${host.snapshotId} '
      'hydrated=${host.coverage.hydrated} planLocalOnly=${host.coverage.planSummary == null ? false : true}',
    );
    await host.startFullCoverageAnalysis();
    return;
  }
  final generation = host.beginOperation();
  if (!await coverageEnsurePrivacyAccepted(host, generation)) return;
  if (!host.isCurrent(generation)) return;
  final provider = await host.gateway.resolveProvider();
  if (!host.isCurrent(generation)) return;
  if (provider == null) {
    host.bootstrap.setProviderAvailable(false);
    return;
  }
  host.mutate(() {
    host.analyzing = true;
    host.phase = AiWorkspaceDisplayState.results;
    host.setResultsViewOverview();
    host.setScopeExpandedManual(false);
    host.error = null;
    host.setLoadedEmptySuggestions(false);
  });
  final mode = await host.gateway.getMode();
  if (!host.isCurrent(generation)) return;
  final providerLabel = mode == AiMode.platform ? 'platform' : 'byok';
  final stopwatch = Stopwatch()..start();
  var byokUsageRecorded = false;
  unawaited(
    host.analytics.track(AnalyticsEvents.aiAnalysisStarted, {
      'provider': providerLabel,
      'candidate_count':
          host.bootstrap.unknownTotalCount ?? host.bootstrap.unknown.length,
    }),
  );
  try {
    final result = await provider.analyze(host.bootstrap.unknown);
    final verdicts = result.verdicts;
    final model = provider is ByokAiProvider
        ? provider.model
        : 'deepseek-v4-flash';
    final byokUsage = provider is ByokAiProvider
        ? provider.lastTokenUsage
        : null;
    final inputTokens =
        byokUsage?.promptTokens ??
        (host.bootstrap.estimatedTokens > 0
            ? host.bootstrap.estimatedTokens
            : (host.bootstrap.unknown.length * 8 + 200));
    final outputTokens = byokUsage?.completionTokens ?? verdicts.length * 40;
    final totalTokens = byokUsage?.totalTokens ?? inputTokens + outputTokens;
    if (provider is ByokAiProvider) {
      await recordByokTokenUsage(
        gateway: host.gateway,
        analytics: host.analytics,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: totalTokens,
        estimated: !provider.hasReliableTokenUsage,
        partial: false,
      );
      byokUsageRecorded = true;
    }
    if (!host.isCurrent(generation)) return;
    final cost = (inputTokens / 1e6) * 0.14 + (outputTokens / 1e6) * 0.28;
    final enrichedVerdicts = verdicts
        .map(
          (verdict) => withCandidateMeta(verdict, host.bootstrap.unknownByPath),
        )
        .toList();
    final sizeByPath = host.bootstrap.sizeByPath;
    final entries = enrichedVerdicts
        .map(
          (verdict) => {
            'path': verdict.path,
            'size_bytes': sizeByPath[verdict.path] ?? 0,
            'verdict': verdict.verdict,
            'confidence': verdict.confidence,
            'reason': verdict.reason,
            if (verdict.cleanupSource != null &&
                verdict.cleanupSource!.isNotEmpty)
              'cleanup_source': verdict.cleanupSource,
            if (verdict.cleanupHint != null && verdict.cleanupHint!.isNotEmpty)
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
      'snapshot_id': host.snapshotId,
      if (host.bootstrap.resultCacheKey.isNotEmpty)
        'cache_key': host.bootstrap.resultCacheKey,
      if (host.bootstrap.rootPath.isNotEmpty)
        'root_path': host.bootstrap.rootPath,
      'analyzed_at_ms': DateTime.now().millisecondsSinceEpoch,
      'mode': mode.name,
      'model': model,
      'entries': entries,
      'token_usage': {'input': inputTokens, 'output': outputTokens},
      'cost_estimate_usd': cost,
      'credits_used': creditsUsed,
    });
    if (!host.isCurrent(generation)) return;
    host.gateway.saveResult(host.snapshotId, resultJson);
    if (!host.isCurrent(generation)) return;
    unawaited(
      host.analytics.track(AnalyticsEvents.aiAnalysisCompleted, {
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
    if (!host.isCurrent(generation)) return;
    host.mutate(() {
      host.resetResultsPresentation();
      host.resultsController.applyVerdicts(
        enrichedVerdicts,
        selectedPaths: selectedPathsForResults(
          verdicts: enrichedVerdicts,
          preClassified: host.bootstrap.preClassified,
          reviewDecisions: host.resultsController.reviewDecisions,
        ),
      );
      host.invalidateResultGroups();
      host.resultsController.setExpandedGroupPaths(
        host.defaultExpandedGroupPaths(),
      );
      host.bootstrap.markExistingResult(true);
      host.setLoadedEmptySuggestions(enrichedVerdicts.isEmpty);
      host.analyzing = false;
      host.setScopeExpandedManual(null);
      host.enterResultsPhase(showOverview: true);
    });
    unawaited(() async {
      await host.loadNarrativeSettings();
      if (host.disposed) return;
      await host.maybeRunConclusionNarrative(fresh: true);
    }());
  } catch (error) {
    if (!byokUsageRecorded && provider is ByokAiProvider) {
      final partialUsage = provider.lastTokenUsage;
      if (partialUsage != null) {
        await recordByokTokenUsage(
          gateway: host.gateway,
          analytics: host.analytics,
          inputTokens: partialUsage.promptTokens,
          outputTokens: partialUsage.completionTokens,
          totalTokens: partialUsage.totalTokens,
          estimated: !provider.hasReliableTokenUsage,
          partial: true,
        );
      }
    }
    if (!host.isCurrent(generation)) return;
    final message = error.toString();
    if (message.contains('insufficient_credits')) {
      host.mutate(() {
        host.error = host.messages.l10n.aiInsufficientCredits;
        host.analyzing = false;
        host.enterOverviewHub();
        host.bootstrap.updatePlatformCredits(0);
      });
      return;
    }
    if (message.contains('session_expired')) {
      host.mutate(() {
        host.error = host.messages.l10n.aiSettingsSessionExpired;
        host.analyzing = false;
        host.bootstrap.setProviderAvailable(false);
        host.enterOverviewHub();
      });
      return;
    }
    final normalizedError = normalizeAiError(error);
    unawaited(
      host.analytics.track(AnalyticsEvents.aiAnalysisFailed, {
        'provider': providerLabel,
        'error': normalizedError,
        'duration_ms': stopwatch.elapsedMilliseconds,
      }),
    );
    if (!host.isCurrent(generation)) return;
    final configurationError = switch (normalizedError) {
      'invalid_api_key' ||
      'empty_api_key' ||
      'ai_contract_unavailable' ||
      'platform_api_unconfigured' ||
      'link_account_required' => true,
      _ => false,
    };
    host.mutate(() {
      host.analyzing = false;
      host.enterOverviewHub();
      if (configurationError) {
        host.bootstrap.setProviderAvailable(false);
      }
      host.error = localizedAiError(error, host.messages.l10n);
    });
  }
}
