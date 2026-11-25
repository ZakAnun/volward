import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:volward/ai/ai_analysis_gateway.dart';
import 'package:volward/ai/ai_coverage_coordinator.dart';
import 'package:volward/features/browse/controllers/directory_browse_controller.dart';
import 'package:volward/features/browse/controllers/directory_details_actions.dart';
import 'package:volward/features/browse/controllers/directory_details_query.dart';
import 'package:volward/features/browse/controllers/scan_presentation_controller.dart';
import 'package:volward/features/browse/directory_browse_session.dart';
import 'package:volward/features/browse/scan_sort_mode.dart';
import 'package:volward/features/browse/widgets/browse_body.dart';
import 'package:volward/features/browse/widgets/directory_browse_results.dart';
import 'package:volward/features/browse/widgets/directory_page_scaffold.dart';
import 'package:volward/features/browse/widgets/directory_permission_banner.dart';
import 'package:volward/features/browse/widgets/directory_restore_loading.dart';
import 'package:volward/features/browse/widgets/directory_scan_section.dart';
import 'package:volward/features/browse/widgets/directory_sticky_section.dart';
import 'package:volward/features/browse/widgets/directory_top_nav.dart';
import 'package:volward/features/browse/widgets/home_dashboard.dart';
import 'package:volward/features/scan/scan_lifecycle.dart';
import 'package:volward/l10n/l10n.dart';
import 'package:volward/linux_desktop_integration.dart';
import 'package:volward/macos_settings.dart';
import 'package:volward/scan_tree_navigation.dart';
import 'package:volward/settings/settings_file.dart';
import 'package:volward/settings_page.dart';
import 'package:volward/storage_overview.dart';
import 'package:volward/storage_overview_provider.dart';
import 'package:volward/theme/volward_theme_settings.dart';
import 'package:volward/theme/volward_tokens.dart';
import 'package:volward/updater/app_updater.dart';
import 'package:volward/volward_session.dart';
import 'package:volward/widgets/home/dashboard_theme.dart';
import 'package:volward/widgets/top_toast.dart';
import 'directory_details_helpers.dart';
import 'directory_details_ports.dart';

export 'directory_details_helpers.dart';

@visibleForTesting
enum SessionUiFlush { none, homeSummary, browseResults, page }

@visibleForTesting
SessionUiFlush sessionUiFlushFor({
  required bool snapshotIdChanged,
  required bool catalogChanged,
  required bool targetPreviewChanged,
  required bool deletingChanged,
  required bool refreshingChanged,
  required bool postDeleteRefreshChanged,
  required bool scanStarted,
  required bool scanStopped,
  bool browseResultsLayoutChanged = false,
}) {
  if (scanStarted ||
      scanStopped ||
      targetPreviewChanged ||
      deletingChanged ||
      refreshingChanged ||
      postDeleteRefreshChanged) {
    return SessionUiFlush.page;
  }
  if (snapshotIdChanged || catalogChanged) {
    if (browseResultsLayoutChanged) {
      return SessionUiFlush.page;
    }
    return SessionUiFlush.browseResults;
  }
  return SessionUiFlush.none;
}

enum _HomeContentMode { home, browse }

