import 'dart:async';

import '../../../ai/ai_conclusion_narrative_cache.dart';
import '../../../ai/ai_conclusion_synthesis.dart';
import '../../../ai/ai_provider.dart';
import '../../../ai/ai_result_overview.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../analytics/analytics_events.dart';
import '../../../snapshot_cache.dart';
import '../models/ai_analysis_workspace_display_state.dart';
import '../views/ai_analysis_workspace_view_state.dart';
import 'ai_analysis_delete_controller.dart';
import 'ai_analysis_quick_flow.dart';
import 'ai_analysis_results_controller.dart';
import 'ai_analysis_workspace_result_helpers.dart';

/// Narrow bridge the page controller implements so the results, narrative
/// and delete orchestration can live in this context-free module.
abstract interface class AiResultsFlowHost implements AiQuickFlowHost {
  AiAnalysisDeleteController get deleteController;

  WorkspaceResultsView get resultsView;
  set resultsView(WorkspaceResultsView value);
  bool? get scopeExpandedManual;
  set scopeExpandedManual(bool? value);
  String get targetLabel;
  String? get rootPath;
  int? get selectedBytes;
  AiResultsProjection get resultsProjection;
  AiResultOverviewBuildInput get conclusionOverviewInput;

  bool get openExternalDetailPageSupported;
  void openExternalDetailPage(String path);
  void exitHost();
  void deleteCompleted();
  void setDeleteBusy(bool busy);
  String formatBytesValue(num? bytes);
  void applyDirectoryTypeFilter(WorkspaceDirectoryTypeFilter filter);
}

Future<void> resultsLoadNarrativeSettings(AiResultsFlowHost host) async {
  await host.resultsController.loadNarrativeSettings();
}

void resultsInvalidateConclusionNarrative(AiResultsFlowHost host) {
  host.resultsController.invalidateNarrative();
}

void resultsCommitConclusionNarrative(
  AiResultsFlowHost host,
  String text,
  String hash,
) {
  host.resultsController.commitNarrative(text, hash);
}

Future<void> resultsMaybeRunConclusionNarrative(
  AiResultsFlowHost host, {
  required bool fresh,
  bool manual = false,
  AiProvider? provider,
}) async {
  final narrativeGeneration = host.resultsController.narrativeGeneration;
  bool stale() =>
      host.disposed ||
      narrativeGeneration != host.resultsController.narrativeGeneration;
  final locale = host.messages.l10n.localeName == 'zh' ? 'zh-CN' : 'en';
  if (host.verdicts.isEmpty) return;
  try {
    await resultsLoadNarrativeSettings(host);
    if (stale() || !host.resultsController.narrativeEnabled) return;
    if (host.resultsController.narrativeLoading ||
        host.resultsController.narrativeSynthesisInFlight) {
      return;
    }

    final buildInput = host.conclusionOverviewInput;
    final overview = host.resultsProjection.overview;
    if (overview.analyzedItemCount == 0) return;

    final hash = conclusionContentHash(
      overview,
      host.resultsProjection.normalizedGroups.expand((group) => group.items),
    );
    if (host.resultsController.narrativeText != null &&
        host.resultsController.narrativeSignature == hash) {
      return;
    }
    final cacheKey = host.bootstrap.resultCacheKey.isNotEmpty
        ? host.bootstrap.resultCacheKey
        : host.snapshotId;
    final cache = ConclusionNarrativeCache(SnapshotCache.cacheDir());
    final cached = await cache.read(cacheKey, hash);
    if (stale()) return;
    if (cached != null) {
      resultsCommitConclusionNarrative(host, cached, hash);
      return;
    }
    if (!manual && !(fresh && host.resultsController.narrativeAuto)) {
      return;
    }

    final resolved = provider ?? await host.gateway.resolveProvider();
    if (stale() || resolved == null) return;
    await host.resultsController.generateNarrative(
      signature: hash,
      synthesize: () async {
        if (stale()) return null;
        final request = buildConclusionSynthesisRequest(
          overview: overview,
          buildInput: buildInput,
          analysisSessionId: cacheKey,
          locale: locale,
        );
        final response = await resolved.synthesizeConclusion(request);
        final text = response.text.trim();
        if (host.disposed || stale()) return null;
        if (text.isEmpty) return null;
        await cache.write(cacheKey, hash, text);
        if (host.disposed || stale()) return null;
        return text;
      },
    );
  } catch (_) {
    // Narrative is optional; the template-only overview stays as-is.
  }
}

