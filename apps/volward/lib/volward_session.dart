// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ai/ai_candidates_materialized_cache.dart';
import 'ai/ai_debug_log.dart';
import 'ai/ai_provider.dart';
import 'ai/coverage_models.dart';
import 'ai/coverage_snapshot_reader.dart';
import 'ai/native_coverage_engine.dart';
import 'ai/native_engine_lifetime.dart';
import 'analytics/analytics.dart';
import 'analytics/analytics_events.dart';
import 'bridge/native_bridge.dart';
import 'cache_restore_policy.dart';
import 'capabilities/capability_models.dart';
import 'core/session/capability_session.dart';
import 'core/session/catalog_session.dart';
import 'core/session/deletion_session.dart';
import 'core/session/engine_host.dart';
import 'core/session/scan_session.dart';
import 'core/session/snapshot_persistence.dart';
import 'core/contracts/native_engine_ports.dart';
import 'core/contracts/scan_session_host.dart';
import 'features/browse/directory_browse_session.dart';
import 'features/browse/controllers/directory_details_ports.dart';
import 'features/deletion/deletion_actions.dart';
import 'features/scan/scan_lifecycle.dart';
import 'features/scan/scan_session_types.dart';
import 'features/scan/snapshot_file_decoder.dart';
import 'scan_root_record.dart';
import 'scan_snapshot_state.dart';
import 'scan_tree.dart';
import 'snapshot_catalog.dart';
import 'snapshot_cache.dart';
import 'snapshot_query.dart';

export 'features/scan/scan_progress_estimate.dart' show estimateScanFraction;
export 'features/scan/scan_session_types.dart'
    show ScanCancelledException, ScanProgressViewState, ScanRunMode;