/// Orchestrates the directory page: session wiring, navigation, listens and
/// composition. Query behavior lives in [DirectoryQueryController], actions in
/// [DirectoryDetailsActionsController], rendering in the section widgets.
abstract class DirectoryDetailsPageBaseState<T extends StatefulWidget>
    extends State<T>
    with WidgetsBindingObserver
    implements DirectoryDetailsActionState {
  static const logoKey = Key('volward-top-nav-home');
  static const browseFolderActionKey = Key('volward-browse-folder-action');
  static const browseHomeActionKey = Key('volward-browse-home-action');

  VolwardSession get pageSession;
  VolwardThemeSettings get pageThemeSettings;
  AppUpdater get pageUpdater;
  Future<String?> Function({required String confirmButtonText})?
  get pageDirectoryPicker;
  StorageOverviewProvider get pageStorageOverviewProvider;
  AiAnalysisGateway get pageAiAnalysisGateway;
  AiCoverageCoordinator? get pageCoverageCoordinator;
  VolwardSession sessionOf(T widget);
  StorageOverviewProvider storageOverviewProviderOf(T widget);
  AiCoverageCoordinator? coverageCoordinatorOf(T widget);

  final DirectoryBrowseController _directoryBrowseController =
      DirectoryBrowseController();
  final ScanPresentationController _scanPresentationController =
      ScanPresentationController();

  bool _permissionBannerExpanded = false;
  bool _hasValidRoot = false;
  _HomeContentMode _contentMode = _HomeContentMode.home;
  final GlobalKey _storageHomeKey = GlobalKey(
    debugLabel: 'storage-steward-home',
  );
  Completer<bool> _startupRootGate = Completer<bool>();
  StorageOverviewData _storageOverview = const StorageOverviewData.loading();
  String? _homeTargetPath;
  List<StorageLocationInfo> _recentCustomLocations = const [];
  int _overviewLoadGeneration = 0;
  bool _scanStartPending = false;
  bool _targetPreparationPending = false;
  int _scanStartGeneration = 0;

  late VolwardSession _subscribedSession;
  late ProductionAiAnalysisGateway _sessionAiGateway;
  AiCoverageCoordinator? _coverageCoordinator;
  bool _ownsCoverageCoordinator = false;
  int _sessionGeneration = 0;
  VolwardSession? _startupPendingSession;
  int? _startupPendingGeneration;
  int? _prefetchScheduledGeneration;
  String? _lastObservedSessionError;

  bool _lastDeleting = false;
  int _lastRefreshingDirectoryCount = 0;
  bool _lastTargetPreviewLoading = false;
  bool _lastPostDeleteRefreshPending = false;
  bool _prevScanning = false;
  bool _lastHasResults = false;
  String? _lastRefreshedSnapshotId;
  int _lastRefreshedCatalogVersion = -1;

  late final DirectoryQueryController _query = DirectoryQueryController(
    session: pageSession,
    browse: pageSession,
    browseController: _directoryBrowseController,
    scanPresentationController: _scanPresentationController,
    isMounted: () => mounted,
    applySetState: _setState,
    l10n: () => context.l10n,
  );

  late final DirectoryDetailsActionsController _actions =
      DirectoryDetailsActionsController(
        session: pageSession,
        scan: pageSession,
        browse: pageSession,
        deletion: pageSession,
        state: this,
        browseController: _directoryBrowseController,
        query: _query,
        isMounted: () => mounted,
        applySetState: _setState,
        l10n: () => context.l10n,
        showConfirm: (dialog) =>
            showDialog<bool>(context: context, builder: (_) => dialog),
        showToast: (message, type) =>
            showTopToast(context, message: message, type: type),
        attachedSession: () => _subscribedSession,
        isStartupPendingFor: (session) =>
            session is VolwardSession && _isStartupPendingFor(session),
        loadOverview: (path) => unawaited(_loadStorageOverview(path)),
        directoryPicker: pageDirectoryPicker,
      );

  AiAnalysisGateway get _aiGateway {
    final gateway = pageAiAnalysisGateway;
    if (gateway.runtimeType == ProductionAiAnalysisGateway &&
        gateway is ProductionAiAnalysisGateway &&
        !identical(gateway.session, _subscribedSession)) {
      return _sessionAiGateway;
    }
    return gateway;
  }

  String? get _scanStatus => _scanPresentationController.scanStatus;
  set _scanStatus(String? value) =>
      _scanPresentationController.scanStatus = value;

  void _setState(VoidCallback fn) {
    setState(fn);
  }

  @override
  void reassemble() {
    super.reassemble();
    _directoryBrowseController.sortIndex = _directoryBrowseController.sortIndex
        .clamp(0, ScanSortMode.values.length - 1);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribedSession = pageSession;
    _sessionAiGateway = ProductionAiAnalysisGateway(
      session: _subscribedSession,
    );
    _bindCoverageCoordinator();
    _bindScanPresentationController();
    _subscribedSession.addListener(_onSessionChanged);
    _lastPostDeleteRefreshPending = pageSession.postDeleteRefreshPending;
    _lastObservedSessionError = pageSession.lastError;
    _scheduleSessionStartup(_subscribedSession);
    if (Platform.isLinux) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_installLinuxDesktopIfNeeded());
      });
    }
  }

  Future<void> _installLinuxDesktopIfNeeded() async {
    try {
      final homeEnv = Platform.environment['HOME'];
      if (homeEnv == null || homeEnv.isEmpty) return;
      final appImage = Platform.environment['APPIMAGE'];
      final execPath = (appImage != null && appImage.isNotEmpty)
          ? appImage
          : Platform.resolvedExecutable;
      final iconPng = File(
        '${File(Platform.resolvedExecutable).parent.path}/volward.png',
      );
      await installLinuxDesktopIntegration(
        paths: LinuxDesktopPaths(
          home: Directory(homeEnv),
          execPath: execPath,
          iconPng: iconPng,
        ),
        settingsFile: sharedSettingsFile(),
      );
    } catch (error, stackTrace) {
      debugPrint('Linux desktop integration failed: $error\n$stackTrace');
    }
  }

  void _bindCoverageCoordinator({Future<void>? previousRetirement}) {
    final supplied = pageCoverageCoordinator;
    _ownsCoverageCoordinator = supplied == null;
    _coverageCoordinator =
        supplied ?? AiCoverageCoordinator.forSession(_subscribedSession);
    if (previousRetirement != null) {
      _coverageCoordinator!.attachAfter(_subscribedSession, previousRetirement);
    } else if (!_coverageCoordinator!.isAttachedTo(_subscribedSession)) {
      _coverageCoordinator!.rebind(_subscribedSession);
    } else if (_ownsCoverageCoordinator) {
      _coverageCoordinator!.observeLifecycleIfReady();
    }
  }

  void _bindScanPresentationController() {
    _scanPresentationController.bindActions(
      onCancelScan: _subscribedSession.cancelScan,
      onPauseScan: _subscribedSession.pauseCurrentScanForSwitch,
    );
    _scanPresentationController.bindSource(
      progress: _subscribedSession.scanProgressNotifier,
      scannedFraction: _subscribedSession.scannedFractionNotifier,
      elapsedLabel: _subscribedSession.scanElapsedNotifier,
    );
    _scanPresentationController.updateFromLifecycle(
      _subscribedSession,
      restoringSnapshot: _subscribedSession.restoringSnapshot,
      targetPreviewLoading: _subscribedSession.targetPreviewLoading,
      deleting: _subscribedSession.deleting,
      postDeleteRefreshPending: _subscribedSession.postDeleteRefreshPending,
      refreshingDirectoryCount:
          _subscribedSession.refreshingDirectoryPaths.length,
      progressDetail: _subscribedSession.scanProgress,
    );
  }

  void _scheduleSessionStartup(VolwardSession session) {
    final generation = ++_sessionGeneration;
    final gate = _startupRootGate;
    _startupPendingSession = session;
    _startupPendingGeneration = generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runSessionStartup(session, generation, gate));
    });
  }

  Future<void> _runSessionStartup(
    VolwardSession session,
    int generation,
    Completer<bool> gate,
  ) async {
    var restoreStarted = false;
    try {
      // Preview-first startup: lightweight session state + a validated launch
      // root render immediately, without waiting for the full snapshot/index
      // restore to complete (that restore continues in the background).
      final ScanLifecycle scan = session;
      final DirectoryBrowseSession browse = session;
      await scan.loadSessionStateIfNeeded();
      if (!_isCurrentSession(session, generation)) return;
      final launchRoot = await scan.resolveStartupRoot();
      if (!_isCurrentSession(session, generation)) return;

      setState(() {
        _hasValidRoot = launchRoot.isNotEmpty;
        _homeTargetPath = launchRoot;
      });
      unawaited(
        _loadStorageOverview(
          launchRoot,
          expectedSession: session,
          expectedSessionGeneration: generation,
        ),
      );
      if (identical(gate, _startupRootGate) && !gate.isCompleted) {
        gate.complete(true);
      }

      if (launchRoot.isNotEmpty) {
        if (browse.refreshTargetPath != launchRoot) {
          scan.setScanRoots([launchRoot]);
        }
        final previewGeneration = scan.rootSwitchGeneration;
        await scan.previewTarget(expectedGeneration: previewGeneration);
        if (!_isCurrentSession(session, generation)) return;
        restoreStarted = true;
        unawaited(_restoreCachedSnapshotInBackground(session, generation));
      }
    } catch (error, stackTrace) {
      if (_isCurrentSession(session, generation)) {
        debugPrint('HomePage startup failed: $error\n$stackTrace');
      }
    } finally {
      _finishSessionStartup(
        session,
        generation,
        gate,
        restoreStarted: restoreStarted,
      );
    }
  }

  bool _isCurrentSession(VolwardSession session, int generation) {
    return mounted &&
        identical(_subscribedSession, session) &&
        generation == _sessionGeneration;
  }

  bool _isStartupPendingFor(VolwardSession session) {
    return identical(_startupPendingSession, session) &&
        _startupPendingGeneration == _sessionGeneration;
  }

  void _finishSessionStartup(
    VolwardSession session,
    int generation,
    Completer<bool> gate, {
    required bool restoreStarted,
  }) {
    if (!_isCurrentSession(session, generation)) return;
    if (identical(gate, _startupRootGate) && !gate.isCompleted) {
      gate.complete(true);
    }
    if (!identical(_startupPendingSession, session) ||
        _startupPendingGeneration != generation) {
      return;
    }
    _startupPendingSession = null;
    _startupPendingGeneration = null;
    setState(() {});
    if (!restoreStarted) {
      _scheduleUpdaterPrefetch(session, generation);
    }
  }

  Future<void> _restoreCachedSnapshotInBackground(
    VolwardSession session,
    int generation,
  ) async {
    final ScanLifecycle scan = session;
    final DirectoryBrowseSession browse = session;
    try {
      await scan.restoreCachedSnapshotIfNeeded();
    } catch (error, stackTrace) {
      if (_isCurrentSession(session, generation)) {
        debugPrint(
          'HomePage cached snapshot restore failed: $error\n$stackTrace',
        );
        _scheduleUpdaterPrefetch(session, generation);
      }
      return;
    }
    if (!_isCurrentSession(session, generation)) return;
    final shouldAutoScan =
        session.ready &&
        !scan.scanning &&
        scan.hasSnapshotFileApi &&
        (_homeTargetPath ?? '').isNotEmpty &&
        !scan.hasAuthoritativeSnapshotForCurrentRoot;
    if (shouldAutoScan) {
      unawaited(_autoStartScan(session, generation));
    }
    _scheduleUpdaterPrefetch(session, generation);
    if (!mounted) return;
    setState(() {
      _query.invalidateSnapshotCachesForSessionUpdate();
      _lastRefreshedSnapshotId = session.lastSnapshot?.snapshotId;
      _lastRefreshedCatalogVersion = browse.catalogVersion;
      _actions.syncRecentCustomLocations();
      _lastHasResults = _query.hasResults;
    });
  }

  void _scheduleUpdaterPrefetch(VolwardSession session, int generation) {
    if (!_isCurrentSession(session, generation)) return;
    if (!pageThemeSettings.autoDownloadUpdates) return;
    if (_prefetchScheduledGeneration == generation) return;
    _prefetchScheduledGeneration = generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrentSession(session, generation)) return;
      if (!pageThemeSettings.autoDownloadUpdates) return;
      unawaited(pageUpdater.checkAndPrefetch());
    });
  }

  Future<void> _autoStartScan(VolwardSession session, int generation) async {
    if (!_isCurrentSession(session, generation)) return;
    final ScanLifecycle scan = session;
    if (_scanStartPending || scan.scanning || !scan.hasSnapshotFileApi) {
      return;
    }
    setState(() => _scanStartPending = true);
    try {
      await scan.runScan();
    } on ScanCancelledException {
      // ignored
    } catch (error, stackTrace) {
      debugPrint('HomePage auto-scan failed: $error\n$stackTrace');
    } finally {
      if (_isCurrentSession(session, generation)) {
        setState(() => _scanStartPending = false);
      }
    }
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sessionChanged = !identical(sessionOf(oldWidget), pageSession);
    final providerChanged = !identical(
      storageOverviewProviderOf(oldWidget),
      pageStorageOverviewProvider,
    );
    if (sessionChanged) {
      _subscribedSession.removeListener(_onSessionChanged);
      _subscribedSession = pageSession;
      _query.rebind(session: pageSession, browse: pageSession);
      _actions.rebind(
        session: pageSession,
        scan: pageSession,
        browse: pageSession,
        deletion: pageSession,
      );
      _bindScanPresentationController();
      _sessionAiGateway = ProductionAiAnalysisGateway(
        session: _subscribedSession,
      );
      _subscribedSession.addListener(_onSessionChanged);
    }
    if (sessionChanged ||
        !identical(coverageCoordinatorOf(oldWidget), pageCoverageCoordinator)) {
      if (identical(
        coverageCoordinatorOf(oldWidget),
        pageCoverageCoordinator,
      )) {
        _coverageCoordinator!.rebind(_subscribedSession);
      } else {
        final retirement = _coverageCoordinator!.detachAndDrain();
        _bindCoverageCoordinator(previousRetirement: retirement);
      }
    }
    if (!sessionChanged && !providerChanged) return;

    if (sessionChanged) {
      _sessionGeneration++;
      _scanStartGeneration++;
      _scanStartPending = false;
      _targetPreparationPending = false;
      _scanStatus = null;
      _directoryBrowseController.clearSelection();
      _directoryBrowseController.columnChain.clear();
      _directoryBrowseController.columnNavTick.value++;
      _query.invalidateSnapshotCaches();
      _lastRefreshedSnapshotId = pageSession.lastSnapshot?.snapshotId;
      _lastRefreshedCatalogVersion = pageSession.catalogVersion;
      _lastDeleting = pageSession.deleting;
      _lastRefreshingDirectoryCount =
          pageSession.refreshingDirectoryPaths.length;
      _lastTargetPreviewLoading = pageSession.targetPreviewLoading;
      _lastPostDeleteRefreshPending = pageSession.postDeleteRefreshPending;
      _lastObservedSessionError = pageSession.lastError;
      _prevScanning = pageSession.scanning;
      _lastHasResults = _query.hasResults;
      _homeTargetPath = null;
      _recentCustomLocations = const [];
      _hasValidRoot = false;
      if (!_startupRootGate.isCompleted) {
        _startupRootGate.complete(false);
      }
      _startupRootGate = Completer<bool>();
      unawaited(pageSession.refreshCapabilities());
      _overviewLoadGeneration++;
      _storageOverview = const StorageOverviewData.loading();
      _scheduleSessionStartup(_subscribedSession);
      return;
    }

    _overviewLoadGeneration++;
    _storageOverview = const StorageOverviewData.loading();
    if (_startupRootGate.isCompleted) {
      unawaited(_loadStorageOverview(_homeTargetPath ?? _query.scanRootPath()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionGeneration++;
    _overviewLoadGeneration++;
    _scanStartGeneration++;
    _scanStartPending = false;
    _targetPreparationPending = false;
    _startupPendingSession = null;
    _startupPendingGeneration = null;
    if (!_startupRootGate.isCompleted) {
      _startupRootGate.complete(false);
    }
    _subscribedSession.removeListener(_onSessionChanged);
    _scanPresentationController.unbindSource();
    if (_ownsCoverageCoordinator) _coverageCoordinator!.detach();
    _directoryBrowseController.dispose();
    _scanPresentationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      pageSession.refreshCapabilities();
      if (_startupRootGate.isCompleted) {
        unawaited(
          _loadStorageOverview(_homeTargetPath ?? _query.scanRootPath()),
        );
      }
      if (pageThemeSettings.autoDownloadUpdates) {
        unawaited(pageUpdater.checkAndPrefetch());
      }
    }
  }

  Future<void> _loadStorageOverview(
    String? selectedPath, {
    VolwardSession? expectedSession,
    int? expectedSessionGeneration,
  }) async {
    final generation = ++_overviewLoadGeneration;
    final provider = pageStorageOverviewProvider;
    bool isCurrentRequest() {
      return mounted &&
          generation == _overviewLoadGeneration &&
          (expectedSession == null ||
              identical(expectedSession, _subscribedSession)) &&
          (expectedSessionGeneration == null ||
              expectedSessionGeneration == _sessionGeneration) &&
          identical(provider, pageStorageOverviewProvider);
    }

    if (selectedPath == null || selectedPath.isEmpty) {
      if (isCurrentRequest()) {
        setState(
          () => _storageOverview = const StorageOverviewData.unavailable(
            'missing-root',
          ),
        );
      }
      return;
    }
    final data = await provider.load(selectedPath: selectedPath);
    if (!isCurrentRequest()) return;
    setState(() {
      _storageOverview = data;
      _actions.syncRecentCustomLocations();
    });
  }

  Future<void> _openFullDiskAccessSettings() async {
    await MacosSettings.touchFullDiskAccessProbe();
    if (mounted && !_permissionBannerExpanded) {
      setState(() => _permissionBannerExpanded = true);
    }
    await MacosSettings.openFullDiskAccessSettings();
  }

  Future<void> _copyAppBundlePath() async {
    await MacosSettings.copyAppBundlePath();
    if (!mounted) return;
    final path = MacosSettings.appBundlePath();
    final l10n = context.l10n;
    showTopToast(
      context,
      message: l10n.permissionCopiedPath(path ?? l10n.permissionUnknownPath),
      type: ToastType.success,
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          themeSettings: pageThemeSettings,
          session: pageSession,
          deletableOnly: _directoryBrowseController.deletableOnly,
          onDeletableOnlyChanged: (value) {
            _setState(() {
              _directoryBrowseController.deletableOnly = value;
              _query.resetColumnNav();
            });
          },
          updater: pageUpdater,
        ),
      ),
    );
  }

  void _onSessionChanged() {
    _directoryBrowseController.syncCurrentDirectory(
      pageSession.currentDirectoryPath,
    );
    _coverageCoordinator!.observeLifecycleIfReady();
    final sessionError = pageSession.lastError;
    if (sessionError != _lastObservedSessionError) {
      _lastObservedSessionError = sessionError;
      _showStateMachineErrorToast(sessionError);
    }
    final deletingChanged = _lastDeleting != pageSession.deleting;
    _lastDeleting = pageSession.deleting;
    final refreshingDirectoryCount =
        pageSession.refreshingDirectoryPaths.length;
    final refreshingChanged =
        _lastRefreshingDirectoryCount != refreshingDirectoryCount;
    _lastRefreshingDirectoryCount = refreshingDirectoryCount;
    final targetPreviewChanged =
        _lastTargetPreviewLoading != pageSession.targetPreviewLoading;
    _lastTargetPreviewLoading = pageSession.targetPreviewLoading;
    final postDeleteRefreshChanged =
        _lastPostDeleteRefreshPending != pageSession.postDeleteRefreshPending;
    _lastPostDeleteRefreshPending = pageSession.postDeleteRefreshPending;
    final hasResults = _query.hasResults;
    _scanPresentationController.updateFromLifecycle(
      pageSession,
      restoringSnapshot: pageSession.restoringSnapshot,
      targetPreviewLoading: pageSession.targetPreviewLoading,
      deleting: pageSession.deleting,
      postDeleteRefreshPending: pageSession.postDeleteRefreshPending,
      refreshingDirectoryCount: refreshingDirectoryCount,
      progressDetail: pageSession.scanProgress,
    );

    if (targetPreviewChanged && pageSession.targetPreviewLoading) {
      _setState(() {
        _directoryBrowseController.clearSelection();
        _scanStatus = null;
        _directoryBrowseController.columnChain.clear();
        _directoryBrowseController.columnNavTick.value++;
        _query.invalidateSnapshotCaches();
        _lastRefreshedSnapshotId = null;
        _lastRefreshedCatalogVersion = pageSession.catalogVersion;
      });
    } else if (!_prevScanning && pageSession.scanning) {
      _setState(() {
        // Scan now owns the busy state; don't keep Start disabled after Stop.
        _scanStartPending = false;
        _scanStatus = null;
        _query.invalidateSnapshotCaches();
        _lastRefreshedSnapshotId = pageSession.lastSnapshot?.snapshotId;
        if (_contentMode != _HomeContentMode.home) {
          _directoryBrowseController.clearSelection();
          _directoryBrowseController.columnChain.clear();
          _directoryBrowseController.columnNavTick.value++;
        }
      });
    } else if (_prevScanning && !pageSession.scanning) {
      // Completed or cancelled — release the start-scan lock even if runScan()
      // is still unwinding (native cancel can lag behind `scanning = false`).
      final snapshot = pageSession.lastSnapshot;
      final count = snapshot?.filesInSnapshot ?? 0;
      final l10n = context.l10n;
      final label = pageSession.incrementalScan
          ? l10n.scanStatusIncremental
          : l10n.scanStatusFull;
      _setState(() {
        _scanStartPending = false;
        if (snapshot != null) {
          _scanStatus = l10n.scanStatusFiles(label, count);
          _query.invalidateSnapshotCaches();
          _lastRefreshedSnapshotId = snapshot.snapshotId;
          if (_contentMode != _HomeContentMode.home) {
            _directoryBrowseController.columnChain.clear();
            _directoryBrowseController.columnNavTick.value++;
            _directoryBrowseController.clearSelection();
          }
        }
      });
    } else {
      // Checkpoint / peek merged new data. Refresh display caches whenever
      // snapshot_id changed — including when the user is still on the root
      // column, so preview spinners clear as soon as the background walk
      // rediscovers each directory. Also rebuild browse/home listenables when
      // the catalog version advances without a snapshotId change.
      final snapId = pageSession.lastSnapshot?.snapshotId;
      final catalogVer = pageSession.catalogVersion;
      final snapChanged = snapId != null && snapId != _lastRefreshedSnapshotId;
      final catalogChanged = catalogVer != _lastRefreshedCatalogVersion;
      final dataChanged = snapChanged || catalogChanged || targetPreviewChanged;
      if (dataChanged) {
        if (snapChanged) _lastRefreshedSnapshotId = snapId;
        _lastRefreshedCatalogVersion = catalogVer;
        _query.invalidateSnapshotCachesForSessionUpdate();
        final tree = _query.resolveResultTree();
        if (_directoryBrowseController.columnChain.isNotEmpty && tree != null) {
          // When the catalog index API is active, Dart tree.children is empty
          // (children come from Rust), so refreshColumnChain would always
          // truncate the chain to []. Skip the re-validation; the
          // visible-children cache invalidation above is sufficient.
          if (!pageSession.hasIndexApi) {
            final refreshed = refreshColumnChain(
              tree,
              _directoryBrowseController.columnChain,
            );
            final chain = _directoryBrowseController.columnChain;
            final chainChanged =
                refreshed.length != chain.length ||
                !Iterable.generate(
                  refreshed.length,
                ).every((i) => refreshed[i].path == chain[i].path);
            if (chainChanged) _query.setColumnChain(refreshed);
          }
        }
      }
      final flush = sessionUiFlushFor(
        snapshotIdChanged: snapChanged,
        catalogChanged: catalogChanged,
        targetPreviewChanged:
            targetPreviewChanged && !pageSession.targetPreviewLoading,
        deletingChanged: deletingChanged,
        refreshingChanged: refreshingChanged,
        postDeleteRefreshChanged: postDeleteRefreshChanged,
        scanStarted: !_prevScanning && pageSession.scanning,
        scanStopped: _prevScanning && !pageSession.scanning,
        browseResultsLayoutChanged:
            _contentMode == _HomeContentMode.browse &&
            hasResults != _lastHasResults,
      );
      switch (flush) {
        case SessionUiFlush.none:
          break;
        case SessionUiFlush.browseResults:
          _directoryBrowseController.homeSummaryRevision.value++;
          _directoryBrowseController.browseRevision.value++;
          break;
        case SessionUiFlush.homeSummary:
          _directoryBrowseController.homeSummaryRevision.value++;
          break;
        case SessionUiFlush.page:
          _setState(() {});
          break;
      }
    }
    _lastHasResults = hasResults;
    _prevScanning = pageSession.scanning;
  }

  void _showStateMachineErrorToast(String? error) {
    final message = switch (error) {
      'scan-pause-failed' => context.l10n.scanPauseFailed,
      'scan-cache-unreadable' => context.l10n.scanCacheUnreadable,
      'scan-cache-too-large' => context.l10n.scanCacheTooLarge,
      'scan-cache-restore-timeout' => context.l10n.scanCacheRestoreTimeout,
      _ => null,
    };
    if (message == null) return;
    showTopToast(context, message: message, type: ToastType.error);
  }

  // ---------- DirectoryDetailsActionState ----------

  @override
  bool get isBrowsing => _contentMode == _HomeContentMode.browse;
  @override
  set isBrowsing(bool value) {
    _contentMode = value ? _HomeContentMode.browse : _HomeContentMode.home;
  }

  @override
  bool get hasValidRoot => _hasValidRoot;
  @override
  set hasValidRoot(bool value) => _hasValidRoot = value;

  @override
  bool get targetPreparationPending => _targetPreparationPending;
  @override
  set targetPreparationPending(bool value) => _targetPreparationPending = value;

  @override
  bool get scanStartPending => _scanStartPending;
  @override
  set scanStartPending(bool value) => _scanStartPending = value;

  @override
  String? get scanStatus => _scanStatus;
  @override
  set scanStatus(String? value) => _scanStatus = value;

  @override
  String? get homeTargetPath => _homeTargetPath;
  @override
  set homeTargetPath(String? value) => _homeTargetPath = value;

  @override
  List<StorageLocationInfo> get recentCustomLocations => _recentCustomLocations;
  @override
  set recentCustomLocations(List<StorageLocationInfo> value) =>
      _recentCustomLocations = value;

  @override
  StorageOverviewData get storageOverview => _storageOverview;
  @override
  set storageOverview(StorageOverviewData value) => _storageOverview = value;

  @override
  Completer<bool> get startupRootGate => _startupRootGate;
  @override
  set startupRootGate(Completer<bool> value) => _startupRootGate = value;

  @override
  int get scanStartGeneration => _scanStartGeneration;
  @override
  set scanStartGeneration(int value) => _scanStartGeneration = value;

  @override
  int get sessionGeneration => _sessionGeneration;

  @override
  int get overviewLoadGeneration => _overviewLoadGeneration;
  @override
  set overviewLoadGeneration(int value) => _overviewLoadGeneration = value;

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pageThemeSettings,
      builder: (context, _) {
        final browsing = _contentMode == _HomeContentMode.browse;
        final session = pageSession;
        final restoring = session.restoringSnapshot;
        final snapshotMatches = _query.snapshotMatchesCurrentRoot();
        final loadingTarget =
            session.targetPreviewLoading ||
            (session.scanning && !snapshotMatches);
        final hasResults =
            !loadingTarget && session.lastSnapshot != null && snapshotMatches;
        return DirectoryPageScaffold(
          backgroundColor: browsing
              ? context.volward.canvasParchment
              : dashboardPageBackground(context),
          body: Column(
            children: [
              if (browsing)
                DirectoryTopNav(
                  onShowHome: _actions.showHome,
                  onOpenSettings: _openSettings,
                ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: Offstage(
                        offstage: browsing,
                        child: TickerMode(
                          enabled: !browsing,
                          child: SizedBox.expand(child: _buildHomeDashboard()),
                        ),
                      ),
                    ),
                    if (browsing)
                      _buildBrowseBody(
                        restoring: restoring,
                        loadingTarget: loadingTarget,
                        hasResults: hasResults,
                      ),
                  ],
                ),
              ),
              if (browsing) _buildStickyBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHomeDashboard() {
    final availableAiSnapshot = _actions.homeAiSnapshot();
    return HomeDashboard(
      storageHomeKey: _storageHomeKey,
      summary: _actions.homeSummary,
      scanProgress: _scanPresentationController.progress,
      revision: _directoryBrowseController.homeSummaryRevision,
      aiSnapshotId: availableAiSnapshot?.snapshotId,
      aiAnalysisGateway: _aiGateway,
      coverageJobs: _coverageCoordinator,
      coverageOwner: _subscribedSession,
      onAiDeleteCompleted: _actions.handleAiDeleteCompleted,
      onOpenDetailPage: (path) => unawaited(
        _actions.onHomeBrowse(focusPath: path.isEmpty ? null : path),
      ),
      onBrowse: () => unawaited(_actions.onHomeBrowse()),
      onChooseFolder: () => unawaited(_actions.pickHomeFolder()),
      onSelectTarget: (location) =>
          unawaited(_actions.prepareHomeTarget(location.path)),
      onScan: _actions.scanStartAction,
      onCancelScan: _scanPresentationController.scanning
          ? _scanPresentationController.cancelScan
          : null,
      onOpenSettings: _openSettings,
      onSelectCategory: _actions.openHomeCategory,
      onOpenItem: (item) =>
          unawaited(_actions.onHomeBrowse(focusPath: item.path)),
      updater: pageUpdater,
    );
  }

  Widget _permissionBanner(BuildContext context) {
    return DirectoryPermissionBanner(
      ready: pageSession.ready,
      initError: pageSession.initError,
      hasSnapshotFileApi: pageSession.hasSnapshotFileApi,
      deepScanReady: pageSession.deepScanReady,
      expanded: _permissionBannerExpanded,
      onToggleExpanded: (value) =>
          _setState(() => _permissionBannerExpanded = value),
      onOpenFullDiskAccess: () => unawaited(_openFullDiskAccessSettings()),
      onCopyAppPath: () => unawaited(_copyAppBundlePath()),
      onCheckAgain: pageSession.refreshCapabilities,
    );
  }

  Widget _buildBrowseBody({
    required bool restoring,
    required bool loadingTarget,
    required bool hasResults,
  }) {
    final session = pageSession;
    return BrowseBody(
      restoring: restoring,
      loadingTarget: loadingTarget,
      hasResults: hasResults,
      scanSection: DirectoryScanSection(
        permissionBanner:
            !session.ready ||
                !session.hasSnapshotFileApi ||
                !session.deepScanReady
            ? _permissionBanner(context)
            : null,
        targetLabel: _query.scanTargetLabel(context.l10n),
        scanRootsEmpty: session.scanRoots.isEmpty,
        scanning: session.scanning,
        scannedFraction: _scanPresentationController.scannedFraction,
        elapsedLabel: _scanPresentationController.elapsedLabel,
        progressSummary: _query.scanProgressSummary,
        scanStatus: _scanStatus,
        onPickFolder: () => unawaited(_actions.pickFolder()),
        showHomeAction: session.scanRoots.isNotEmpty,
        onBrowseHome: () => unawaited(_actions.switchBrowseToHomeRoot()),
        onCancelScan: _scanPresentationController.cancelScan,
      ),
      restoreLoading: DirectoryRestoreLoading(
        label: restoring
            ? context.l10n.resultsRestoringPreviousScan
            : context.l10n.scanColumnPreparingFolder,
      ),
      emptyBody: const SizedBox(height: 72),
      resultsBody: DirectoryBrowseResults(
        revision: _directoryBrowseController.browseRevision,
        query: _query,
        browseController: _directoryBrowseController,
        scanning: session.scanning,
        deleting: session.deleting,
        hasIndexApi: session.hasIndexApi,
        refreshingPaths: session.refreshingDirectoryPaths,
        peekInFlight: session.peekInFlight,
        canRefresh: session.canRefreshCurrentDirectory,
        onRescan: () => unawaited(session.refreshCurrentDirectory()),
        onPickFolder: () => unawaited(_actions.pickFolder()),
        showHomeAction: session.scanRoots.isNotEmpty,
        onBrowseHome: () => unawaited(_actions.switchBrowseToHomeRoot()),
        onPermission: (context) =>
            session.ready &&
                (!session.hasSnapshotFileApi || !session.deepScanReady)
            ? _permissionBanner(context)
            : null,
        formatBytes: formatDirectoryBytes,
      ),
    );
  }

  Widget _buildStickyBar() {
    final session = pageSession;
    return DirectoryDetailsStickyBar(
      scanning: session.scanning,
      deleting: session.deleting,
      scanStartPending: _scanStartPending,
      refreshing: session.refreshingDirectoryPaths.isNotEmpty,
      hasResults: session.lastSnapshot != null,
      ready: session.ready,
      peekCount: session.peekInFlight.length,
      deleteCount: _query.deleteTargetCount(),
      deleteBytes: _query.deleteTargetBytes(),
      scannedFraction: _scanPresentationController.scannedFraction,
      elapsedLabel: _scanPresentationController.elapsedLabel,
      progressSummary: _query.scanProgressSummary,
      canRefresh: session.canRefreshCurrentDirectory,
      onRescan: () => unawaited(session.refreshCurrentDirectory()),
      onCancelScan: _scanPresentationController.cancelScan,
      onStartScan: _actions.scanStartAction,
      onConfirmDelete: _actions.confirmDelete,
      onConfirmEmptyTrash: _actions.confirmEmptyTrash,
    );
  }
}