void resultsHandleBack(AiResultsFlowHost host) {
  if (host.resultsView == WorkspaceResultsView.reviewQueue ||
      host.resultsView == WorkspaceResultsView.detailList) {
    host.mutate(() {
      host.resultsView = WorkspaceResultsView.overview;
      host.resultsController.setDirectoryFilter(null);
      host.resultsController.clearReviewQueue();
    });
    return;
  }
  host.exitHost();
}

void resultsToggleEmbeddedScopeExpanded(AiResultsFlowHost host) {
  final expanded =
      host.scopeExpandedManual ??
      (!host.bootstrap.hasProvider ||
              (host.bootstrap.mode == AiMode.platform &&
                  (host.bootstrap.platformCredits ?? 0) == 0)
          ? true
          : host.error != null);
  host.mutate(() => host.scopeExpandedManual = !expanded);
}

void resultsEnterOverviewHub(AiResultsFlowHost host) {
  host.phase = AiWorkspaceDisplayState.results;
  host.resultsView = WorkspaceResultsView.overview;
  host.scopeExpandedManual = null;
}

void resultsEnterResultsPhase(
  AiResultsFlowHost host, {
  bool showOverview = true,
}) {
  final entering =
      host.phase != AiWorkspaceDisplayState.results &&
      host.phase != AiWorkspaceDisplayState.deleting;
  host.phase = AiWorkspaceDisplayState.results;
  if (showOverview &&
      (entering || host.resultsView == WorkspaceResultsView.overview)) {
    host.resultsView = WorkspaceResultsView.overview;
  }
}

void resultsOpenReviewQueue(AiResultsFlowHost host, {String? directoryPath}) {
  final pending = pendingReviewVerdicts(
    verdicts: host.verdicts,
    reviewDecisions: host.reviewDecisions,
    sort: host.resultSort,
    sizeByPath: host.sizeByPath,
    directoryPath: directoryPath,
  );
  host.mutate(() {
    host.resultsView = WorkspaceResultsView.reviewQueue;
    host.resultsController.setReviewQueue(
      directoryPath: directoryPath,
      initialPending: pending.length,
    );
  });
}

void resultsOpenDetailList(
  AiResultsFlowHost host, {
  WorkspaceResultFilter? initialFilter,
  String? directoryPath,
}) {
  host.mutate(() {
    host.resultsView = WorkspaceResultsView.detailList;
    host.resultsController.clearReviewQueue();
    host.resultsController.setDirectoryFilter(directoryPath);
    if (initialFilter != null) {
      host.resultsController.setFilter(initialFilter);
    }
    host.invalidateVisibleGroups();
  });
}

void resultsOpenDetailPage(AiResultsFlowHost host, {String? directoryPath}) {
  if (host.openExternalDetailPageSupported) {
    host.openExternalDetailPage(
      directoryPath != null && directoryPath.isNotEmpty
          ? directoryPath
          : host.rootPath ?? '',
    );
    return;
  }
  resultsOpenDetailList(
    host,
    initialFilter: directoryPath == null ? WorkspaceResultFilter.all : null,
    directoryPath: directoryPath,
  );
}

void resultsToggleSelection(
  AiResultsFlowHost host,
  String path,
  bool? selected,
) {
  host.resultsController.toggleSelection(path, selected);
  if (host.resultFilter == WorkspaceResultFilter.selected) {
    host.invalidateVisibleGroups();
  }
}

void resultsConfirmReviewDecision(
  AiResultsFlowHost host,
  String path,
  WorkspaceReviewDecision decision,
) {
  host.resultsController.setReviewDecision(path, decision);
  host.invalidateVisibleGroups();
}

