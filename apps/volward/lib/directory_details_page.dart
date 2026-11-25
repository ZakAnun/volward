import 'package:flutter/material.dart';

import 'ai/ai_analysis_gateway.dart';
import 'ai/ai_coverage_coordinator.dart';
import 'features/browse/controllers/directory_details_page_base_state.dart';
import 'storage_overview_provider.dart';
import 'theme/volward_theme_settings.dart';
import 'updater/app_updater.dart';
import 'volward_session.dart';

export 'features/browse/controllers/directory_details_page_base_state.dart';

class DirectoryDetailsPage extends StatefulWidget {
  const DirectoryDetailsPage({
    super.key,
    required this.session,
    required this.themeSettings,
    required this.updater,
    this.directoryPicker,
    this.storageOverviewProvider = const MethodChannelStorageOverviewProvider(),
    this.aiAnalysisGateway = const ProductionAiAnalysisGateway(),
    this.coverageCoordinator,
  });
  final VolwardSession session;
  final VolwardThemeSettings themeSettings;
  final AppUpdater updater;
  final Future<String?> Function({required String confirmButtonText})?
  directoryPicker;
  final StorageOverviewProvider storageOverviewProvider;
  final AiAnalysisGateway aiAnalysisGateway;
  final AiCoverageCoordinator? coverageCoordinator;

  static const logoKey = Key('volward-top-nav-home');
  static const browseFolderActionKey = Key('volward-browse-folder-action');
  static const browseHomeActionKey = Key('volward-browse-home-action');

  @override
  State<DirectoryDetailsPage> createState() => _DirectoryDetailsPageState();
}

class _DirectoryDetailsPageState
    extends DirectoryDetailsPageBaseState<DirectoryDetailsPage> {
  @override
  VolwardSession get pageSession => widget.session;

  @override
  VolwardThemeSettings get pageThemeSettings => widget.themeSettings;

  @override
  AppUpdater get pageUpdater => widget.updater;

  @override
  Future<String?> Function({required String confirmButtonText})?
  get pageDirectoryPicker => widget.directoryPicker;

  @override
  StorageOverviewProvider get pageStorageOverviewProvider =>
      widget.storageOverviewProvider;

  @override
  AiAnalysisGateway get pageAiAnalysisGateway => widget.aiAnalysisGateway;

  @override
  AiCoverageCoordinator? get pageCoverageCoordinator =>
      widget.coverageCoordinator;

  @override
  VolwardSession sessionOf(DirectoryDetailsPage widget) => widget.session;

  @override
  StorageOverviewProvider storageOverviewProviderOf(
    DirectoryDetailsPage widget,
  ) => widget.storageOverviewProvider;

  @override
  AiCoverageCoordinator? coverageCoordinatorOf(DirectoryDetailsPage widget) =>
      widget.coverageCoordinator;
}