/// Holds the native Volward engine pointer and exposes async wrappers for UI.
class VolwardSession extends ChangeNotifier
    implements
        DirectoryBrowseSession,
        CoverageSnapshotReader,
        DeletionActions,
        DirectorySnapshotSource,
        ScanLifecycle,
        ScanSessionHost,
        CatalogSessionHost,
        DeletionSessionHost {
  VolwardSession()
    : _bridgeForTest = null,
      _engineHost = null,
      _offloadCoverageForTest = true {
    _scanSession = ScanSession(
      host: this,
      persistence: _snapshotPersistence,
      snapshotFileDecoder: decodeSnapshotFile,
    );
    _testPortHost = null;
    _scanSessionNotificationsSub = _scanSession.notifications.listen(
      _handleScanSessionNotification,
    );
    _catalogSession = CatalogSession(host: this);
    _deletionSession = DeletionSession(host: this, catalog: _catalogSession);
    _capabilitySession = CapabilitySession(
      () => _capabilityEngine,
      () => _ready,
      () => _initError,
    );
    _catalogSession.addListener(_notifyListeners);
    _deletionSession.addListener(_notifyListeners);
    _initialize();
    instance = this;
  }

  VolwardSession.test({
    VolwardNativeBridge? nativeBridgeForTest,
    Pointer<Void>? engineForTest,
    bool offloadCoverageForTest = true,
  }) : _bridgeForTest = nativeBridgeForTest,
       _engineHost = engineForTest == null
           ? null
           : EngineHost.forTest(
               engine: engineForTest,
               freeEngine: () =>
                   (nativeBridgeForTest ?? VolwardNativeBridge.instance)
                       .freeEngine(engineForTest),
             ),
       // Keep the public test constructor parameter name stable.
       // ignore: prefer_initializing_formals
       _offloadCoverageForTest = offloadCoverageForTest,
       _ready = true,
       _persistSessionStateEnabled = false {
    _scanSession = ScanSession(
      host: this,
      persistence: _snapshotPersistence,
      snapshotFileDecoder: decodeSnapshotFile,
      persistSessionStateEnabled: false,
    );
    _testPortHost = EngineHost.forTest(engine: Pointer<Void>.fromAddress(1));
    _scanSessionNotificationsSub = _scanSession.notifications.listen(
      _handleScanSessionNotification,
    );
    _catalogSession = CatalogSession(host: this);
    _deletionSession = DeletionSession(host: this, catalog: _catalogSession);
    _capabilitySession = CapabilitySession(
      () => _capabilityEngine,
      () => _ready,
      () => _initError,
    );
    _catalogSession.addListener(_notifyListeners);
    _deletionSession.addListener(_notifyListeners);
  }

  /// Global reference set when the singleton is constructed.
  /// Retained for callers of the legacy catalog and AI entry points.
  static VolwardSession? _instance;
  static VolwardSession? get instance => _instance;
  static set instance(VolwardSession? value) {
    _instance = value;
    SnapshotCatalog.legacyReader = value;
  }

  final VolwardNativeBridge? _bridgeForTest;
  final bool _offloadCoverageForTest;
  late final ScanSession _scanSession;
  late final CatalogSession _catalogSession;
  late final DeletionSession _deletionSession;
  late final CapabilitySession _capabilitySession;
  late final EngineHost? _testPortHost;
  late final SnapshotPersistence _snapshotPersistence = SnapshotPersistence(
    stateFile: () async => sessionStateFileForTest ?? _sessionStateFile(),
    readState: (file) =>
        sessionStateReaderForTest?.call(file) ?? file.readAsString(),
    writeState: (file, value) => file.writeAsString(value),
  );
  EngineHost? _engineHost;
  StreamSubscription<ScanSessionNotificationKind>? _scanSessionNotificationsSub;
  // ignore: deprecated_member_use
  Pointer<Void>? get _engine => _engineHost?.legacyEnginePointer;
  NativeEngineLifetime get _engineLifetime {
    final host = _engineHost;
    if (host == null) {
      throw StateError('Native engine not initialized');
    }
    return host.lifetime;
  }

  bool _ready = false;
  String? _initError;
  String? _lastError;
  Map<String, dynamic> _capabilities = {};
  bool _deepScanReady = false;
  bool get _scanning => _scanSession.scanning;
  String? get _lastJobId => _scanSession.lastJobId;
  ScanSnapshotState? get _lastSnapshot => _scanSession.lastSnapshot;
  Map<String, dynamic>? get _scanProgress => _scanSession.scanProgress;
  List<String> get _scanRoots => _scanSession.scanRoots;
  String? get _lastCustomRoot => _scanSession.lastCustomRoot;
  List<String> get _recentCustomRoots => _scanSession.recentCustomRoots;
  bool get _incrementalScan => _scanSession.incrementalScan;
  final Set<String> _selectedEntryIds = {};
  // Monotonic token for root switches. If the user picks folders quickly, only
  // the latest preview/scan handoff may update the visible snapshot.
  int get _rootSwitchGeneration => _scanSession.rootSwitchGeneration;

  // Throttle display-update notifications from _applyMerge. Checkpoints can
  // arrive 5-10×/sec; rebuilding the full widget tree that often is the primary
  // source of UI jank. We still update _lastSnapshot on every checkpoint for
  // correctness; we just batch the UI wake-ups to ≤ 1 per _kDisplayNotifyGap.
  ValueNotifier<String?> get scanElapsedNotifier =>
      _scanSession.scanElapsedNotifier;
  ValueNotifier<double?> get scannedFractionNotifier =>
      _scanSession.scannedFractionNotifier;
  ValueNotifier<ScanProgressViewState> get scanProgressNotifier =>
      _scanSession.scanProgressNotifier;
  int _notificationBatchDepth = 0;
  bool _notificationBatchPending = false;
  @visibleForTesting
  Future<ScanSnapshotState?> Function(String jobId, List<String> roots)?
  get scanRunnerForTest => _scanSession.scanRunnerForTest;
  set scanRunnerForTest(
    Future<ScanSnapshotState?> Function(String jobId, List<String> roots)?
    value,
  ) => _scanSession.scanRunnerForTest = value;
  @visibleForTesting
  get deleteRunnerForTest => _deletionSession.deleteRunnerForTest;
  @visibleForTesting
  set deleteRunnerForTest(value) =>
      _deletionSession.deleteRunnerForTest = value;
  @visibleForTesting
  get directoryRefreshRunnerForTest =>
      _catalogSession.directoryRefreshRunnerForTest;
  @visibleForTesting
  set directoryRefreshRunnerForTest(value) =>
      _catalogSession.directoryRefreshRunnerForTest = value;
  @visibleForTesting
  Future<List<Map<String, dynamic>>> Function(String path)?
  get scanRootPreviewReaderForTest => _scanSession.scanRootPreviewReaderForTest;
  set scanRootPreviewReaderForTest(
    Future<List<Map<String, dynamic>>> Function(String path)? value,
  ) => _scanSession.scanRootPreviewReaderForTest = value;
  @visibleForTesting
  get capabilityAnalyzeRunnerForTest =>
      _capabilitySession.capabilityAnalyzeRunnerForTest;
  @visibleForTesting
  set capabilityAnalyzeRunnerForTest(value) =>
      _capabilitySession.capabilityAnalyzeRunnerForTest = value;
  @visibleForTesting
  get capabilityStartRunnerForTest =>
      _capabilitySession.capabilityStartRunnerForTest;
  @visibleForTesting
  set capabilityStartRunnerForTest(value) =>
      _capabilitySession.capabilityStartRunnerForTest = value;
  @visibleForTesting
  get capabilityStatusReaderForTest =>
      _capabilitySession.capabilityStatusReaderForTest;
  @visibleForTesting
  set capabilityStatusReaderForTest(value) =>
      _capabilitySession.capabilityStatusReaderForTest = value;
  @visibleForTesting
  get capabilityCancelRunnerForTest =>
      _capabilitySession.capabilityCancelRunnerForTest;
  @visibleForTesting
  set capabilityCancelRunnerForTest(value) =>
      _capabilitySession.capabilityCancelRunnerForTest = value;

  bool get _targetPreviewLoading => _scanSession.targetPreviewLoading;
  bool _persistSessionStateEnabled = true;
  @visibleForTesting
  File? sessionStateFileForTest;
  @visibleForTesting
  Future<String> Function(File file)? sessionStateReaderForTest;
  @visibleForTesting
  Future<bool> Function()? get pauseCurrentScanForTest =>
      _scanSession.pauseCurrentScanForTest;
  set pauseCurrentScanForTest(Future<bool> Function()? value) =>
      _scanSession.pauseCurrentScanForTest = value;
  @visibleForTesting
  ScanRootRecordStore? rootRecordStoreForTest;
  @visibleForTesting
  String Function(String root, String cacheDir)? get pauseRequestForTest =>
      _scanSession.pauseRequestForTest;
  set pauseRequestForTest(
    String Function(String root, String cacheDir)? value,
  ) => _scanSession.pauseRequestForTest = value;
  @visibleForTesting
  String? Function()? get pauseErrorForTest => _scanSession.pauseErrorForTest;
  set pauseErrorForTest(String? Function()? value) =>
      _scanSession.pauseErrorForTest = value;
  @visibleForTesting
  Future<void> Function()? get scanPreparationWaitForTest =>
      _scanSession.scanPreparationWaitForTest;
  set scanPreparationWaitForTest(Future<void> Function()? value) =>
      _scanSession.scanPreparationWaitForTest = value;
  @visibleForTesting
  Duration? get nativeScanStopTimeoutForTest =>
      _scanSession.nativeScanStopTimeoutForTest;
  set nativeScanStopTimeoutForTest(Duration? value) =>
      _scanSession.nativeScanStopTimeoutForTest = value;
  @visibleForTesting
  Duration? get restoreDelayForTest => _scanSession.restoreDelayForTest;
  set restoreDelayForTest(Duration? value) =>
      _scanSession.restoreDelayForTest = value;
  @visibleForTesting
  VoidCallback? get restoreDelayStartedForTest =>
      _scanSession.restoreDelayStartedForTest;
  set restoreDelayStartedForTest(VoidCallback? value) =>
      _scanSession.restoreDelayStartedForTest = value;

  /// Overrides [cacheRestoreTimeoutForByteSize] in tests.
  @visibleForTesting
  Duration? get cacheRestoreTimeoutForTest =>
      _scanSession.cacheRestoreTimeoutForTest;
  set cacheRestoreTimeoutForTest(Duration? value) =>
      _scanSession.cacheRestoreTimeoutForTest = value;

  /// Treats the session as index-capable without a native engine.
  @visibleForTesting
  bool get treatAsIndexApiForTest => _scanSession.treatAsIndexApiForTest;
  set treatAsIndexApiForTest(bool value) =>
      _scanSession.treatAsIndexApiForTest = value;

  /// In-memory index used by [treatAsIndexApiForTest] restore paths.
  @visibleForTesting
  ScanSnapshotState? get engineIndexSnapshotForTest =>
      _scanSession.engineIndexSnapshotForTest;
  set engineIndexSnapshotForTest(ScanSnapshotState? value) =>
      _scanSession.engineIndexSnapshotForTest = value;

  /// Counts async index load starts when [indexLoadAsyncResultForTest] is set.
  @visibleForTesting
  int get startIndexLoadCallsForTest => _scanSession.startIndexLoadCallsForTest;
  set startIndexLoadCallsForTest(int value) =>
      _scanSession.startIndexLoadCallsForTest = value;

  /// When set, simulates [startLoadIndexFromPathAsync] return values per call.
  @visibleForTesting
  List<String>? get indexLoadAsyncResultsForTest =>
      _scanSession.indexLoadAsyncResultsForTest;
  set indexLoadAsyncResultsForTest(List<String>? value) =>
      _scanSession.indexLoadAsyncResultsForTest = value;

  /// When set, simulates whether an async index load is in progress.
  @visibleForTesting
  bool Function()? get isIndexLoadingForTest =>
      _scanSession.isIndexLoadingForTest;
  set isIndexLoadingForTest(bool Function()? value) =>
      _scanSession.isIndexLoadingForTest = value;

  @override
  bool get ready => _ready;
  @override
  String? get initError => _initError;
  @override
  String? get lastError => _lastError;
  @override
  set lastError(String? value) => _lastError = value;
  Map<String, dynamic> get capabilities => _capabilities;
  bool get deepScanReady => _deepScanReady;
  @override
  bool get scanning => _scanning;
  @visibleForTesting
  ScanSession get scanSessionForTest => _scanSession;
  @visibleForTesting
  CatalogSession get catalogSessionForTest => _catalogSession;
  @visibleForTesting
  DeletionSession get deletionSessionForTest => _deletionSession;
  @visibleForTesting
  CapabilitySession get capabilitySessionForTest => _capabilitySession;
  @visibleForTesting
  bool get didAttemptHydration => _catalogSession.didAttemptHydration;
  @visibleForTesting
  set didAttemptHydration(bool value) =>
      _catalogSession.didAttemptHydration = value;
  @override
  bool get deleting => _deletionSession.deleting;
  String? get lastJobId => _lastJobId;

  @override
  bool get persistSessionStateEnabled =>
      _persistSessionStateEnabled || sessionStateFileForTest != null;

  @override
  ScanEnginePort get scanEngine => (_engineHost ?? _testPortHost!).scan;

  @override
  IndexEnginePort get indexEngine => (_engineHost ?? _testPortHost!).index;

  @override
  ScanRootRecordStore get rootRecordStore =>
      rootRecordStoreForTest ?? ScanRootRecordStore(SnapshotCache.cacheDir());

  @override
  void invalidateCapabilityCache(String? snapshotId) =>
      _capabilitySession.invalidateForSnapshot(snapshotId);

  @override
  void resetBrowseStateForRootChange() =>
      _catalogSession.resetBrowseStateForRootChange();

  @override
  void clearDeletionState() => _deletionSession.clearState();

  @override
  Future<void> commitMergedSnapshot({
    required ScanSnapshotState snapshot,
    required String targetPath,
    required Map<String, dynamic> subtreeTree,
    required List<Map<String, dynamic>> subtreeEntries,
    required bool authoritative,
  }) => _catalogSession.commitMergedSnapshot(
    snapshot: snapshot,
    targetPath: targetPath,
    subtreeTree: subtreeTree,
    subtreeEntries: subtreeEntries,
    authoritative: authoritative,
    notify: false,
  );

  @override
  Future<void> previewTargetFromHost({int? expectedGeneration}) =>
      previewTarget(expectedGeneration: expectedGeneration);

  @override
  Future<bool> peekScanFromHost(String path, {bool force = false}) =>
      peekScan(path, force: force);

  @override
  Future<String> runScanFromHost({required ScanRunMode mode}) =>
      runScan(mode: mode);

  @override
  void trackScanRootSelected(String root) {
    unawaited(
      Analytics.instance.track(AnalyticsEvents.scanRootSelected, {
        'root': root,
      }),
    );
  }

  @override
  void trackScanStarted({required String root, required bool incremental}) {
    unawaited(
      Analytics.instance.track(AnalyticsEvents.scanStarted, {
        'incremental': incremental ? 1 : 0,
      }),
    );
  }

  @override
  void trackScanCompleted({
    required String root,
    required Duration elapsed,
    required int entryCount,
  }) {
    unawaited(
      Analytics.instance.track(AnalyticsEvents.scanCompleted, {
        'success': entryCount > 0 ? 1 : 0,
        'duration_ms': elapsed.inMilliseconds,
      }),
    );
  }

  @override
  bool get catalogEngineReady =>
      _ready && (_engine != null || scanRunnerForTest != null);

  @override
  bool get catalogHasIndexApi => hasIndexApi;

  @override
  bool get catalogHasSnapshotFileApi => hasSnapshotFileApi;

  @override
  int get catalogIndexVersion => catalogHasIndexApi && _engineHost != null
      ? _engineHost!.index.indexVersion()
      : 0;

  @override
  int get catalogRootSwitchGeneration => _rootSwitchGeneration;

  @override
  bool get catalogScanning => _scanning;

  @override
  Set<String> get catalogPeekInFlight => _scanSession.peekInFlight;

  @override
  ScanSnapshotState? get catalogSnapshot => _lastSnapshot;

  @override
  List<String> get catalogScanRoots => _scanRoots;

  @override
  String get catalogDefaultRoot => _defaultScanRoot();

  @override
  IndexEnginePort? get catalogIndexEngine =>
      _engineHost?.index ?? _testPortHost?.index;

  @override
  Future<void> runCatalogRootRefresh() => runScan(mode: ScanRunMode.rescan);

  @override
  Future<bool> peekScanForCatalog(String path, {bool force = false}) =>
      _scanSession.peekScan(path, force: force);

  @override
  void invalidateCapabilityCacheForCatalog(String? snapshotId) =>
      _capabilitySession.invalidateForSnapshot(snapshotId);

  @override
  void setCatalogLastError(String? value) => _lastError = value;

  @override
  void beginCatalogNotificationBatch() => _beginNotificationBatch();

  @override
  void endCatalogNotificationBatch({bool notify = true}) =>
      _endNotificationBatch(notify: notify);

  @override
  void trackCatalogRefreshTriggered() {
    unawaited(Analytics.instance.track(AnalyticsEvents.refreshTriggered));
  }

  @override
  bool get deletionReady => _ready;

  @override
  String? get deletionInitError => _initError;

  @override
  DeleteEnginePort? get deletionEngine =>
      _engineHost?.delete ?? _testPortHost?.delete;

  @override
  String? get deletionSnapshotId => _lastSnapshot?.snapshotId;

  @override
  void setDeletionLastError(String? value) => _lastError = value;

  @override
  void trackMoveToTrash({required int itemCount, required bool success}) {
    unawaited(
      Analytics.instance.track(AnalyticsEvents.moveToTrash, {
        'item_count': itemCount,
        'success': success ? 1 : 0,
      }),
    );
  }

  @override
  void trackEmptyTrash({required bool success}) {
    unawaited(
      Analytics.instance.track(AnalyticsEvents.emptyTrash, {
        'success': success ? 1 : 0,
      }),
    );
  }

  CapabilityEnginePort? get _capabilityEngine =>
      _engineHost?.capability ?? _testPortHost?.capability;

  /// True when the bundled dylib supports catalog index query/refresh APIs.
  @override
  bool get hasIndexApi {
    if (treatAsIndexApiForTest) return _ready;
    // Guard: if the engine hasn't been initialised yet (e.g. in unit tests via
    // VolwardSession.test()), return false rather than attempting to dlopen the
    // dylib, which would crash in environments without the native library.
    if (!_ready || _engineHost == null) return false;
    return _engineHost!.index.hasIndexApi;
  }

  /// Current combined view version for cache-key alignment (Design §5.4).
  ///
  /// Combines the Rust catalog's data version (reflects when the index was
  /// last rebuilt from a new snapshot) with the Dart-side [_snapshotVersion]
  /// (incremented by [refreshCurrentDirectory] and other UI-intent operations).
  ///
  /// Using both guarantees that:
  /// - A new scan result (Rust version bump) invalidates the view cache.
  /// - A catalog refresh call (Dart _snapshotVersion bump, no data change)
  ///   also invalidates the cache and triggers a rebuild in [_onSessionChanged].
  @override
  int get catalogVersion => _catalogSession.catalogVersion;

  @override
  ScanSnapshotState? get lastSnapshot => _lastSnapshot;
  Map<String, dynamic>? get lastDeleteReport =>
      _deletionSession.lastDeleteReport;
  Map<String, dynamic>? get scanProgress => _scanProgress;
  @override
  List<String> get scanRoots => List.unmodifiable(_scanRoots);
  String? get lastCustomRoot => _recentCustomRoots.isNotEmpty
      ? _recentCustomRoots.first
      : _lastCustomRoot;
  @override
  List<String> get recentCustomRoots => List.unmodifiable(
    _recentCustomRoots.isNotEmpty
        ? _recentCustomRoots
        : [
            if (_lastCustomRoot != null && _lastCustomRoot!.isNotEmpty)
              _lastCustomRoot!,
          ],
  );
  @override
  bool get incrementalScan => _incrementalScan;
  Set<String> get selectedEntryIds => Set.unmodifiable(_selectedEntryIds);

  int get snapshotVersion => _catalogSession.snapshotVersion;
  @override
  int get rootSwitchGeneration => _rootSwitchGeneration;

  Set<String> get invalidatedPrefixes => _catalogSession.invalidatedPrefixes;

  /// Latest authoritative filesystem result for a directory peek. Index-mode
  /// snapshots intentionally keep only root metadata in Dart, so these local
  /// overlays are the source of truth for refreshed directories until the
  /// next full scan replaces the catalog.
  @override
  ScanTreeNode? directoryOverlayForPath(String path) =>
      _catalogSession.directoryOverlayForPath(path);

  @override
  Set<String> get refreshingDirectoryPaths =>
      _catalogSession.refreshingDirectoryPaths;

  @override
  bool get postDeleteRefreshPending => _catalogSession.postDeleteRefreshPending;

  @override
  bool isDirectoryRefreshing(String path) =>
      _catalogSession.isDirectoryRefreshing(path);

  String? refreshErrorForPath(String path) =>
      _catalogSession.refreshErrorForPath(path);

  @override
  Set<String> consumeInvalidatedPrefixes() =>
      _catalogSession.consumeInvalidatedPrefixes();

  void _notifyListeners() {
    if (_notificationBatchDepth > 0) {
      _notificationBatchPending = true;
      return;
    }
    notifyListeners();
  }

  void _notifyImmediately() => notifyListeners();

  void _handleScanSessionNotification(ScanSessionNotificationKind kind) {
    switch (kind) {
      case ScanSessionNotificationKind.batched:
        _notifyListeners();
        return;
      case ScanSessionNotificationKind.immediate:
        _notifyImmediately();
        return;
    }
  }

  @visibleForTesting
  void beginNotificationBatchForTest() => _beginNotificationBatch();

  @visibleForTesting
  void endNotificationBatchForTest({bool notify = false}) =>
      _endNotificationBatch(notify: notify);

  void _beginNotificationBatch() {
    _notificationBatchDepth++;
  }

  void _endNotificationBatch({bool notify = false}) {
    if (_notificationBatchDepth == 0) return;
    _notificationBatchDepth--;
    if (_notificationBatchDepth == 0 && (_notificationBatchPending || notify)) {
      _notificationBatchPending = false;
      _notifyListeners();
    }
  }

  @visibleForTesting
  void setSnapshotForTest(ScanSnapshotState snapshot) {
    _scanSession.setSnapshotForTest(snapshot);
    _catalogSession.replaceSnapshotForTest(snapshot);
  }

  @visibleForTesting
  void primeTransientScanStateForTest({
    Map<String, dynamic>? progress,
    bool scanning = true,
    bool preparing = false,
    bool openScanPorts = true,
    String? lastJobId,
  }) {
    _scanSession.primeTransientScanStateForTest(
      progress: progress,
      scanning: scanning,
      preparing: preparing,
      openScanPorts: openScanPorts,
      lastJobId: lastJobId,
    );
  }

  @visibleForTesting
  void updateScanProgressForTest(Map<String, dynamic> progress) {
    _scanSession.updateScanProgressForTest(progress);
  }

  @visibleForTesting
  void updateSnapshotForTest(
    ScanSnapshotState snapshot, {
    required String affectedPrefix,
  }) {
    _scanSession.updateSnapshotForTest(
      snapshot,
      affectedPrefix: affectedPrefix,
    );
  }

  /// Paths for which a peek scan is currently in flight.
  /// Empty when no peek is running (or when a full scan hasn't started yet).
  @override
  Set<String> get peekInFlight => _scanSession.peekInFlight;

  /// Fraction of directories in the current tree that have been scanned
  /// (0.0–1.0). This is an estimated progress bar derived from the active scan
  /// phase and elapsed time rather than a tree-wide directory-count ratio.
  /// Returns null when a scan is not running.
  ///
  /// Prefer listening to [scannedFractionNotifier] for UI that should update
  /// when the estimate ticks forward (without a full page notify).
  double? get scannedFraction => _scanSession.scannedFraction;

  /// Whether the bundled native library supports file-based snapshot I/O.
  @override
  bool get hasSnapshotFileApi {
    // Same guard as [hasIndexApi]: in unit tests the engine is null, and
    // touching the bridge singleton would attempt to dlopen the dylib and
    // crash in environments without the native library.
    return _ready && (_engineHost?.index.hasSnapshotFileApi ?? false);
  }

  /// Whether the bundled native library supports incremental scan options.
  bool get hasScanOptionsApi {
    return _ready && (_engineHost?.scan.hasScanOptionsApi ?? false);
  }

  /// Increment scan requires both snapshot file API and scan options FFI.
  @override
  bool get canUseIncrementalScan => hasSnapshotFileApi && hasScanOptionsApi;

  /// True while loading a previously saved scan from disk cache.
  @override
  bool get restoringSnapshot => _scanSession.restoringSnapshot;
  bool get _restoringSnapshot => _scanSession.restoringSnapshot;
  @override
  bool get targetPreviewLoading => _targetPreviewLoading;

  String get scanTargetLabel => _scanSession.scanTargetLabel;

  List<String> get permissionHints {
    final hints = _capabilities['permission_hints'];
    if (hints is List) {
      return hints.map((e) => e.toString()).toList();
    }
    return const [];
  }

  /// Elapsed wall time since scan started (updates every second while scanning).
  String? get scanElapsedLabel => _scanSession.scanElapsedLabel;

  @visibleForTesting
  int get transientFinalizeCount => _scanSession.transientFinalizeCount;

  @visibleForTesting
  void clearTransientScanStateForTest() {
    _scanSession.clearTransientScanStateForTest();
  }

  @visibleForTesting
  Future<bool> applyMergeForTest(
    String targetPath,
    Map<String, dynamic> subtreeTree,
    List<Map<String, dynamic>> subtreeEntries, {
    bool authoritative = false,
  }) {
    return _scanSession.applyMergeForTest(
      targetPath,
      subtreeTree,
      subtreeEntries,
      authoritative: authoritative,
    );
  }

  @visibleForTesting
  bool get hasTransientScanStateForTest =>
      _scanSession.hasTransientScanStateForTest;

  Future<void> _initialize() async {
    await Future<void>.delayed(Duration.zero);
    try {
      final bridge = VolwardNativeBridge.instance;
      _engineHost = bridge.createEngineHost();
      _capabilities = _engineHost!.capabilities;
      _deepScanReady = _engineHost!.deepScanReady;
      if (!bridge.hasSnapshotFileApi) {
        debugPrint(
          'Volward: bundled native library is outdated (missing snapshot file FFI). '
          'Rebuild the Rust library for this platform, then fully restart the app.',
        );
      }
      _ready = true;
      volwardAiDebugLog(
        'session ready coverage=$hasAiCoverageApi tree=$hasAiTreeCoverageApi '
        'sessionApi=$hasAiSessionApi contract=$hasAiContractApi',
      );
      await loadSessionStateIfNeeded();
      await restoreCachedSnapshotIfNeeded();
    } catch (e, st) {
      _initError = '$e';
      debugPrint('VolwardSession init failed: $e\n$st');
    }
    _notifyListeners();
  }

  String _defaultScanRoot() {
    return defaultScanRootPath(
      environment: Platform.environment,
      isWindows: () => Platform.isWindows,
    );
  }

  // Test-injectable probes for the startup-root resolver. Production code
  // never sets these; they exist so widget/session tests can simulate a
  // missing home directory or a deleted saved root without touching the real
  // filesystem layout.
  /// Overrides [_defaultScanRoot] for tests.
  String Function()? get defaultRootForTest => _scanSession.defaultRootForTest;
  set defaultRootForTest(String Function()? value) =>
      _scanSession.defaultRootForTest = value;

  /// Overrides the directory-exists check in [resolveStartupRoot] for tests.
  bool Function(String path)? get rootExistsForTest =>
      _scanSession.rootExistsForTest;
  set rootExistsForTest(bool Function(String path)? value) =>
      _scanSession.rootExistsForTest = value;

  /// Resolves the root the app should preview on launch.
  ///
  /// Priority: the persisted scan root (if it still exists on disk) → the
  /// default home directory (if that still exists) → an empty string, which
  /// tells [HomePage] to keep the folder picker visible instead of previewing
  /// a dead path. Startup must never block on a missing or stale root.
  @override
  Future<String> resolveStartupRoot() => _scanSession.resolveStartupRoot();

  @override
  Future<void> validateScanRoot(String path) =>
      _scanSession.validateScanRoot(path);

  @visibleForTesting
  Future<String> resolveStartupRootForTest() => resolveStartupRoot();

  @visibleForTesting
  Future<bool> waitForNativeScanToStopForTest(bool Function() isRunning) =>
      _scanSession.waitForNativeScanToStopForTest(isRunning);

  bool get _hasAuthoritativeSnapshot =>
      _scanSession.hasAuthoritativeSnapshotForCurrentRoot;

  @override
  bool get hasAuthoritativeSnapshotForCurrentRoot => _hasAuthoritativeSnapshot;

  /// Reload the last on-disk snapshot into memory (after hot reload / restart).
  /// Preview stubs from [previewTarget] do not count as a loaded scan.
  @override
  Future<void> restoreCachedSnapshotIfNeeded() =>
      _scanSession.restoreCachedSnapshotIfNeeded();

  @visibleForTesting
  Future<bool> restoreCachedSnapshotForTest({String? preferredPath}) =>
      _scanSession.restoreCachedSnapshotForTest(preferredPath: preferredPath);

  @override
  Future<void> loadSessionStateIfNeeded() =>
      _scanSession.loadSessionStateIfNeeded();

  static File _sessionStateFile() =>
      File('${SnapshotCache.cacheDir().path}/session.json');

  /// Path the UI is currently browsing — used as the refresh target.
  /// Set by [setCurrentDirectory] from [HomePage] column selection.
  @override
  String? get currentDirectoryPath => _catalogSession.currentDirectoryPath;

  /// The path that [refreshCurrentDirectory] will target (Design §6.1):
  /// focused subdirectory → scan root → default home.
  @override
  String get refreshTargetPath => _catalogSession.refreshTargetPath;

  /// Whether the refresh action can run for the directory currently shown.
  ///
  /// A root refresh starts the file-backed full scan and therefore needs the
  /// snapshot-file API. A child refresh is a scoped peek and does not need
  /// that API, so it remains available with an older compatible dylib.
  @override
  bool get canRefreshCurrentDirectory =>
      _catalogSession.canRefreshCurrentDirectory;

  /// Called by [HomePage] whenever the column selection changes.
  @override
  void setCurrentDirectory(String? path) =>
      _catalogSession.setCurrentDirectory(path);

  @visibleForTesting
  void setCurrentPathForTest(String path) =>
      _catalogSession.setCurrentPathForTest(path);

  @override
  void setScanRoots(List<String> roots) {
    _scanSession.setScanRoots(roots);
  }

  void setLastCustomRoot(String? path) {
    rememberCustomRoot(path);
  }

  @override
  void rememberCustomRoot(String? path) {
    _scanSession.rememberCustomRoot(path);
  }

  void clearScanRoots() {
    _scanSession.clearScanRoots();
  }

  Future<bool> pauseCurrentScanForSwitch() =>
      _scanSession.pauseCurrentScanForSwitch();

  @override
  Future<void> switchScanRoot(
    String? path, {
    bool validateBeforeSwitch = false,
  }) {
    return _scanSession.switchScanRoot(
      path,
      validateBeforeSwitch: validateBeforeSwitch,
    );
  }

  @override
  Future<void> previewTarget({int? expectedGeneration}) =>
      _scanSession.previewTarget(expectedGeneration: expectedGeneration);

  /// Query direct children of [path] from the Rust catalog index.
  ///
  /// Returns null if the index API is unavailable so callers can fall back to
  /// the tree-based path.  Called by [HomePage._visibleChildrenFor] on every
  /// cache miss so results are always fresh after [refreshCurrentDirectory].
  @override
  List<SnapshotNodeRecord>? queryDirectoryChildrenFromCatalog(
    String path, {
    String? categoryFilter,
    bool deletableOnly = false,
    String sortMode = 'size_desc',
  }) => _catalogSession.queryDirectoryChildrenFromCatalog(
    path,
    categoryFilter: categoryFilter,
    deletableOnly: deletableOnly,
    sortMode: sortMode,
  );

  /// Refreshes the currently focused directory.
  ///
  /// Subdirectories use a scoped re-scan so local filesystem changes are
  /// reflected without re-scanning the whole root. The root target falls back
  /// to the normal full scan worker so large refreshes stay file-backed rather
  /// than shipping a giant snapshot through the UI isolate.
  @override
  Future<void> refreshCurrentDirectory([String? path]) =>
      _catalogSession.refreshCurrentDirectory(path);

  /// Triggers a small, scoped scan of [path] so its contents/size become
  /// available immediately, without waiting for the background full scan
  /// to reach it. Explicit refreshes wait for an existing peek of the same
  /// path and then run once more, so a click cannot be silently lost.
  @override
  Future<bool> peekScan(String path, {bool force = false}) =>
      _scanSession.peekScan(path, force: force);

  @override
  void setIncrementalScan(bool incremental) =>
      _scanSession.setIncrementalScan(incremental);

  void setSelectedEntryIds(Set<String> ids) {
    _selectedEntryIds
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  void clearSelectedEntryIds() {
    _selectedEntryIds.clear();
    notifyListeners();
  }

  Future<void> refreshCapabilities() async {
    if (!_ready || _engine == null) return;
    _lastError = null;
    try {
      _capabilities = _engineHost!.capability.probeCapabilities();
      _deepScanReady = _engineHost!.capability.isDeepScanReady();
    } catch (e) {
      _lastError = '$e';
    }
    notifyListeners();
  }

  Future<bool> openPermissionSettings() async {
    if (!_ready || _engine == null) return false;
    _lastError = null;
    try {
      return _engineHost!.capability.openPermissionSettings();
    } catch (e) {
      _lastError = '$e';
      return false;
    }
  }

  @override
  Future<String> runScan({ScanRunMode mode = ScanRunMode.auto}) =>
      _scanSession.runScan(mode: mode);

  @override
  bool get hasAiSessionApi =>
      _ready && _engine != null && VolwardNativeBridge.instance.hasAiSessionApi;

  bool get hasAiCoverageApi =>
      _ready &&
      _engine != null &&
      (_bridgeForTest ?? VolwardNativeBridge.instance).hasAiCoverageApi;

  @override
  bool get hasAiTreeCoverageApi =>
      _ready &&
      _engine != null &&
      (_bridgeForTest ?? VolwardNativeBridge.instance).hasAiTreeCoverageApi;

  @override
  String? get currentCoverageSnapshotId => lastSnapshot?.snapshotId;

  /// True when the in-memory Rust index matches [snapshotId] and is safe for AI/coverage FFI.
  bool isAiCoverageSnapshotReady(String snapshotId) {
    if (snapshotId.isEmpty || !hasAiCoverageApi) return false;
    if (_restoringSnapshot || _scanning) return false;
    final engine = _engine;
    if (engine == null) return false;
    final bridge = VolwardNativeBridge.instance;
    if (bridge.isIndexLoading(engine)) return false;
    final snap = _lastSnapshot;
    if (snap == null || snap.snapshotId != snapshotId) return false;
    if (snap.stats['scan_state']?.toString() != 'Done') return false;
    final summary = bridge.getIndexSummaryJson(engine);
    if (summary == null) return false;
    return summary['snapshot_id']?.toString() == snapshotId;
  }

  /// On-disk catalog path for [snapshotId] (index or snapshot pb/json).
  @override
  Future<String?> catalogIndexPathForAiCoverage(String snapshotId) async {
    final byId = await SnapshotCache.catalogPathForSnapshotId(snapshotId);
    if (byId != null && byId.isNotEmpty) return byId;

    final snap = _lastSnapshot;
    if (snap == null || snap.snapshotId != snapshotId) return null;
    final root = snap.tree?.path;
    if (root == null || root.isEmpty) return null;
    final latest = await SnapshotCache.latestSnapshotPath(preferredRoot: root);
    if (latest == null) return null;
    final latestId = await SnapshotCache.snapshotIdForCatalogPath(latest);
    if (latestId == snapshotId) return latest;
    return null;
  }

  @override
  NativeCoverageEngine? get coverageEngine {
    final engine = _engine;
    if (!hasAiCoverageApi || engine == null) return null;
    return NativeCoverageEngine(
      bridge: _bridgeForTest ?? VolwardNativeBridge.instance,
      engine: engine,
      offloadHeavyCalls: _offloadCoverageForTest,
      lifetime: _engineLifetime,
    );
  }

  NativeCoverageEngine? get treeCoverageEngine {
    final engine = _engine;
    if (!hasAiTreeCoverageApi || engine == null) return null;
    return NativeCoverageEngine(
      bridge: _bridgeForTest ?? VolwardNativeBridge.instance,
      engine: engine,
      offloadHeavyCalls: _offloadCoverageForTest,
      lifetime: _engineLifetime,
    );
  }

  Future<CoveragePlanSummary?> buildTreeCoveragePlan(String snapshotId) async =>
      treeCoverageEngine?.buildTreePlan(snapshotId);

  Future<CoverageTreePage?> nextTreeCoveragePage(
    String snapshotId,
    int planVersion,
    int cursor, {
    int? pageSize,
  }) async => treeCoverageEngine?.nextTreePage(
    snapshotId,
    planVersion,
    cursor,
    pageSize: pageSize,
  );

  Future<CoverageTailPage?> nextTailCoveragePage(
    String snapshotId,
    int planVersion,
    int cursor, {
    int? pageSize,
  }) async => treeCoverageEngine?.nextTailPage(
    snapshotId,
    planVersion,
    cursor,
    pageSize: pageSize,
  );

  Future<List<CoverageTreeNode>?> expandTreeCoverageNode(
    String snapshotId,
    String dirPath,
  ) async => treeCoverageEngine?.expandTreeNode(snapshotId, dirPath);

  bool get hasAiContractApi =>
      _ready && VolwardNativeBridge.instance.hasAiContractApi;

  bool get hasAiTreeContractApi =>
      _ready && VolwardNativeBridge.instance.hasAiTreeContractApi;

  String? aiUpstreamEndpoint() {
    if (!hasAiContractApi) return null;
    return VolwardNativeBridge.instance.aiUpstreamEndpoint();
  }

  int? aiBatchSize() {
    if (!hasAiContractApi) return null;
    return VolwardNativeBridge.instance.aiBatchSize();
  }

  /// Build DeepSeek request body for analyze candidates (no `member_paths`).
  String? aiBuildRequestJson(List<Map<String, dynamic>> candidates) {
    if (!hasAiContractApi) return null;
    return VolwardNativeBridge.instance.aiBuildRequestJson(
      jsonEncode(candidates),
    );
  }

  String? aiBuildConclusionSynthesisJson(String userJson) {
    if (!hasAiContractApi) return null;
    return VolwardNativeBridge.instance.aiBuildConclusionSynthesisJson(
      userJson,
    );
  }

  /// Parse upstream body against the batch that produced it.
  List<AiVerdict>? aiParseResponseJson(
    String upstreamBody,
    List<Map<String, dynamic>> batch,
  ) {
    if (!hasAiContractApi) return null;
    final raw = VolwardNativeBridge.instance.aiParseResponseJson(
      upstreamBody,
      jsonEncode(batch),
    );
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((e) => AiVerdict.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  int? aiTreeBatchSize() {
    if (!hasAiTreeContractApi) return null;
    return VolwardNativeBridge.instance.aiTreeBatchSize();
  }

  String? aiBuildTreeRequestJson(List<Map<String, dynamic>> nodes) {
    if (!hasAiTreeContractApi) return null;
    return VolwardNativeBridge.instance.aiBuildTreeRequestJson(
      jsonEncode(nodes),
    );
  }

  List<AiVerdict>? aiParseTreeResponseJson(
    String upstreamBody,
    List<Map<String, dynamic>> batch,
  ) {
    if (!hasAiTreeContractApi) return null;
    final raw = VolwardNativeBridge.instance.aiParseTreeResponseJson(
      upstreamBody,
      jsonEncode(batch),
    );
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((e) => AiVerdict.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  String? buildAiCandidatesJson(String snapshotId) {
    final engine = _engine;
    if (!_ready || engine == null) return null;
    return VolwardNativeBridge.instance.buildAiCandidatesJson(
      engine,
      snapshotId,
    );
  }

  /// Prefer async native build so huge scans don't freeze the UI isolate.
  Future<String?> buildAiCandidatesJsonAsync(String snapshotId) async {
    final engine = _engine;
    if (!_ready || engine == null) return null;
    return AiCandidatesMaterializedCache.instance.loadOrReuse(
      snapshotId,
      () => _buildAiCandidatesJsonAsyncImpl(snapshotId, engine),
      ownerId: engine.address.toRadixString(16),
    );
  }

  Future<String?> _buildAiCandidatesJsonAsyncImpl(
    String snapshotId,
    Pointer<Void> engine,
  ) async {
    final bridge = VolwardNativeBridge.instance;
    if (!bridge.hasAsyncAiCandidatesApi) {
      debugPrint(
        'Volward: sync buildAiCandidatesJson (missing async FFI symbols — rebuild Rust dylib)',
      );
      return bridge.buildAiCandidatesJson(engine, snapshotId);
    }

    // Native build scales with unclassified volume but uses a size-ranked funnel
    // sample; do not abort early with a short client timeout on huge scans.
    const busyStartWatchdog = Duration(minutes: 5);
    // Funnel-sample candidates build is one index pass; allow headroom on huge indexes.
    const buildTimeout = Duration(minutes: 60);
    final busyStartedAt = DateTime.now();
    volwardAiDebugLog('candidates build start snapshot=$snapshotId');
    while (true) {
      final started = bridge.startBuildAiCandidatesAsync(engine, snapshotId);
      if (started == null) {
        volwardAiDebugLog('candidates build fallback to sync FFI');
        return bridge.buildAiCandidatesJson(engine, snapshotId);
      }
      if (started.startsWith('error:')) return started;
      if (started.startsWith('busy:')) {
        if (DateTime.now().difference(busyStartedAt) > busyStartWatchdog) {
          return 'error:ai candidates build busy (prior build did not finish)';
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }
      break;
    }

    final buildWaitStarted = DateTime.now();
    var lastHeartbeat = buildWaitStarted;
    while (bridge.isAiCandidatesBuilding(engine)) {
      final now = DateTime.now();
      if (now.difference(buildWaitStarted) > buildTimeout) {
        return 'error:ai candidates build timed out after ${buildTimeout.inMinutes} minutes';
      }
      if (now.difference(lastHeartbeat) >= const Duration(seconds: 5)) {
        volwardAiDebugLog(
          'candidates build still running '
          '${now.difference(buildWaitStarted).inSeconds}s '
          '(large index scans can take several minutes)',
        );
        lastHeartbeat = now;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    volwardAiDebugLog(
      'candidates build native finished in '
      '${DateTime.now().difference(buildWaitStarted).inSeconds}s',
    );
    final spillPath = bridge.takeAiCandidatesSpillPath(engine);
    if (spillPath != null &&
        spillPath.isNotEmpty &&
        !spillPath.startsWith('error:')) {
      // Pass path only — reading multi‑MB JSON here copies it onto the UI isolate.
      return 'spill:$spillPath';
    }
    final inline = bridge.getAiCandidatesJson(engine);
    if (inline != null &&
        inline.length > 512 * 1024 &&
        !inline.startsWith('error:')) {
      debugPrint(
        'Volward: large inline candidates payload (${inline.length} bytes) — '
        'prefer async spill build; UI may stutter',
      );
    }
    return inline;
  }

  bool saveAiResultJson(String snapshotId, String resultJson) {
    final engine = _engine;
    if (!_ready || engine == null) return false;
    return VolwardNativeBridge.instance.saveAiResultJson(
      engine,
      snapshotId,
      resultJson,
    );
  }

  /// Saved AI analysis JSON for [snapshotId], or null / `error:…` on failure.
  String? loadAiResultJson(String snapshotId) {
    final engine = _engine;
    if (!_ready || engine == null) return null;
    return VolwardNativeBridge.instance.loadAiResultJson(engine, snapshotId);
  }

  @override
  Future<Map<String, dynamic>> deleteEntries(
    List<String> targets, {
    String? expectedSnapshotId,
    bool dryRun = false,
    bool rescanAfterDelete = false,
    String? refreshPath,
    Map<String, String>? targetPathById,
  }) => _deletionSession.deleteEntries(
    targets,
    expectedSnapshotId: expectedSnapshotId,
    dryRun: dryRun,
    rescanAfterDelete: rescanAfterDelete,
    refreshPath: refreshPath,
    targetPathById: targetPathById,
  );

  @visibleForTesting
  void applySuccessfulDeleteOverlayForTest(
    String directoryPath,
    List<String> targets,
    Map<String, dynamic> report, {
    Map<String, String>? targetPathById,
  }) => _deletionSession.applyOverlayForTest(
    directoryPath,
    targets,
    report,
    targetPathById: targetPathById,
  );

  @override
  Future<Map<String, dynamic>> emptyTrash({bool rescanAfterEmpty = true}) =>
      _deletionSession.emptyTrash(rescanAfterEmpty: rescanAfterEmpty);

  @override
  void cancelScan() => _scanSession.cancelScan();

  @override
  void dispose() {
    _deletionSession.detachOwner();
    if (_scanning) {
      cancelScan();
    } else {
      _scanSession.clearTransientState();
    }
    final scanNotifications = _scanSessionNotificationsSub;
    _scanSessionNotificationsSub = null;
    if (scanNotifications != null) {
      unawaited(scanNotifications.cancel());
    }
    _catalogSession.removeListener(_notifyListeners);
    _deletionSession.removeListener(_notifyListeners);
    _catalogSession.dispose();
    _deletionSession.dispose();
    _scanSession.dispose();
    _engineHost?.dispose();
    _testPortHost?.dispose();
    super.dispose();
  }

  // ── Capability analysis (Lemon-style storage capabilities) ─────────────

  bool get hasCapabilityApi => _capabilitySession.hasCapabilityApi;

  /// Synchronous capability analysis against the current snapshot. Returns
  /// the typed result, or throws [StateError] / [FormatException] on failure.
  Future<CapabilityAnalysisResult> analyzeCapability({
    required String snapshotId,
    required Capability capability,
    AnalysisOptions? options,
  }) => _capabilitySession.analyzeCapability(
    snapshotId: snapshotId,
    capability: capability,
    options: options,
  );

  /// Starts an async capability job and returns its job id.
  String startCapabilityAnalysis({
    required String snapshotId,
    required Capability capability,
    AnalysisOptions? options,
  }) => _capabilitySession.startCapabilityAnalysis(
    snapshotId: snapshotId,
    capability: capability,
    options: options,
  );

  /// Reads the current typed status of a capability job.
  CapabilityJobStatus getCapabilityJobStatus(String jobId) =>
      _capabilitySession.getCapabilityJobStatus(jobId);

  /// Requests cancellation of an in-flight capability job.
  bool cancelCapabilityAnalysis(String jobId) =>
      _capabilitySession.cancelCapabilityAnalysis(jobId);

  /// Polls a capability job until it reaches a terminal state, yielding each
  /// progress snapshot. Use [getCapabilityJobStatus] for the final typed
  /// result after the stream completes.
  Stream<CapabilityAnalysisProgress> watchCapabilityJob(
    String jobId, {
    Duration pollInterval = const Duration(milliseconds: 300),
  }) =>
      _capabilitySession.watchCapabilityJob(jobId, pollInterval: pollInterval);
}