void resultsToggleSafeGroupPaths(
  AiResultsFlowHost host,
  List<String> paths,
  bool selected,
) {
  host.resultsController.setSelectionForPaths(paths, selected);
  if (host.resultFilter == WorkspaceResultFilter.selected) {
    host.invalidateVisibleGroups();
  }
}

void resultsToggleGroupExpanded(AiResultsFlowHost host, String path) {
  host.mutate(() {
    host.resultsController.setExpandedGroup(
      path,
      !host.expandedGroupPaths.contains(path),
    );
    host.invalidateVisibleGroups();
  });
}

const _expandedGroupInitialItemCap = 120;
const _expandedGroupItemCapStep = 120;

void resultsShowMoreItemsInGroup(
  AiResultsFlowHost host,
  String groupPath,
  int total,
) {
  final current = host.resultsController.expandedGroupItemLimits[groupPath];
  final next =
      (current ?? _expandedGroupInitialItemCap) + _expandedGroupItemCapStep;
  host.mutate(() {
    host.resultsController.setExpandedGroupItemLimit(
      groupPath,
      next.clamp(0, total),
    );
    host.invalidateVisibleGroups();
  });
}

void resultsToggleReviewExpanded(AiResultsFlowHost host, String path) {
  host.mutate(() {
    final expanded = host.expandedReviewPaths.contains(path);
    if (expanded) {
      host.resultsController.setExpandedReview(path, false);
    } else {
      host.resultsController.setExpandedReviewPaths([path]);
    }
  });
}

void resultsResetFilters(AiResultsFlowHost host) {
  host.mutate(() {
    host.resultsController.setQuery('');
    host.resultsController.setDirectoryFilter(null);
    host.resultsController.setFilter(WorkspaceResultFilter.all);
    host.resultsController.setSort(WorkspaceResultSort.priority);
    host.invalidateVisibleGroups();
  });
}

void resultsBackToConclusions(AiResultsFlowHost host) {
  host.mutate(() {
    host.resultsView = WorkspaceResultsView.overview;
    host.resultsController.setDirectoryFilter(null);
    host.resultsController.clearReviewQueue();
    host.invalidateVisibleGroups();
  });
}

void resultsSetQuery(AiResultsFlowHost host, String value) {
  host.mutate(() {
    host.resultsController.setQuery(value);
    host.invalidateVisibleGroups();
  });
}

void resultsSetDirectoryFilter(AiResultsFlowHost host, String? path) {
  host.mutate(() {
    host.resultsController.setDirectoryFilter(path);
    host.invalidateVisibleGroups();
  });
}

void resultsSetFilter(AiResultsFlowHost host, WorkspaceResultFilter filter) {
  host.mutate(() {
    host.resultsController.setFilter(filter);
    host.invalidateVisibleGroups();
  });
}

void resultsSetSort(AiResultsFlowHost host, WorkspaceResultSort sort) {
  host.mutate(() {
    host.resultsController.setSort(sort);
    host.invalidateVisibleGroups();
  });
}

void resultsSetDirectoryTypeFilter(
  AiResultsFlowHost host,
  WorkspaceDirectoryTypeFilter filter,
) {
  host.mutate(() {
    host.applyDirectoryTypeFilter(filter);
    host.invalidateVisibleGroups();
  });
}

List<String> resultsDeleteTargets(AiResultsFlowHost host) {
  final retry = host.deleteController.retryTargets;
  if (retry.isNotEmpty) return List.of(retry);
  final targets = <String>{};
  for (final path in host.selected) {
    final deleteTarget = host.bootstrap.deleteTargetsByPath[path];
    if (deleteTarget != null && deleteTarget.isNotEmpty) {
      targets.add(deleteTarget);
    } else {
      targets.add(path);
    }
  }
  return targets.toList();
}

