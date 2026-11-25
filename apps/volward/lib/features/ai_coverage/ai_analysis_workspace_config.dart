import 'package:flutter/foundation.dart';

import '../../ai/ai_analysis_gateway.dart';
import '../../ai/ai_coverage_coordinator.dart';
import '../../ai/coverage_job_state.dart';
import 'ports/workspace_ports.dart';
import 'views/ai_analysis_workspace_messages.dart';
import 'views/ai_analysis_workspace_presenter.dart';

/// Immutable widget inputs consumed by the AI workspace controller.
final class AiAnalysisWorkspaceConfig {
  const AiAnalysisWorkspaceConfig({
    required this.snapshotId,
    required this.targetLabel,
    required this.onExit,
    required this.onOpenSettings,
    required this.onDeletingChanged,
    required this.onDeleteCompleted,
    this.gateway = const ProductionAiAnalysisGateway(),
    this.coverageJobs,
    this.coverageOwner,
    this.ports,
    this.debugCoverageJobState,
    this.onOpenDetailPage,
    this.presenter,
    this.messages,
    this.onResetResultsScroll,
    this.onClearResultsSearch,
  });

  final String snapshotId;
  final String targetLabel;
  final VoidCallback onExit;
  final VoidCallback onOpenSettings;
  final ValueChanged<bool> onDeletingChanged;
  final VoidCallback onDeleteCompleted;
  final AiAnalysisGateway gateway;
  final AiCoverageJobs? coverageJobs;
  final Object? coverageOwner;
  final AiWorkspacePorts? ports;

  final CoverageJobState? debugCoverageJobState;

  final ValueChanged<String>? onOpenDetailPage;

  final AiAnalysisWorkspacePresenter? presenter;

  final AiAnalysisWorkspaceMessages? messages;

  final VoidCallback? onResetResultsScroll;

  final VoidCallback? onClearResultsSearch;
}
