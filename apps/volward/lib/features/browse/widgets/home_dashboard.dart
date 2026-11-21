import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../ai/ai_analysis_gateway.dart';
import '../../../ai/ai_coverage_coordinator.dart';
import '../../../storage_home_summary.dart';
import '../../../storage_overview.dart';
import '../../../updater/app_updater.dart';
import '../../../widgets/storage_steward_home.dart';
import '../../scan/scan_session_types.dart';

/// Production home dashboard section.
class HomeDashboard extends StatelessWidget {
  const HomeDashboard({
    super.key,
    required this.summary,
    required this.scanProgress,
    required this.revision,
    required this.aiSnapshotId,
    required this.aiAnalysisGateway,
    required this.coverageJobs,
    required this.coverageOwner,
    required this.onAiDeleteCompleted,
    required this.onOpenDetailPage,
    required this.onBrowse,
    required this.onChooseFolder,
    required this.onSelectTarget,
    required this.onScan,
    required this.onCancelScan,
    required this.onOpenSettings,
    required this.onSelectCategory,
    required this.onOpenItem,
    required this.updater,
    this.storageHomeKey,
  });

  final StorageHomeSummary Function(ScanProgressViewState progress) summary;
  final ValueListenable<ScanProgressViewState> scanProgress;
  final ValueListenable<int> revision;
  final String? aiSnapshotId;
  final AiAnalysisGateway aiAnalysisGateway;
  final AiCoverageJobs? coverageJobs;
  final Object? coverageOwner;
  final VoidCallback onAiDeleteCompleted;
  final ValueChanged<String> onOpenDetailPage;
  final VoidCallback onBrowse;
  final VoidCallback onChooseFolder;
  final ValueChanged<StorageLocationInfo> onSelectTarget;
  final VoidCallback? onScan;
  final VoidCallback? onCancelScan;
  final VoidCallback onOpenSettings;
  final ValueChanged<String> onSelectCategory;
  final ValueChanged<StorageHomeItem> onOpenItem;
  final AppUpdater updater;
  final Key? storageHomeKey;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ScanProgressViewState>(
      valueListenable: scanProgress,
      builder: (context, progress, _) {
        return ValueListenableBuilder<int>(
          valueListenable: revision,
          builder: (context, _, _) {
            return StorageStewardHome(
              key: storageHomeKey,
              summary: summary(progress),
              aiSnapshotId: aiSnapshotId,
              aiAnalysisGateway: aiAnalysisGateway,
              coverageJobs: coverageJobs,
              coverageOwner: coverageOwner,
              onAiDeleteCompleted: onAiDeleteCompleted,
              onOpenDetailPage: onOpenDetailPage,
              onBrowse: onBrowse,
              onChooseFolder: onChooseFolder,
              onSelectTarget: onSelectTarget,
              onScan: onScan,
              onCancelScan: onCancelScan,
              onOpenSettings: onOpenSettings,
              onSelectCategory: onSelectCategory,
              onOpenItem: onOpenItem,
              updater: updater,
            );
          },
        );
      },
    );
  }
}