Future<void> resultsDeleteSelected(AiResultsFlowHost host) async {
  if (host.deleting) return;
  final targets = resultsDeleteTargets(host);
  if (targets.isEmpty) return;
  final stayOnOverview =
      host.phase == AiWorkspaceDisplayState.results &&
      host.resultsView == WorkspaceResultsView.overview &&
      !host.analyzing;
  final returnToOverviewHub = stayOnOverview && host.verdicts.isEmpty;
  final selectedPaths = Set<String>.from(host.selected);
  final generation = host.beginOperation();
  final l10n = host.messages.l10n;
  host.mutate(() => host.error = null);
  final Map<String, dynamic> preview;
  try {
    preview = await host.gateway.deleteEntries(
      targets,
      snapshotId: host.snapshotId,
      dryRun: true,
    );
    if (!host.isCurrent(generation)) return;
  } catch (error) {
    if (!host.isCurrent(generation)) return;
    host.mutate(() => host.error = l10n.deleteFailed(error.toString()));
    return;
  }
  final count = (preview['deleted_count'] as num?)?.toInt() ?? targets.length;
  final freed =
      (preview['freed_bytes'] as num?)?.toInt() ?? host.selectedBytes ?? 0;
  if (host.disposed) return;
  await host.deleteController.deleteSelected(
    generation: generation,
    confirm: (_) async {
      if (!host.isCurrent(generation)) return false;
      return host.messages.confirmDelete(
        count: count,
        freedLabel: host.formatBytesValue(freed),
      );
    },
    execute: (deleteGeneration) async {
      if (!host.isCurrent(deleteGeneration)) return const {'error': 'stale'};
      host.mutate(() {
        if (!stayOnOverview) {
          host.resultsView = WorkspaceResultsView.detailList;
        }
        host.phase = AiWorkspaceDisplayState.deleting;
      });
      try {
        final report = await host.gateway.deleteEntries(
          targets,
          snapshotId: host.snapshotId,
          rescanAfterDelete: true,
        );
        if (!host.isCurrent(deleteGeneration)) {
          return const {'error': 'stale'};
        }
        final error = report['error'];
        if (error != null) {
          host.mutate(() {
            host.phase = AiWorkspaceDisplayState.results;
            host.error = l10n.deleteFailed(error.toString());
          });
          return report;
        }
        final failed = report['failed_paths'];
        final failedCount = failed is List ? failed.length : 0;
        final freedAfter = (report['freed_bytes'] as num?)?.toInt() ?? 0;
        final deletedCount =
            (report['deleted_count'] as num?)?.toInt() ??
            (targets.length - failedCount);
        unawaited(
          host.analytics.track(AnalyticsEvents.aiDeletionConfirmed, {
            'suggested_count': targets.length,
            'deleted_count': deletedCount,
            'freed_mb': freedAfter / 1e6,
          }),
        );
        if (failedCount > 0) {
          host.mutate(() {
            host.phase = AiWorkspaceDisplayState.results;
            if (stayOnOverview) {
              host.resultsView = WorkspaceResultsView.overview;
            }
            host.error = l10n.aiWorkspacePartialDelete(
              failedCount,
              host.formatBytesValue(freedAfter),
            );
          });
        } else if (returnToOverviewHub) {
          host.bootstrap.removeCandidates(
            selectedPaths,
            decrementPreClassifiedBy: selectedPaths.length,
          );
          host.resultsController.removeSelectionWhere(selectedPaths.contains);
        }
        return report;
      } catch (error) {
        if (!host.isCurrent(deleteGeneration)) {
          return const {'error': 'stale'};
        }
        host.mutate(() {
          host.phase = AiWorkspaceDisplayState.results;
          if (stayOnOverview) {
            host.resultsView = WorkspaceResultsView.overview;
          }
          host.error = l10n.deleteFailed(error.toString());
        });
        return {'error': error.toString()};
      } finally {
        if (!host.disposed) {
          host.mutate(() {
            if (host.phase == AiWorkspaceDisplayState.deleting) {
              host.phase = AiWorkspaceDisplayState.results;
              if (stayOnOverview) {
                host.resultsView = WorkspaceResultsView.overview;
              }
            }
          });
        }
      }
    },
    onBusyChanged: host.setDeleteBusy,
    onCompleted: () {
      if (host.isCurrent(generation)) host.deleteCompleted();
    },
  );
}
