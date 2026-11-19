import 'dart:async';

import '../ai_analysis_workspace_config.dart';
import '../models/ai_analysis_workspace_display_state.dart';
import '../ports/workspace_ports.dart';
import '../views/ai_analysis_workspace_view_state.dart';
import 'ai_analysis_workspace_page_surface.dart';

void workspaceResetForBootstrap(AiAnalysisWorkspacePageSurface surface) {
  surface.resetResultsScroll();
  surface.mutate(() {
    surface.invalidateResultGroups();
    surface.resetResultsPresentation();
    surface.setDisplayPhase(AiWorkspaceDisplayState.results);
    surface.resultsView = WorkspaceResultsView.overview;
    surface.error = null;
    surface.resultsController.reset();
    surface.coverageController.lastVerdictRefreshAt = null;
    surface.analyzing = false;
    surface.deleteController.reset();
    surface.coverageController.jobState = null;
    surface.coverageController.verdictByteOffset = 0;
    surface.coverageController.verdictPageCount = 2;
    surface.coverageController.hydrating = false;
    surface.coverageController.hydrated = false;
    surface.coverageController.budgetCredits = null;
    surface.coverageController.estimatedCredits = null;
    surface.coverageController.planSummary = null;
    surface.coverageController.runBudgetCredits = null;
    surface.coverageController.verdictRows = const [];
    surface.coverageController.userEngagedFullRun = false;
    surface.coverageController.uiPrefersAnalyzingPhase = false;
    surface.coverageController.stalePausedUpdatedAtMs = null;
    surface.coverageController.planBannerLoadAttempted = false;
    surface.coverageController.planLoadInFlight = false;
    surface.coverageController.planLoadError = null;
    surface.coverageController.pauseInFlight = false;
    unawaited(surface.invalidateConclusionNarrative());
  });
}

/// Context-free lifecycle orchestration for the workspace page surface.
void workspaceUpdateConfig(
  AiAnalysisWorkspacePageSurface surface,
  AiAnalysisWorkspaceConfig oldPage,
) {
  final page = surface.page;
  final previousJobs = surface.coverageJobs;
  if (oldPage.ports != page.ports ||
      oldPage.coverageJobs != page.coverageJobs) {
    surface.ports =
        page.ports ??
        AiWorkspacePorts.fromCoverageJobs(coverageJobs: page.coverageJobs);
  }
  final coverageJobsChanged = !identical(previousJobs, surface.coverageJobs);
  final previousOwnerId =
      oldPage.coverageOwner?.toString() ?? oldPage.snapshotId;
  final nextOwnerId = page.coverageOwner?.toString() ?? page.snapshotId;
  final coverageOwnerChanged =
      coverageJobsChanged || previousOwnerId != nextOwnerId;
  if (coverageOwnerChanged) {
    surface.bootstrapController.rebind(nextOwnerId, page: page);
  } else {
    surface.bootstrapController.updateConfig(page);
  }
  surface.coverageController.configure(
    jobs: surface.ports.coverageJobs,
    settings: surface.ports.settings,
    snapshotId: page.snapshotId,
    coverageOwner: page.coverageOwner,
  );
  surface.resultsController.configure(
    settings: surface.ports.settings,
    ownerId: nextOwnerId,
  );
  surface.deleteController.configure(ownerId: nextOwnerId);
  if (coverageJobsChanged) {
    previousJobs.removeJobStateListener(surface.onCoverageJobState);
    surface.coverageJobs.addJobStateListener(surface.onCoverageJobState);
  }
  if (coverageOwnerChanged) {
    surface.jobStateCoalesceTimer?.cancel();
    surface.jobStateCoalesceTimer = null;
    surface.pendingCoverageJobState = null;
  }
  if (coverageOwnerChanged || oldPage.snapshotId != page.snapshotId) {
    if (oldPage.snapshotId != page.snapshotId &&
        oldPage.snapshotId.isNotEmpty) {
      surface.ports.candidateCache.clearSnapshot(oldPage.snapshotId);
    }
    unawaited(surface.runBootstrap());
    return;
  }
  if (oldPage.gateway != page.gateway) {
    unawaited(surface.runBootstrapPrecheckContext(surface.beginOperation()));
  }
}
