import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'ai/ai_provider.dart';
import 'analytics/analytics.dart';
import 'analytics/analytics_events.dart';
import 'bridge/native_bridge.dart';
import 'bridge/scan_worker.dart';
import 'capabilities/capability_models.dart';
import 'capabilities/capability_result_cache.dart';
import 'proto/snapshot_pb_decoder.dart';
import 'scan_entry_record.dart';
import 'scan_preview.dart';
import 'scan_tree.dart';
import 'scan_snapshot_merge.dart';
import 'scan_snapshot_state.dart';
import 'snapshot_cache.dart';
import 'snapshot_query.dart';

/// Thrown when the user cancels an in-progress scan.
class ScanCancelledException implements Exception {
  ScanCancelledException([this.message = 'Scan cancelled']);
  final String message;

  @override
  String toString() => message;
}

enum _RootSwitchContinuation { previewOnly, forcePeek, fullScan }

@immutable
class ScanProgressViewState {
  const ScanProgressViewState({this.phase, this.fraction});

  final String? phase;
  final double? fraction;

  @override
  bool operator ==(Object other) {
    return other is ScanProgressViewState &&
        other.phase == phase &&
        other.fraction == fraction;
  }

  @override
  int get hashCode => Object.hash(phase, fraction);
}

class _ScanProgressBand {
  const _ScanProgressBand({
    required this.start,
    required this.end,
    required this.duration,
  });

  final double start;
  final double end;
  final Duration duration;
}

_ScanProgressBand _scanProgressBandFor(String? phase) {
  return switch (phase) {
    'DiscoveringRoots' => const _ScanProgressBand(
      start: 0.0,
      end: 0.04,
      duration: Duration(seconds: 2),
    ),
    'Walking' => const _ScanProgressBand(
      start: 0.04,
      end: 0.86,
      duration: Duration(minutes: 4),
    ),
    'Classifying' => const _ScanProgressBand(
      start: 0.86,
      end: 0.93,
      duration: Duration(seconds: 25),
    ),
    'Aggregating' => const _ScanProgressBand(
      start: 0.93,
      end: 0.97,
      duration: Duration(seconds: 15),
    ),
    'SavingResults' => const _ScanProgressBand(
      start: 0.97,
      end: 0.99,
      duration: Duration(seconds: 8),
    ),
    'LoadingResults' => const _ScanProgressBand(
      start: 0.99,
      end: 0.995,
      duration: Duration(seconds: 4),
    ),
    _ => const _ScanProgressBand(
      start: 0.0,
      end: 0.99,
      duration: Duration(minutes: 4),
    ),
  };
}

@visibleForTesting
double? estimateScanFraction({
  required bool scanning,
  required String? phase,
  required DateTime? scanStartedAt,
  required DateTime now,
}) {
  if (!scanning) return null;
  if (phase == 'Done') return 1.0;

  final startedAt = scanStartedAt;
  if (startedAt == null) return 0.0;

  final band = _scanProgressBandFor(phase);
  final elapsedMs = now.difference(startedAt).inMilliseconds;
  final phaseProgress = elapsedMs <= 0
      ? 0.0
      : elapsedMs / (elapsedMs + band.duration.inMilliseconds);
  final estimated = band.start + (band.end - band.start) * phaseProgress;
  return estimated.clamp(0.0, 0.99).toDouble();
}

/// Holds the native Volward engine pointer and exposes async wrappers for UI.
class VolwardSession extends ChangeNotifier {
  VolwardSession() {
    _initialize();
    instance = this;
  }

  VolwardSession.test() : _ready = true, _persistSessionStateEnabled = false;

  /// Global reference set when the singleton is constructed.
  /// Used by [SnapshotCatalog.queryNode] to access the catalog fast path
  /// without requiring an explicit parameter thread-through.
  static VolwardSession? instance;

  Pointer<Void>? _engine;
  bool _ready = false;
  String? _initError;
  String? _lastError;
  Map<String, dynamic> _capabilities = {};
  bool _deepScanReady = false;
  bool _scanning = false;
  bool _deleting = false;
  String? _lastJobId;
  ScanSnapshotState? _lastSnapshot;
  Map<String, dynamic>? _lastDeleteReport;
  Map<String, dynamic>? _scanProgress;
  List<String> _scanRoots = [];
  String? _lastCustomRoot;
  List<String> _recentCustomRoots = [];
  bool _incrementalScan = false;
  final Set<String> _selectedEntryIds = {};
  final Set<String> _peekInFlight = {};
  final Set<String> _peekCompleted = {};
  final Map<String, Completer<void>> _pendingForcedPeeks = {};
  final Map<String, int> _peekOperationTokens = {};
  int _nextPeekOperationToken = 0;
  static const int _maxConcurrentPeeks = 2;
  static const int _maxPreviewEntries = 2000;
  static const int _maxAutoRestoreBytes = 128 * 1024 * 1024;
  int _snapshotVersion = 0;
  final Set<String> _invalidatedPrefixes = {};
  final Map<String, ScanTreeNode> _directoryOverlays = {};
  final Set<String> _refreshingDirectoryPaths = {};
  final Set<String> _postDeleteRefreshPaths = {};
  final Map<String, String> _refreshErrors = {};
  final CapabilityAnalysisCache _capabilityCache = CapabilityAnalysisCache();
  // Monotonic token for root switches. If the user picks folders quickly, only
  // the latest preview/scan handoff may update the visible snapshot.
  int _rootSwitchGeneration = 0;
  int _rootSwitchRequestGeneration = 0;

  // ── Catalog-backed current-directory state (Design §6.1) ──────────────────
  // Tracks the currently browsed directory path for targeted refresh.
  // Updated by HomePage via setCurrentDirectory(); falls back to scan root.
  String? _currentDirectoryPath;

  // Test-only probe: the catalog-backed flow should never hydrate a full
  // Dart snapshot back into Rust before refresh/scan.
  @visibleForTesting
  bool didAttemptHydration = false;
  // Throttle display-update notifications from _applyMerge. Checkpoints can
  // arrive 5-10×/sec; rebuilding the full widget tree that often is the primary
  // source of UI jank. We still update _lastSnapshot on every checkpoint for
  // correctness; we just batch the UI wake-ups to ≤ 1 per _kDisplayNotifyGap.
  DateTime? _lastApplyMergeNotify;
  static const Duration _kDisplayNotifyGap = Duration(milliseconds: 700);
  // Exposes the scan elapsed label as a ValueNotifier so the sticky bar can
  // react to the 1-Hz tick independently without triggering a full page rebuild.
  final ValueNotifier<String?> scanElapsedNotifier = ValueNotifier(null);
  // Estimated directory-scan progress (0–1, or null when hidden). Driven by
  // scan phase + elapsed time so it advances smoothly without walking the
  // full tree on every checkpoint.
  final ValueNotifier<double?> scannedFractionNotifier = ValueNotifier(null);
  final ValueNotifier<ScanProgressViewState> scanProgressNotifier =
      ValueNotifier(const ScanProgressViewState());
  SendPort? _workerCancelPort;
  Timer? _scanElapsedTimer;
  DateTime? _scanStartedAt;
  int _transientFinalizeCount = 0;
  int _notificationBatchDepth = 0;
  bool _notificationBatchPending = false;
  @visibleForTesting
  Future<ScanSnapshotState?> Function(String jobId, List<String> roots)?
  scanRunnerForTest;
  @visibleForTesting
  Map<String, dynamic> Function(
    String snapshotId,
    List<String> targets,
    bool dryRun,
  )?
  deleteRunnerForTest;
  @visibleForTesting
  Future<void> Function(String path)? directoryRefreshRunnerForTest;
  @visibleForTesting
  Future<List<Map<String, dynamic>>> Function(String path)?
  scanRootPreviewReaderForTest;
  @visibleForTesting
  String Function(String snapshotId, String capability, String optionsJson)?
  capabilityAnalyzeRunnerForTest;
  @visibleForTesting
  String Function(String snapshotId, String capability, String optionsJson)?
  capabilityStartRunnerForTest;
  @visibleForTesting
  String Function(String jobId)? capabilityStatusReaderForTest;
  @visibleForTesting
  bool Function(String jobId)? capabilityCancelRunnerForTest;

  Completer<ScanSnapshotState?>? _activeScanCompleter;
  StreamSubscription<dynamic>? _scanProgressSub;
  ReceivePort? _scanReceivePort;
  ReceivePort? _scanCancelInitPort;
  bool _scanChannelsClosed = false;
  DateTime? _lastScanActivityAt;
  DateTime? _savingPhaseStartedAt;
  DateTime? _lastNativeProgressNotifyAt;
  String? _lastNativeProgressPhase;
  bool _scanRunningOnMainEngine = false;
  bool _scanCancelRequested = false;
  bool _targetPreviewLoading = false;
  DateTime? _targetPreviewStartedAt;
  int _cacheRestoreGeneration = 0;
  Completer<void>? _cacheRestoreCompleter;
  bool _sessionStateLoaded = false;
  Future<void>? _sessionStateLoadFuture;
  bool _persistSessionStateEnabled = true;
  @visibleForTesting
  File? sessionStateFileForTest;
  @visibleForTesting
  Future<String> Function(File file)? sessionStateReaderForTest;

  /// Fail only when progress stalls during walk/classify (not total wall time).
  static const Duration _scanStallTimeout = Duration(minutes: 20);

  /// Allow long JSON serialize/deserialize after walk completes.
  static const Duration _scanSaveLoadTimeout = Duration(hours: 2);

  /// Safety net for runaway scans; normal Home scans should finish well below this.
  static const Duration _scanAbsoluteMax = Duration(hours: 8);

  /// Cap cache restore wait so a bad or huge local cache does not pin the UI.
  static const Duration _cacheRestoreTimeout = Duration(seconds: 8);

  static const Duration _minTargetPreviewLoading = Duration(milliseconds: 180);

  /// Maximum time before requesting cancellation of a peek-scan isolate.
  /// The path remains in-flight until the worker confirms shutdown, preventing
  /// a timed-out native scan from overlapping a retry of the same subtree.
  static const Duration _peekScanTimeout = Duration(seconds: 60);

  bool get ready => _ready;
  String? get initError => _initError;
  String? get lastError => _lastError;
  Map<String, dynamic> get capabilities => _capabilities;
  bool get deepScanReady => _deepScanReady;
  bool get scanning => _scanning;
  bool get deleting => _deleting;
  String? get lastJobId => _lastJobId;

  /// True when the bundled dylib supports catalog index query/refresh APIs.
  bool get hasIndexApi {
    // Guard: if the engine hasn't been initialised yet (e.g. in unit tests via
    // VolwardSession.test()), return false rather than attempting to dlopen the
    // dylib, which would crash in environments without the native library.
    if (!_ready || _engine == null) return false;
    return VolwardNativeBridge.instance.hasIndexApi;
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
  int get catalogVersion {
    final engine = _engine;
    final rustVersion = (engine != null && hasIndexApi)
        ? VolwardNativeBridge.instance.indexVersion(engine)
        : 0;
    // XOR-combine so either dimension changing produces a new value.
    return rustVersion ^ (_snapshotVersion << 20);
  }

  ScanSnapshotState? get lastSnapshot => _lastSnapshot;
  Map<String, dynamic>? get lastDeleteReport => _lastDeleteReport;
  Map<String, dynamic>? get scanProgress => _scanProgress;
  List<String> get scanRoots => List.unmodifiable(_scanRoots);
  String? get lastCustomRoot => _recentCustomRoots.isNotEmpty
      ? _recentCustomRoots.first
      : _lastCustomRoot;
  List<String> get recentCustomRoots => List.unmodifiable(
    _recentCustomRoots.isNotEmpty
        ? _recentCustomRoots
        : [
            if (_lastCustomRoot != null && _lastCustomRoot!.isNotEmpty)
              _lastCustomRoot!,
          ],
  );
  bool get incrementalScan => _incrementalScan;
  Set<String> get selectedEntryIds => Set.unmodifiable(_selectedEntryIds);

  int get snapshotVersion => _snapshotVersion;
  int get rootSwitchGeneration => _rootSwitchGeneration;

  Set<String> get invalidatedPrefixes => Set.unmodifiable(_invalidatedPrefixes);

  /// Latest authoritative filesystem result for a directory peek. Index-mode
  /// snapshots intentionally keep only root metadata in Dart, so these local
  /// overlays are the source of truth for refreshed directories until the
  /// next full scan replaces the catalog.
  ScanTreeNode? directoryOverlayForPath(String path) =>
      _directoryOverlays[ScanTreeBuilder.normalizeRoot(path)];

  Set<String> get refreshingDirectoryPaths =>
      Set.unmodifiable(_refreshingDirectoryPaths);

  bool get postDeleteRefreshPending => _postDeleteRefreshPaths.isNotEmpty;

  bool isDirectoryRefreshing(String path) =>
      _refreshingDirectoryPaths.contains(ScanTreeBuilder.normalizeRoot(path));

  String? refreshErrorForPath(String path) =>
      _refreshErrors[ScanTreeBuilder.normalizeRoot(path)];

  Set<String> consumeInvalidatedPrefixes() {
    final prefixes = Set<String>.from(_invalidatedPrefixes);
    _invalidatedPrefixes.clear();
    return prefixes;
  }

  void _notifyListeners() {
    if (_notificationBatchDepth > 0) {
      _notificationBatchPending = true;
      return;
    }
    notifyListeners();
  }

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

  void _cancelPendingForcedPeeks() {
    final pending = _pendingForcedPeeks.values.toList(growable: false);
    _pendingForcedPeeks.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.complete();
    }
  }

  @visibleForTesting
  void setSnapshotForTest(ScanSnapshotState snapshot) {
    _lastSnapshot = snapshot;
    _invalidateCapabilityCacheFor(snapshot.snapshotId);
    _directoryOverlays.clear();
    _snapshotVersion++;
    _invalidatedPrefixes.clear();
    _notifyListeners();
  }

  @visibleForTesting
  void primeTransientScanStateForTest({
    Map<String, dynamic>? progress,
    bool scanning = true,
    bool openScanPorts = true,
    String? lastJobId,
  }) {
    _scanProgress = progress == null
        ? null
        : Map<String, dynamic>.from(progress);
    _scanning = scanning;
    _scanStartedAt = scanning ? DateTime.utc(2026, 8, 3) : null;
    _lastJobId = lastJobId;
    _workerCancelPort = null;
    final completer = Completer<ScanSnapshotState?>();
    completer.future.catchError((Object _) => null);
    _activeScanCompleter = completer;
    _scanRunningOnMainEngine = false;
    _scanCancelRequested = false;
    _scanChannelsClosed = !openScanPorts;
    if (openScanPorts) {
      _scanReceivePort = ReceivePort();
      _scanCancelInitPort = ReceivePort();
    } else {
      _scanReceivePort = null;
      _scanCancelInitPort = null;
    }
    _lastScanActivityAt = null;
    _savingPhaseStartedAt = null;
    _lastNativeProgressNotifyAt = null;
    _lastNativeProgressPhase = null;
    _publishScanProgress();
  }

  @visibleForTesting
  void updateScanProgressForTest(Map<String, dynamic> progress) {
    _scanProgress = Map<String, dynamic>.from(progress);
    _publishScanProgress();
  }

  @visibleForTesting
  void updateSnapshotForTest(
    ScanSnapshotState snapshot, {
    required String affectedPrefix,
  }) {
    _lastSnapshot = snapshot;
    _invalidateCapabilityCacheFor(snapshot.snapshotId);
    _directoryOverlays.clear();
    _snapshotVersion++;
    _invalidatedPrefixes
      ..removeWhere(
        (prefix) => SnapshotCache.invalidatesPrefix(
          cachedPath: prefix,
          cachedVersion: _snapshotVersion,
          affectedPrefix: affectedPrefix,
          updateVersion: _snapshotVersion,
        ),
      )
      ..add(affectedPrefix);
    notifyListeners();
  }

  /// Paths for which a peek scan is currently in flight.
  /// Empty when no peek is running (or when a full scan hasn't started yet).
  Set<String> get peekInFlight => Set.unmodifiable(_peekInFlight);

  /// Fraction of directories in the current tree that have been scanned
  /// (0.0–1.0). This is an estimated progress bar derived from the active scan
  /// phase and elapsed time rather than a tree-wide directory-count ratio.
  /// Returns null when a scan is not running.
  ///
  /// Prefer listening to [scannedFractionNotifier] for UI that should update
  /// when the estimate ticks forward (without a full page notify).
  double? get scannedFraction {
    return estimateScanFraction(
      scanning: _scanning,
      phase: _scanProgress?['phase']?.toString() ?? 'DiscoveringRoots',
      scanStartedAt: _scanStartedAt,
      now: DateTime.now(),
    );
  }

  /// Pushes [scannedFraction] into [scannedFractionNotifier] only when the
  /// value actually changes — keeps progress-bar rebuilds cheap.
  void _publishScanProgress() {
    final fraction = scannedFraction;
    if (scannedFractionNotifier.value != fraction) {
      scannedFractionNotifier.value = fraction;
    }
    final next = ScanProgressViewState(
      phase: _scanning ? (_scanProgress?['phase']?.toString()) : null,
      fraction: fraction,
    );
    if (scanProgressNotifier.value != next) {
      scanProgressNotifier.value = next;
    }
  }

  /// Whether the bundled native library supports file-based snapshot I/O.
  bool get hasSnapshotFileApi {
    // Same guard as [hasIndexApi]: in unit tests the engine is null, and
    // touching the bridge singleton would attempt to dlopen the dylib and
    // crash in environments without the native library.
    if (!_ready || _engine == null) return false;
    return VolwardNativeBridge.instance.hasSnapshotFileApi;
  }

  /// Whether the bundled native library supports incremental scan options.
  bool get hasScanOptionsApi {
    if (!_ready || _engine == null) return false;
    return VolwardNativeBridge.instance.hasScanOptionsApi;
  }

  /// Increment scan requires both snapshot file API and scan options FFI.
  bool get canUseIncrementalScan => hasSnapshotFileApi && hasScanOptionsApi;

  /// True while loading a previously saved scan from disk cache.
  bool get restoringSnapshot => _restoringSnapshot;
  bool _restoringSnapshot = false;
  bool get targetPreviewLoading => _targetPreviewLoading;

  String get scanTargetLabel =>
      _scanRoots.isEmpty ? 'Home (default)' : _scanRoots.join(', ');

  List<String> get permissionHints {
    final hints = _capabilities['permission_hints'];
    if (hints is List) {
      return hints.map((e) => e.toString()).toList();
    }
    return const [];
  }

  /// Elapsed wall time since scan started (updates every second while scanning).
  String? get scanElapsedLabel {
    if (!_scanning || _scanStartedAt == null) return null;
    final elapsed = DateTime.now().difference(_scanStartedAt!);
    final m = elapsed.inMinutes;
    final s = elapsed.inSeconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  void _startScanElapsedTimer() {
    _scanStartedAt = DateTime.now();
    scanElapsedNotifier.value = scanElapsedLabel;
    _publishScanProgress();
    _scanElapsedTimer?.cancel();
    _scanElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_scanning) {
        // Only update the elapsed label — don't fire a full notifyListeners()
        // which would rebuild the entire page on every tick.
        scanElapsedNotifier.value = scanElapsedLabel;
        _publishScanProgress();
      }
    });
  }

  void _stopScanElapsedTimer() {
    _scanElapsedTimer?.cancel();
    _scanElapsedTimer = null;
    _scanStartedAt = null;
    scanElapsedNotifier.value = null;
  }

  bool get _hasScanTransientState =>
      _scanProgress != null ||
      _lastJobId != null ||
      _workerCancelPort != null ||
      _activeScanCompleter != null ||
      _scanReceivePort != null ||
      _scanCancelInitPort != null ||
      _scanElapsedTimer != null ||
      _scanStartedAt != null ||
      _lastScanActivityAt != null ||
      _savingPhaseStartedAt != null ||
      _lastNativeProgressNotifyAt != null ||
      _lastNativeProgressPhase != null ||
      _scanCancelRequested ||
      _scanRunningOnMainEngine ||
      !_scanChannelsClosed ||
      scanRunnerForTest != null;

  void _clearScanTransientState() {
    _closeScanChannels();
    _scanProgress = null;
    _lastJobId = null;
    _workerCancelPort = null;
    _activeScanCompleter = null;
    _scanRunningOnMainEngine = false;
    _scanCancelRequested = false;
    _lastScanActivityAt = null;
    _savingPhaseStartedAt = null;
    _lastNativeProgressNotifyAt = null;
    _lastNativeProgressPhase = null;
    _lastApplyMergeNotify = null;
    scanRunnerForTest = null;
  }

  /// Idempotent: safe if both [cancelScan] and `runScan`/`finally` call it.
  void _finalizeScanTransientState() {
    if (!_hasScanTransientState) return;
    _transientFinalizeCount++;
    _clearScanTransientState();
    _stopScanElapsedTimer();
    _publishScanProgress();
  }

  @visibleForTesting
  int get transientFinalizeCount => _transientFinalizeCount;

  @visibleForTesting
  void clearTransientScanStateForTest() {
    _scanning = false;
    _finalizeScanTransientState();
  }

  @visibleForTesting
  Future<bool> applyMergeForTest(
    String targetPath,
    Map<String, dynamic> subtreeTree,
    List<Map<String, dynamic>> subtreeEntries, {
    bool authoritative = false,
  }) {
    return _applyMerge(
      targetPath,
      subtreeTree,
      subtreeEntries,
      authoritative: authoritative,
    );
  }

  @visibleForTesting
  bool get hasTransientScanStateForTest =>
      _scanning ||
      _scanStartedAt != null ||
      _workerCancelPort != null ||
      _activeScanCompleter != null ||
      _scanReceivePort != null ||
      _scanCancelInitPort != null ||
      _scanElapsedTimer != null ||
      _scanProgress != null ||
      _lastScanActivityAt != null ||
      _savingPhaseStartedAt != null ||
      _lastNativeProgressNotifyAt != null ||
      _lastNativeProgressPhase != null ||
      _scanCancelRequested ||
      _scanRunningOnMainEngine ||
      !_scanChannelsClosed ||
      scanRunnerForTest != null;

  void _setScanProgressPhase(String phase, {int? pathsSeen}) {
    _touchScanActivity(phase: phase);
    _scanProgress = {
      'phase': phase,
      if (pathsSeen != null) 'paths_seen': pathsSeen,
      if (_scanProgress?['paths_seen'] != null && pathsSeen == null)
        'paths_seen': _scanProgress!['paths_seen'],
    };
    _publishScanProgress();
    _notifyListeners();
  }

  void _touchScanActivity({String? phase}) {
    _lastScanActivityAt = DateTime.now();
    if (phase == 'SavingResults' || phase == 'LoadingResults') {
      _savingPhaseStartedAt ??= _lastScanActivityAt;
    }
  }

  Future<T?> _awaitScanWithStallGuard<T>(Future<T?> future) async {
    final started = DateTime.now();
    _touchScanActivity();

    while (true) {
      try {
        return await future.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        final now = DateTime.now();
        if (now.difference(started) > _scanAbsoluteMax) {
          throw TimeoutException(
            'Scan exceeded ${_scanAbsoluteMax.inHours}-hour limit',
            _scanAbsoluteMax,
          );
        }

        if (_savingPhaseStartedAt != null) {
          if (now.difference(_savingPhaseStartedAt!) > _scanSaveLoadTimeout) {
            throw TimeoutException(
              'Saving or loading results exceeded '
              '${_scanSaveLoadTimeout.inHours}-hour limit',
              _scanSaveLoadTimeout,
            );
          }
          continue;
        }

        final last = _lastScanActivityAt ?? started;
        if (now.difference(last) > _scanStallTimeout) {
          throw TimeoutException(
            'Scan stalled (no progress for ${_scanStallTimeout.inMinutes} minutes)',
            _scanStallTimeout,
          );
        }
      }
    }
  }

  void _closeScanChannels() {
    if (_scanChannelsClosed) return;
    _scanChannelsClosed = true;
    _scanProgressSub?.cancel();
    _scanProgressSub = null;
    _scanReceivePort?.close();
    _scanReceivePort = null;
    _scanCancelInitPort?.close();
    _scanCancelInitPort = null;
  }

  Future<void> _initialize() async {
    await Future<void>.delayed(Duration.zero);
    try {
      final bridge = VolwardNativeBridge.instance;
      _engine = bridge.createEngine();
      _capabilities = bridge.probeCapabilities(_engine!);
      _deepScanReady = bridge.isDeepScanReady(_engine!);
      if (!bridge.hasSnapshotFileApi) {
        debugPrint(
          'Volward: bundled native library is outdated (missing snapshot file FFI). '
          'Rebuild the Rust library for this platform, then fully restart the app.',
        );
      }
      _ready = true;
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
  String Function()? defaultRootForTest;

  /// Overrides the directory-exists check in [resolveStartupRoot] for tests.
  bool Function(String path)? rootExistsForTest;

  /// Resolves the root the app should preview on launch.
  ///
  /// Priority: the persisted scan root (if it still exists on disk) → the
  /// default home directory (if that still exists) → an empty string, which
  /// tells [HomePage] to keep the folder picker visible instead of previewing
  /// a dead path. Startup must never block on a missing or stale root.
  Future<String> resolveStartupRoot() async {
    Future<bool> exists(String path) async {
      final probe = rootExistsForTest;
      if (probe != null) return probe(path);
      return Directory(path).exists();
    }

    if (_scanRoots.isNotEmpty) {
      final saved = ScanTreeBuilder.normalizeRoot(_scanRoots.first);
      if (saved.isNotEmpty && await exists(saved)) return saved;
    }
    final home = defaultRootForTest?.call() ?? _defaultScanRoot();
    if (home.isNotEmpty && await exists(home)) {
      return ScanTreeBuilder.normalizeRoot(home);
    }
    return '';
  }

  Future<void> validateScanRoot(String path) async {
    final normalized = ScanTreeBuilder.normalizeRoot(path);
    final probe = rootExistsForTest;
    if (probe != null) {
      if (!probe(normalized)) {
        throw FileSystemException('Scan target does not exist', normalized);
      }
      return;
    }

    final directory = Directory(normalized);
    if (!await directory.exists()) {
      throw FileSystemException('Scan target does not exist', normalized);
    }
    try {
      await directory.list(followLinks: false).take(1).drain<void>();
    } on FileSystemException {
      rethrow;
    } catch (error) {
      throw FileSystemException(
        'Scan target is not accessible: $error',
        normalized,
      );
    }
  }

  @visibleForTesting
  Future<String> resolveStartupRootForTest() => resolveStartupRoot();

  bool get _hasAuthoritativeSnapshot {
    final snapshot = _lastSnapshot;
    if (snapshot == null || snapshot.snapshotId.startsWith('preview-')) {
      return false;
    }
    final treePath = snapshot.tree?.path;
    if (treePath == null || treePath.isEmpty) return false;
    return ScanTreeBuilder.normalizeRoot(treePath) ==
        ScanTreeBuilder.normalizeRoot(_preferredRestoreRoot());
  }

  bool get hasAuthoritativeSnapshotForCurrentRoot => _hasAuthoritativeSnapshot;

  String _preferredRestoreRoot() {
    return _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot();
  }

  /// Reload the last on-disk snapshot into memory (after hot reload / restart).
  /// Preview stubs from [previewTarget] do not count as a loaded scan.
  Future<void> restoreCachedSnapshotIfNeeded() async {
    if (!_ready || _hasAuthoritativeSnapshot || _scanning) {
      return;
    }
    final inFlight = _cacheRestoreCompleter;
    if (inFlight != null) {
      await inFlight.future;
      if (_hasAuthoritativeSnapshot || _scanning || !_ready) {
        return;
      }
    }

    final completer = Completer<void>();
    _cacheRestoreCompleter = completer;
    try {
      await _restoreCachedSnapshot();
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
      if (identical(_cacheRestoreCompleter, completer)) {
        _cacheRestoreCompleter = null;
      }
    }
  }

  Future<bool> _restoreCachedSnapshot() async {
    if (!_ready || _scanning) return false;
    _restoringSnapshot = true;
    notifyListeners();
    var restoredSnapshot = false;
    try {
      await loadSessionStateIfNeeded();
      final generation = ++_cacheRestoreGeneration;

      final preferredRoot = _preferredRestoreRoot();
      final path = await SnapshotCache.latestSnapshotPath(
        preferredRoot: preferredRoot,
      );
      if (path == null) return false;
      if (generation != _cacheRestoreGeneration) return false;
      if (ScanTreeBuilder.normalizeRoot(_preferredRestoreRoot()) !=
          ScanTreeBuilder.normalizeRoot(preferredRoot)) {
        return false;
      }

      ScanSnapshotState? restored;
      if (hasIndexApi) {
        // Always try the Rust catalog loader before applying the Dart JSON
        // size guard. New dylibs do the load on a Rust worker thread so large
        // legacy snapshots do not block Flutter's main isolate.
        restored = await _restoreIndexCache(path, generation);
        if (generation != _cacheRestoreGeneration) {
          return false;
        }
      }
      if (restored == null) {
        final cacheFile = File(path);
        try {
          final size = await cacheFile.length();
          if (size > _maxAutoRestoreBytes) {
            debugPrint(
              'VolwardSession: skip Dart snapshot restore for oversized cache '
              '$path (${size ~/ (1024 * 1024)} MB)',
            );
            return false;
          }
        } catch (_) {
          return false;
        }
        restored = await Isolate.run(() => _restoreSnapshotStateFile(path));
      }
      if (restored == null) return false;
      if (generation != _cacheRestoreGeneration) return false;
      final restoredRoot = restored.tree?.path;
      if (restoredRoot == null ||
          ScanTreeBuilder.normalizeRoot(restoredRoot) !=
              ScanTreeBuilder.normalizeRoot(_preferredRestoreRoot())) {
        return false;
      }
      _lastSnapshot = restored;
      restoredSnapshot = true;
      _logSnapshotMemoryState('restore');
      debugPrint('VolwardSession: restored cached snapshot from $path');
    } catch (e, st) {
      debugPrint('VolwardSession: restore cached snapshot failed: $e\n$st');
    } finally {
      _restoringSnapshot = false;
      _notifyListeners();
    }
    return restoredSnapshot;
  }

  Future<ScanSnapshotState?> _restoreIndexCache(
    String path,
    int generation,
  ) async {
    final engine = _engine;
    if (engine == null) return null;
    final bridge = VolwardNativeBridge.instance;
    final cacheSize = await _fileSizeOrNull(path);
    if (generation != _cacheRestoreGeneration) return null;

    if (bridge.hasAsyncIndexLoadApi) {
      final startedAt = DateTime.now();
      while (generation == _cacheRestoreGeneration) {
        if (DateTime.now().difference(startedAt) > _cacheRestoreTimeout) {
          bridge.invalidateIndexLoad(engine);
          debugPrint(
            'VolwardSession: cache restore timed out after '
            '${_cacheRestoreTimeout.inSeconds}s for $path',
          );
          return null;
        }
        bridge.invalidateIndexLoad(engine);
        final started = bridge.startLoadIndexFromPathAsync(engine, path);
        if (started == null || started.startsWith('error:')) {
          debugPrint(
            'VolwardSession: async index restore failed to start: $started',
          );
          return null;
        }
        if (started.startsWith('busy:')) {
          await _waitForIndexLoadDrain(generation);
          continue;
        }

        final drained = await _waitForIndexLoadDrain(generation);
        if (!drained) {
          bridge.invalidateIndexLoad(engine);
          return null;
        }
        break;
      }
      if (generation != _cacheRestoreGeneration) return null;

      final error = bridge.getLastIndexLoadError(engine);
      if (error != null && error.isNotEmpty) {
        debugPrint('VolwardSession: async index restore failed: $error');
        return null;
      }
    } else {
      if (cacheSize != null && cacheSize > _maxAutoRestoreBytes) {
        debugPrint(
          'VolwardSession: skip synchronous index restore for oversized cache '
          '$path (${cacheSize ~/ (1024 * 1024)} MB). '
          'Rebuild Rust to enable async cache restore.',
        );
        return null;
      }
      final loaded = bridge.loadIndexFromPath(engine, path);
      if (!loaded) return null;
    }

    final summary = bridge.getIndexSummaryJson(engine);
    if (summary == null || summary.containsKey('error')) return null;
    return ScanSnapshotState.fromIndexSummary(summary);
  }

  Future<int?> _fileSizeOrNull(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _waitForIndexLoadDrain(int generation) async {
    final engine = _engine;
    if (engine == null) return false;
    final bridge = VolwardNativeBridge.instance;
    if (!bridge.hasAsyncIndexLoadApi) return true;
    final startedAt = DateTime.now();
    while (generation == _cacheRestoreGeneration &&
        bridge.isIndexLoading(engine)) {
      if (DateTime.now().difference(startedAt) > _cacheRestoreTimeout) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return generation == _cacheRestoreGeneration;
  }

  void _invalidateCacheRestore() {
    _cacheRestoreGeneration++;
    final engine = _engine;
    if (engine != null) {
      VolwardNativeBridge.instance.invalidateIndexLoad(engine);
    }
  }

  Future<void> loadSessionStateIfNeeded() {
    if (_sessionStateLoaded) return Future<void>.value();
    final inFlight = _sessionStateLoadFuture;
    if (inFlight != null) return inFlight;

    final future = _loadSessionState().whenComplete(() {
      _sessionStateLoaded = true;
      _sessionStateLoadFuture = null;
    });
    _sessionStateLoadFuture = future;
    return future;
  }

  Future<void> _loadSessionState() async {
    final generation = _rootSwitchGeneration;
    if (_scanRoots.isNotEmpty) return;
    final file = sessionStateFileForTest ?? _sessionStateFile();
    if (!await file.exists()) return;
    try {
      final raw =
          await (sessionStateReaderForTest?.call(file) ?? file.readAsString());
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final customRoots = <String>[];
      final rawCustomRoots = map['last_custom_roots'];
      if (rawCustomRoots is List) {
        for (final root in rawCustomRoots) {
          final normalized = ScanTreeBuilder.normalizeRoot(root.toString());
          if (normalized.isNotEmpty && !customRoots.contains(normalized)) {
            customRoots.add(normalized);
          }
        }
      }
      final customRoot = map['last_custom_root']?.toString() ?? '';
      if (customRoot.isNotEmpty) {
        final normalized = ScanTreeBuilder.normalizeRoot(customRoot);
        if (normalized.isNotEmpty && !customRoots.contains(normalized)) {
          customRoots.add(normalized);
        }
      }
      if (customRoots.isNotEmpty) {
        _recentCustomRoots = customRoots.take(_maxRecentCustomRoots).toList();
        _lastCustomRoot = _recentCustomRoots.first;
      }
      final roots = map['scan_roots'];
      if (roots is! List) return;
      final loadedRoots = roots
          .map((root) => root.toString())
          .where((root) => root.isNotEmpty)
          .map(ScanTreeBuilder.normalizeRoot)
          .toList(growable: false);
      if (loadedRoots.isEmpty) return;
      if (generation != _rootSwitchGeneration || _scanRoots.isNotEmpty) {
        return;
      }
      if (listEquals(_scanRoots, loadedRoots)) return;
      _scanRoots = loadedRoots;
      _notifyListeners();
    } catch (_) {
      // Session state is only a local cache hint. If it is empty, truncated,
      // or otherwise malformed, treat it as missing and continue booting.
    }
  }

  Future<void> _persistSessionState() async {
    try {
      final file =
          sessionStateFileForTest ??
          (_persistSessionStateEnabled ? _sessionStateFile() : null);
      if (file == null) return;
      await file.parent.create(recursive: true);
      final tmpFile = File('${file.path}.tmp');
      await tmpFile.writeAsString(
        jsonEncode(<String, dynamic>{
          'scan_roots': _scanRoots,
          if (recentCustomRoots.isNotEmpty) ...{
            'last_custom_root': recentCustomRoots.first,
            'last_custom_roots': recentCustomRoots,
          },
        }),
      );
      await tmpFile.rename(file.path);
    } catch (e, st) {
      debugPrint('VolwardSession: persist session state failed: $e\n$st');
    }
  }

  static File _sessionStateFile() =>
      File('${SnapshotCache.cacheDir().path}/session.json');

  /// Path the UI is currently browsing — used as the refresh target.
  /// Set by [setCurrentDirectory] from [HomePage] column selection.
  String? get currentDirectoryPath => _currentDirectoryPath;

  /// The path that [refreshCurrentDirectory] will target (Design §6.1):
  /// focused subdirectory → scan root → default home.
  String get refreshTargetPath =>
      _currentDirectoryPath ??
      (_scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot());

  /// Whether the refresh action can run for the directory currently shown.
  ///
  /// A root refresh starts the file-backed full scan and therefore needs the
  /// snapshot-file API. A child refresh is a scoped peek and does not need
  /// that API, so it remains available with an older compatible dylib.
  bool get canRefreshCurrentDirectory {
    if (!_ready || _engine == null) return false;
    final root = ScanTreeBuilder.normalizeRoot(
      _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot(),
    );
    final target = ScanTreeBuilder.normalizeRoot(refreshTargetPath);
    return !isDirectoryRefreshing(target) &&
        (target != root || hasSnapshotFileApi);
  }

  /// Called by [HomePage] whenever the column selection changes.
  void setCurrentDirectory(String? path) {
    if (_currentDirectoryPath == path) return;
    _currentDirectoryPath = path;
    // No notifyListeners() — this is UI-state bookkeeping, not display data.
  }

  @visibleForTesting
  void setCurrentPathForTest(String path) => _currentDirectoryPath = path;

  void setScanRoots(List<String> roots) {
    // Normalize at this public entry point too — loadSessionStateIfNeeded and
    // resolveStartupRoot both normalize, and refreshTargetPath comparisons in
    // HomePage rely on all three agreeing on the canonical (no trailing slash)
    // form.
    _scanRoots = roots
        .map(ScanTreeBuilder.normalizeRoot)
        .toList(growable: false);
    _currentDirectoryPath = null;
    unawaited(_persistSessionState());
    _notifyListeners();
  }

  void setLastCustomRoot(String? path) {
    rememberCustomRoot(path);
  }

  static const int _maxRecentCustomRoots = 5;

  void rememberCustomRoot(String? path) {
    final normalized = path == null || path.isEmpty
        ? null
        : ScanTreeBuilder.normalizeRoot(path);
    if (normalized == null) {
      if (_lastCustomRoot == null && _recentCustomRoots.isEmpty) return;
      _lastCustomRoot = null;
      _recentCustomRoots = [];
      unawaited(_persistSessionState());
      return;
    }
    if (_recentCustomRoots.isNotEmpty &&
        _recentCustomRoots.first == normalized) {
      return;
    }
    final next = <String>[
      normalized,
      for (final root in _recentCustomRoots)
        if (root != normalized) root,
    ];
    _recentCustomRoots = next.take(_maxRecentCustomRoots).toList();
    _lastCustomRoot = normalized;
    unawaited(_persistSessionState());
  }

  void clearScanRoots() {
    _scanRoots = [];
    _currentDirectoryPath = null;
    unawaited(_persistSessionState());
    notifyListeners();
  }

  /// Switch the active scan root, implementing Plan B:
  ///
  /// * When the selected root changes, the current scan is cancelled if
  ///   necessary, the new root is previewed immediately, and a fresh scan is
  ///   started automatically so the persisted cache follows the new folder.
  ///
  /// * Re-selecting the same root while a scan is already running keeps that
  ///   scan alive and only refreshes the visible preview.
  ///
  /// Callers can set [startFullScan] to false to prepare and preview the root
  /// without automatically starting a fresh full scan.
  Future<void> switchScanRoot(
    String? path, {
    bool startFullScan = true,
    bool validateBeforeSwitch = false,
  }) async {
    final requestGeneration = ++_rootSwitchRequestGeneration;
    final newRoots = path != null ? [path] : <String>[];
    final newRoot = ScanTreeBuilder.normalizeRoot(path ?? _defaultScanRoot());
    List<Map<String, dynamic>>? preparedPreview;
    if (validateBeforeSwitch && path != null) {
      try {
        await validateScanRoot(newRoot);
        preparedPreview = await _readTargetPreview(
          newRoot,
          throwOnFailure: true,
        );
      } catch (_) {
        if (requestGeneration != _rootSwitchRequestGeneration) return;
        rethrow;
      }
      if (requestGeneration != _rootSwitchRequestGeneration) return;
    }

    final generation = ++_rootSwitchGeneration;
    final currentRoot = ScanTreeBuilder.normalizeRoot(
      _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot(),
    );
    final keepRunningScan = _scanning && newRoot == currentRoot;
    final _RootSwitchContinuation continuation;
    if (!startFullScan) {
      continuation = _RootSwitchContinuation.previewOnly;
    } else if (keepRunningScan) {
      continuation = _RootSwitchContinuation.forcePeek;
    } else {
      continuation = _RootSwitchContinuation.fullScan;
    }

    // User-selected scan root (folder picker / root switch). Skip null clears and
    // launch-time [setScanRoots] so startup restore is not counted.
    if (path != null) {
      unawaited(
        Analytics.instance.track(AnalyticsEvents.scanRootSelected, {
          'changed': newRoot == currentRoot ? 0 : 1,
        }),
      );
    }

    if (_scanning && !keepRunningScan) {
      cancelScan();
    }
    _invalidateCacheRestore();

    _scanRoots = newRoots;
    _currentDirectoryPath = null;
    _lastSnapshot = null;
    _lastDeleteReport = null;
    _directoryOverlays.clear();
    _refreshingDirectoryPaths.clear();
    _postDeleteRefreshPaths.clear();
    _refreshErrors.clear();
    _targetPreviewLoading = true;
    _targetPreviewStartedAt = DateTime.now();
    _snapshotVersion++;
    _invalidatedPrefixes.clear();
    _peekInFlight.clear();
    _peekCompleted.clear();
    _cancelPendingForcedPeeks();
    await _persistSessionState();
    _notifyListeners();

    unawaited(
      _previewThenContinueRootSwitch(
        generation,
        newRoot: newRoot,
        continuation: continuation,
        preparedPreview: preparedPreview,
      ),
    );
  }

  Future<void> _previewThenContinueRootSwitch(
    int generation, {
    required String newRoot,
    required _RootSwitchContinuation continuation,
    List<Map<String, dynamic>>? preparedPreview,
  }) async {
    final restored = await _restoreCachedSnapshot();
    if (generation != _rootSwitchGeneration) return;
    if (restored) {
      _targetPreviewLoading = false;
      _targetPreviewStartedAt = null;
      _notifyListeners();
    } else if (preparedPreview == null) {
      await previewTarget(expectedGeneration: generation);
    } else {
      await _applyTargetPreview(
        newRoot,
        preparedPreview,
        expectedGeneration: generation,
      );
    }
    if (generation != _rootSwitchGeneration) return;
    switch (continuation) {
      case _RootSwitchContinuation.previewOnly:
        return;
      case _RootSwitchContinuation.forcePeek:
        unawaited(peekScan(newRoot, force: true));
        return;
      case _RootSwitchContinuation.fullScan:
        await _waitForScanIdle(generation);
        if (generation != _rootSwitchGeneration) return;
        // Fire-and-forget — errors surface via _lastError / notifyListeners.
        unawaited(_runScanAutostart(generation));
    }
  }

  Future<void> _waitForScanIdle(int generation) async {
    while (_scanning && generation == _rootSwitchGeneration) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Internal helper: start a scan and store the completion status without
  /// surfacing a Future to the caller (used by [switchScanRoot]).
  Future<void> _runScanAutostart([int? generation]) async {
    if (generation != null && generation != _rootSwitchGeneration) return;
    try {
      await runScan();
    } on ScanCancelledException {
      // Cancelled by the user or by a subsequent switchScanRoot — ignore.
    } catch (e, st) {
      debugPrint('VolwardSession: auto-started scan failed: $e\n$st');
    }
  }

  /// Instantly renders the chosen target's top-level directory listing,
  /// before any deep scan starts. No-op if the native dylib doesn't support
  /// quick_list_dir yet (old build) — callers fall back to the pre-scan
  /// section in that case.
  Future<void> previewTarget({int? expectedGeneration}) async {
    final root = ScanTreeBuilder.normalizeRoot(
      _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot(),
    );
    final entries = await _readTargetPreview(root);
    if (entries == null) {
      _clearTargetPreviewLoading(expectedGeneration);
      return;
    }

    await _applyTargetPreview(
      root,
      entries,
      expectedGeneration: expectedGeneration,
    );
  }

  Future<List<Map<String, dynamic>>?> _readTargetPreview(
    String root, {
    bool throwOnFailure = false,
  }) async {
    try {
      final testReader = scanRootPreviewReaderForTest;
      if (testReader != null) return await testReader(root);
      if (!_ready || _engine == null) return null;
      if (!VolwardNativeBridge.instance.hasQuickListApi) return null;
      return await Isolate.run(() {
        final bridge = VolwardNativeBridge.open();
        final engine = bridge.createEngine();
        try {
          return bridge.quickListDir(engine, root);
        } finally {
          bridge.freeEngine(engine);
        }
      });
    } catch (e, st) {
      debugPrint('VolwardSession: previewTarget failed: $e\n$st');
      if (throwOnFailure) rethrow;
      return null;
    }
  }

  Future<void> _applyTargetPreview(
    String root,
    List<Map<String, dynamic>> entries, {
    int? expectedGeneration,
  }) async {
    if (expectedGeneration != null &&
        expectedGeneration != _rootSwitchGeneration) {
      return;
    }
    final activeRoot = ScanTreeBuilder.normalizeRoot(
      _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot(),
    );
    if (activeRoot != root) return;

    await _holdTargetPreviewLoading(expectedGeneration);
    if (expectedGeneration != null &&
        expectedGeneration != _rootSwitchGeneration) {
      return;
    }

    final previewEntries = entries.length > _maxPreviewEntries
        ? entries.take(_maxPreviewEntries).toList(growable: false)
        : entries;
    _lastSnapshot = ScanSnapshotState.fromWire(
      buildPreviewSnapshot(rootPath: root, quickListEntries: previewEntries),
    );
    _targetPreviewLoading = false;
    _targetPreviewStartedAt = null;
    notifyListeners();
  }

  Future<void> _holdTargetPreviewLoading(int? expectedGeneration) async {
    final started = _targetPreviewStartedAt;
    if (started == null) return;
    final elapsed = DateTime.now().difference(started);
    final remaining = _minTargetPreviewLoading - elapsed;
    if (remaining <= Duration.zero) return;
    await Future<void>.delayed(remaining);
    if (expectedGeneration != null &&
        expectedGeneration != _rootSwitchGeneration) {
      return;
    }
  }

  void _clearTargetPreviewLoading(int? expectedGeneration) {
    if (expectedGeneration != null &&
        expectedGeneration != _rootSwitchGeneration) {
      return;
    }
    if (!_targetPreviewLoading) return;
    _targetPreviewLoading = false;
    _targetPreviewStartedAt = null;
    notifyListeners();
  }

  /// Query direct children of [path] from the Rust catalog index.
  ///
  /// Returns null if the index API is unavailable so callers can fall back to
  /// the tree-based path.  Called by [HomePage._visibleChildrenFor] on every
  /// cache miss so results are always fresh after [refreshCurrentDirectory].
  List<SnapshotNodeRecord>? queryDirectoryChildrenFromCatalog(
    String path, {
    String? categoryFilter,
    bool deletableOnly = false,
    String sortMode = 'size_desc',
  }) {
    if (!hasIndexApi || _engine == null) return null;
    try {
      final result = VolwardNativeBridge.instance.queryDirectoryJson(
        _engine!,
        normalizeFsPath(path),
        categoryFilter: categoryFilter,
        deletableOnly: deletableOnly,
        sortMode: sortMode,
      );
      final nodes = result['direct_children'] as List?;
      if (nodes == null) return null;
      return nodes
          .whereType<Map<String, dynamic>>()
          .map(SnapshotNodeRecord.fromJson)
          .toList(growable: false);
    } catch (e) {
      debugPrint('VolwardSession.queryDirectoryChildrenFromCatalog: $e');
      return null;
    }
  }

  /// Refreshes the currently focused directory.
  ///
  /// Subdirectories use a scoped re-scan so local filesystem changes are
  /// reflected without re-scanning the whole root. The root target falls back
  /// to the normal full scan worker so large refreshes stay file-backed rather
  /// than shipping a giant snapshot through the UI isolate.
  Future<void> refreshCurrentDirectory([String? path]) async {
    if (!_ready || _engine == null) return;
    final targetPath = path ?? refreshTargetPath;
    final root = ScanTreeBuilder.normalizeRoot(
      _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot(),
    );
    final target = ScanTreeBuilder.normalizeRoot(targetPath);
    if (_refreshingDirectoryPaths.contains(target)) return;
    unawaited(Analytics.instance.track(AnalyticsEvents.refreshTriggered));
    if (target == root) {
      _currentDirectoryPath = null;
    } else {
      _currentDirectoryPath = target;
    }
    _refreshingDirectoryPaths.add(target);
    _refreshErrors.remove(target);
    _invalidatedPrefixes.add(target);
    _snapshotVersion++;
    _notifyListeners();
    final scopedRefresh = target != root;
    if (scopedRefresh) _beginNotificationBatch();
    try {
      if (target == root) {
        final generation = _rootSwitchGeneration;
        while (_scanning && generation == _rootSwitchGeneration) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        if (generation != _rootSwitchGeneration) return;
        await runScan();
      } else {
        final refreshed = await peekScan(target, force: true);
        if (!refreshed) {
          _refreshErrors[target] =
              'The directory could not be refreshed. The previous results are still shown.';
        }
      }
      _invalidateCapabilityCacheFor(_lastSnapshot?.snapshotId);
    } catch (e, st) {
      _refreshErrors[target] = e.toString();
      _lastError = '$e';
      debugPrint('VolwardSession: refreshCurrentDirectory failed: $e\n$st');
    } finally {
      _refreshingDirectoryPaths.remove(target);
      if (scopedRefresh) {
        _endNotificationBatch(notify: true);
      } else {
        _notifyListeners();
      }
    }
  }

  /// Triggers a small, scoped scan of [path] so its contents/size become
  /// available immediately, without waiting for the background full scan
  /// to reach it. Explicit refreshes wait for an existing peek of the same
  /// path and then run once more, so a click cannot be silently lost.
  Future<bool> peekScan(String path, {bool force = false}) async {
    if (!_ready || _engine == null) return false;
    final normalizedPath = ScanTreeBuilder.normalizeRoot(path);
    final generation = _rootSwitchGeneration;
    if (_peekInFlight.contains(normalizedPath)) {
      if (!force) return false;
      final pending = _pendingForcedPeeks[normalizedPath] ??= Completer<void>();
      await pending.future;
      if (generation != _rootSwitchGeneration) return false;
      return peekScan(normalizedPath, force: true);
    }
    if (!force && _peekCompleted.contains(normalizedPath)) return false;
    if (_peekInFlight.length >= _maxConcurrentPeeks) {
      if (!force) return false;
      while (_peekInFlight.length >= _maxConcurrentPeeks &&
          generation == _rootSwitchGeneration) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
    if (generation != _rootSwitchGeneration) return false;

    final operationToken = ++_nextPeekOperationToken;
    _peekOperationTokens[normalizedPath] = operationToken;
    _peekInFlight.add(normalizedPath);
    _notifyListeners();
    ReceivePort? receivePort;
    ReceivePort? cancelInitPort;
    var applied = false;
    try {
      receivePort = ReceivePort();
      cancelInitPort = ReceivePort();
      final resultFuture = receivePort.first;
      final cancelPortFuture = cancelInitPort.first;
      await Isolate.spawn(volwardPeekScanIsolate, [
        receivePort.sendPort,
        normalizedPath,
        cancelInitPort.sendPort,
      ]);
      final readyOrResult = await Future.any<dynamic>([
        cancelPortFuture,
        resultFuture.then<dynamic>((_) => null),
      ]);
      final cancelPort = readyOrResult is SendPort ? readyOrResult : null;
      final message = await waitForPeekWorkerResult<dynamic>(
        resultFuture,
        timeout: _peekScanTimeout,
        cancel: () {
          debugPrint(
            'VolwardSession: peekScan($normalizedPath) timed out after '
            '${_peekScanTimeout.inSeconds}s; cancelling worker',
          );
          cancelPort?.send(null);
        },
      );
      // The timeout path stays in-flight until the native scan acknowledges
      // cancellation and the worker releases its engine. Clearing it earlier
      // would allow a second subtree scan to overlap.
      if (message is! Map) return false;
      final type = message['type']?.toString();
      if (type == 'done') {
        if (generation != _rootSwitchGeneration) return false;
        final tree = message['tree'];
        final entriesRaw = message['entries'];
        if (tree is Map) {
          // Do not load a peek-scan index into the main engine: the peek engine
          // only scanned this subtree, so its index would replace the full
          // catalog with a partial one. The merged Dart tree is the authoritative
          // overlay for this focused branch until the next full scan.
          final entries = (entriesRaw is List)
              ? entriesRaw
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList()
              : <Map<String, dynamic>>[];
          applied = await _applyMerge(
            normalizedPath,
            Map<String, dynamic>.from(tree),
            entries,
            authoritative: true,
          );
          _peekCompleted.add(normalizedPath);
        }
      } else {
        debugPrint(
          'VolwardSession: peekScan($normalizedPath) failed: ${message['error']}',
        );
      }
    } catch (e, st) {
      debugPrint('VolwardSession: peekScan($normalizedPath) error: $e\n$st');
    } finally {
      receivePort?.close();
      cancelInitPort?.close();
      if (_peekOperationTokens[normalizedPath] == operationToken) {
        _peekOperationTokens.remove(normalizedPath);
        _peekInFlight.remove(normalizedPath);
        final pending = _pendingForcedPeeks.remove(normalizedPath);
        if (pending != null && !pending.isCompleted) pending.complete();
        _notifyListeners();
      }
    }
    return applied;
  }

  void setIncrementalScan(bool incremental) {
    if (incremental && !canUseIncrementalScan) return;
    if (_incrementalScan == incremental) return;
    _incrementalScan = incremental;
    _notifyListeners();
  }

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
      _capabilities = VolwardNativeBridge.instance.probeCapabilities(_engine!);
      _deepScanReady = VolwardNativeBridge.instance.isDeepScanReady(_engine!);
    } catch (e) {
      _lastError = '$e';
    }
    notifyListeners();
  }

  Future<bool> openPermissionSettings() async {
    if (!_ready || _engine == null) return false;
    _lastError = null;
    try {
      return VolwardNativeBridge.instance.openPermissionSettings(_engine!);
    } catch (e) {
      _lastError = '$e';
      return false;
    }
  }

  Future<String> runScan() async {
    if (!_ready) {
      throw StateError(_initError ?? 'Native engine not ready');
    }
    if (_scanning) {
      throw StateError('A scan is already in progress');
    }
    final testRunner = scanRunnerForTest;
    if (testRunner == null && !hasSnapshotFileApi) {
      throw StateError(
        'Native library is outdated. Rebuild the Rust library for this platform, '
        'then fully restart the app.',
      );
    }
    if (testRunner == null && _incrementalScan && !canUseIncrementalScan) {
      throw StateError(
        'Incremental scan requires an updated native library. Rebuild the Rust library '
        'for this platform, then fully restart the app.',
      );
    }

    final effectiveRoots = _scanRoots.isNotEmpty
        ? _scanRoots
        : [_defaultScanRoot()];

    _invalidateCacheRestore();
    _scanning = true;
    final scanStartedAt = DateTime.now();
    final incrementalProp = _incrementalScan ? 1 : 0;
    unawaited(
      Analytics.instance.track(AnalyticsEvents.scanStarted, {
        'incremental': incrementalProp,
      }),
    );
    var scanSucceeded = false;
    try {
      final scanGeneration = _rootSwitchGeneration;
      _targetPreviewLoading = false;
      _targetPreviewStartedAt = null;
      _lastError = null;
      _lastDeleteReport = null;
      _scanProgress = null;
      _workerCancelPort = null;
      _scanChannelsClosed = false;
      _scanRunningOnMainEngine = false;
      _scanCancelRequested = false;
      _lastScanActivityAt = null;
      _savingPhaseStartedAt = null;
      _lastNativeProgressNotifyAt = null;
      _lastNativeProgressPhase = null;
      _peekInFlight.clear();
      _peekCompleted.clear();
      _directoryOverlays.clear();
      _cancelPendingForcedPeeks();
      _startScanElapsedTimer();
      _setScanProgressPhase('DiscoveringRoots', pathsSeen: 0);
      await _waitForIndexLoadDrain(_cacheRestoreGeneration);
      if (scanGeneration != _rootSwitchGeneration) {
        _scanning = false;
        _finalizeScanTransientState();
        _notifyListeners();
        throw ScanCancelledException();
      }

      if (testRunner != null) {
        final jobId = 'job-${DateTime.now().millisecondsSinceEpoch}';
        _lastJobId = jobId;
        try {
          final snapshot = await _awaitScanWithStallGuard(
            testRunner(jobId, effectiveRoots),
          );
          if (scanGeneration == _rootSwitchGeneration) {
            _lastSnapshot = snapshot;
            _invalidateCapabilityCacheFor(snapshot?.snapshotId);
            _logSnapshotMemoryState('scan-complete');
            _notifyListeners();
          }
          scanSucceeded = true;
          return _lastSnapshot?.snapshotId ?? snapshot?.snapshotId ?? 'done';
        } finally {
          _scanning = false;
          _finalizeScanTransientState();
          _notifyListeners();
        }
      }

      if (hasIndexApi) {
        final jobId = 'job-${DateTime.now().millisecondsSinceEpoch}';
        _lastJobId = jobId;
        try {
          final snapshot = await _awaitScanWithStallGuard(
            _runIndexScanOnMainEngine(jobId, effectiveRoots),
          );
          if (scanGeneration == _rootSwitchGeneration) {
            _lastSnapshot = snapshot;
            _invalidateCapabilityCacheFor(snapshot?.snapshotId);
            _logSnapshotMemoryState('scan-complete');
            _notifyListeners();
          }
          scanSucceeded = true;
          return _lastSnapshot?.snapshotId ?? snapshot?.snapshotId ?? 'done';
        } on ScanCancelledException catch (e) {
          _lastError = e.message;
          rethrow;
        } catch (e, st) {
          _lastError = '$e';
          debugPrint('VolwardSession index scan failed: $e\n$st');
          rethrow;
        } finally {
          _scanRunningOnMainEngine = false;
          _scanning = false;
          _finalizeScanTransientState();
          _notifyListeners();
        }
      }

      _scanReceivePort = ReceivePort();
      _scanCancelInitPort = ReceivePort();
      final completer = Completer<ScanSnapshotState?>();
      _activeScanCompleter = completer;

      _scanProgressSub = _scanReceivePort!.listen((msg) {
        if (_scanChannelsClosed || completer.isCompleted) return;
        if (msg is! Map) return;
        final m = Map<String, dynamic>.from(msg);
        final type = m['type']?.toString();
        if (type == 'progress') {
          final phase = m['phase']?.toString();
          _touchScanActivity(phase: phase);
          _scanProgress = Map<String, dynamic>.from(m)..remove('type');
          _publishScanProgress();
          _notifyListeners();
        } else if (type == 'checkpoint') {
          final path = m['snapshot_path']?.toString();
          if (!hasIndexApi && path != null && path.isNotEmpty) {
            unawaited(_applyCheckpointFromFile(path, scanGeneration));
          }
          // Load catalog index from checkpoint if available (Design §7.2).
          final indexPath = m['index_path']?.toString();
          if (indexPath != null && indexPath.isNotEmpty && _engine != null) {
            VolwardNativeBridge.instance.loadIndexFromPath(_engine!, indexPath);
          }
        } else if (type == 'done') {
          _touchScanActivity(phase: 'LoadingResults');
          _closeScanChannels();
          final indexPath = m['index_path']?.toString();
          var loadedIndex = true;
          if (indexPath != null && indexPath.isNotEmpty && _engine != null) {
            loadedIndex = VolwardNativeBridge.instance.loadIndexFromPath(
              _engine!,
              indexPath,
            );
          }
          final summary = !loadedIndex || _engine == null
              ? null
              : VolwardNativeBridge.instance.getIndexSummaryJson(_engine!);
          final path = m['snapshot_path']?.toString();
          if (summary != null && !summary.containsKey('error')) {
            if (path != null && path.isNotEmpty) {
              _deleteTempResultFile(path);
            }
            if (indexPath != null && indexPath.isNotEmpty) {
              _deleteTempResultFile(indexPath);
            }
            completer.complete(ScanSnapshotState.fromIndexSummary(summary));
          } else if (path != null && path.isNotEmpty) {
            if (indexPath != null && indexPath.isNotEmpty) {
              _deleteTempResultFile(indexPath);
            }
            _loadSnapshotFromFile(path)
                .then((snap) {
                  if (!completer.isCompleted) {
                    completer.complete(snap);
                  }
                })
                .catchError((Object e, StackTrace st) {
                  if (!completer.isCompleted) {
                    completer.completeError(e, st);
                  }
                });
          } else if (indexPath != null && indexPath.isNotEmpty) {
            _deleteTempResultFile(indexPath);
            completer.completeError('Failed to load catalog index');
          } else {
            final snap = m['snapshot'];
            completer.complete(
              snap is Map
                  ? ScanSnapshotState.fromWire(Map<String, dynamic>.from(snap))
                  : null,
            );
          }
        } else if (type == 'error') {
          _closeScanChannels();
          if (!completer.isCompleted) {
            completer.completeError(m['error']?.toString() ?? 'Scan failed');
          }
        }
      });

      _scanCancelInitPort!.listen((msg) {
        if (msg is SendPort) {
          _workerCancelPort = msg;
        }
      });

      try {
        final jobId = 'job-${DateTime.now().millisecondsSinceEpoch}';
        _lastJobId = jobId;
        await Isolate.spawn(volwardScanIsolate, [
          _scanReceivePort!.sendPort,
          effectiveRoots,
          _scanCancelInitPort!.sendPort,
          _incrementalScan,
        ]);
        final snapshot = await _awaitScanWithStallGuard(completer.future);
        if (scanGeneration == _rootSwitchGeneration) {
          _lastSnapshot = snapshot;
          _invalidateCapabilityCacheFor(snapshot?.snapshotId);
          _logSnapshotMemoryState('scan-complete');
          _notifyListeners();
        }
        scanSucceeded = true;
        return _lastSnapshot?.snapshotId ?? snapshot?.snapshotId ?? 'done';
      } on ScanCancelledException catch (e) {
        _lastError = e.message;
        rethrow;
      } catch (e, st) {
        if (!_scanChannelsClosed) {
          _closeScanChannels();
        }
        _lastError = '$e';
        debugPrint('VolwardSession scan failed: $e\n$st');
        rethrow;
      } finally {
        _scanning = false;
        _finalizeScanTransientState();
        _notifyListeners();
      }
    } finally {
      unawaited(
        Analytics.instance.track(AnalyticsEvents.scanCompleted, {
          'success': scanSucceeded ? 1 : 0,
          'duration_ms': DateTime.now()
              .difference(scanStartedAt)
              .inMilliseconds,
          'incremental': incrementalProp,
        }),
      );
    }
  }

  bool get hasAiSessionApi =>
      _ready && _engine != null && VolwardNativeBridge.instance.hasAiSessionApi;

  bool get hasAiContractApi =>
      _ready && VolwardNativeBridge.instance.hasAiContractApi;

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
    final bridge = VolwardNativeBridge.instance;
    if (!bridge.hasAsyncAiCandidatesApi) {
      return bridge.buildAiCandidatesJson(engine, snapshotId);
    }

    final startedAt = DateTime.now();
    const timeout = Duration(minutes: 3);
    while (true) {
      if (DateTime.now().difference(startedAt) > timeout) {
        return 'error:ai candidates build timed out';
      }
      final started = bridge.startBuildAiCandidatesAsync(engine, snapshotId);
      if (started == null) {
        return bridge.buildAiCandidatesJson(engine, snapshotId);
      }
      if (started.startsWith('error:')) return started;
      if (started.startsWith('busy:')) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }
      break;
    }

    while (bridge.isAiCandidatesBuilding(engine)) {
      if (DateTime.now().difference(startedAt) > timeout) {
        return 'error:ai candidates build timed out';
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return bridge.getAiCandidatesJson(engine);
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

  Future<Map<String, dynamic>> deleteEntries(
    List<String> targets, {
    String? expectedSnapshotId,
    bool dryRun = false,
    bool rescanAfterDelete = false,
    String? refreshPath,
    Map<String, String>? targetPathById,
  }) async {
    final testDeleteRunner = deleteRunnerForTest;
    if (!_ready || (_engine == null && testDeleteRunner == null)) {
      throw StateError(_initError ?? 'Native engine not ready');
    }
    final snapshotId = _lastSnapshot?.snapshotId;
    if (snapshotId == null || snapshotId.isEmpty) {
      throw StateError('No scan snapshot — run a scan first');
    }
    if (expectedSnapshotId != null && expectedSnapshotId != snapshotId) {
      throw StateError('Snapshot changed — refresh the analysis and try again');
    }

    _deleting = true;
    _lastError = null;
    _notifyListeners();
    final batchRefresh = !dryRun && rescanAfterDelete;
    // The directory whose listing changes after the delete.
    final deleteTargetDir = batchRefresh
        ? (refreshPath ?? refreshTargetPath)
        : null;
    late Map<String, dynamic> completedReport;
    String? pendingRefreshPath;
    var moveToTrashSucceeded = false;
    var moveToTrashItemCount = targets.length;
    try {
      final report =
          testDeleteRunner?.call(snapshotId, targets, dryRun) ??
          VolwardNativeBridge.instance.deleteEntries(
            _engine!,
            snapshotId,
            targets,
            dryRun: dryRun,
          );
      if (report.containsKey('error')) {
        throw StateError(report['error'].toString());
      }
      completedReport = report;
      if (!dryRun) {
        _lastDeleteReport = report;
        moveToTrashSucceeded = true;
        moveToTrashItemCount =
            (report['deleted_count'] as num?)?.toInt() ?? targets.length;
      }
      if (!dryRun && rescanAfterDelete && deleteTargetDir != null) {
        // The OS move has completed, so commit that result immediately instead
        // of keeping the delete action in Working while a potentially large
        // parent directory is scanned. The background refresh remains the
        // authoritative disk reconciliation and atomically replaces this
        // temporary overlay when it completes.
        _applySuccessfulDeleteOverlay(
          deleteTargetDir,
          targets,
          report,
          targetPathById: targetPathById,
          notify: false,
        );
        pendingRefreshPath = deleteTargetDir;
      }
    } catch (e, st) {
      _lastError = '$e';
      debugPrint('VolwardSession delete failed: $e\n$st');
      rethrow;
    } finally {
      _deleting = false;
      _notifyListeners();
      if (!dryRun) {
        unawaited(
          Analytics.instance.track(AnalyticsEvents.moveToTrash, {
            'item_count': moveToTrashItemCount,
            'success': moveToTrashSucceeded ? 1 : 0,
          }),
        );
      }
    }
    if (pendingRefreshPath != null) {
      _scheduleDirectoryRefreshAfterDelete(pendingRefreshPath);
    }
    return completedReport;
  }

  void _scheduleDirectoryRefreshAfterDelete(String path) {
    final normalizedPath = ScanTreeBuilder.normalizeRoot(path);
    _postDeleteRefreshPaths.add(normalizedPath);
    _notifyListeners();
    unawaited(
      Future<void>.delayed(Duration.zero, () async {
        try {
          final testRunner = directoryRefreshRunnerForTest;
          if (testRunner != null) {
            await testRunner(path);
          } else {
            await refreshCurrentDirectory(path);
          }
        } catch (e, st) {
          _refreshErrors[ScanTreeBuilder.normalizeRoot(path)] = e.toString();
          debugPrint(
            'VolwardSession: post-delete directory refresh failed: $e\n$st',
          );
          _notifyListeners();
        } finally {
          _postDeleteRefreshPaths.remove(normalizedPath);
          _notifyListeners();
        }
      }),
    );
  }

  void _applySuccessfulDeleteOverlay(
    String directoryPath,
    List<String> targets,
    Map<String, dynamic> report, {
    Map<String, String>? targetPathById,
    bool notify = true,
  }) {
    final normalizedPath = ScanTreeBuilder.normalizeRoot(directoryPath);
    final existing = _directoryOverlays[normalizedPath];
    final snapshotNode = existing == null
        ? _findSnapshotDirectory(_lastSnapshot?.tree, normalizedPath)
        : null;
    final records = existing != null
        ? existing.children
              .map(SnapshotNodeRecord.fromTree)
              .toList(growable: false)
        : (queryDirectoryChildrenFromCatalog(normalizedPath) ??
              snapshotNode?.children
                  .map(SnapshotNodeRecord.fromTree)
                  .toList(growable: false));
    if (records == null) {
      // No in-memory listing for this directory (peek did not cover it and the
      // catalog has no entry). Skipping silently leaves the UI showing a stale
      // list with no way to know the refresh was dropped — surface it instead.
      debugPrint(
        'VolwardSession: delete overlay skipped for $normalizedPath — '
        'no records available (list may be stale; manual refresh required)',
      );
      _refreshErrors[normalizedPath] =
          'The directory could not be refreshed after delete. '
          'The previous results are still shown.';
      return;
    }
    final deletedCount = (report['deleted_count'] as num?)?.toInt() ?? 0;
    if (deletedCount <= 0) {
      debugPrint(
        'VolwardSession: delete overlay skipped for $normalizedPath — '
        'report deleted_count=$deletedCount',
      );
      return;
    }

    final targetIds = targets.toSet();
    final targetPaths = <String>{
      for (final target in targets)
        ScanTreeBuilder.normalizeRoot(targetPathById?[target] ?? target),
    };
    final failedPaths =
        (report['failed_paths'] as List?)
            ?.whereType<Object>()
            .map((path) => ScanTreeBuilder.normalizeRoot(path.toString()))
            .toSet() ??
        <String>{};
    final remaining = <ScanTreeNode>[];
    final removedPaths = <String>{};
    for (final node in records) {
      final matchesTarget =
          (node.entryId != null && targetIds.contains(node.entryId)) ||
          targetPaths.contains(ScanTreeBuilder.normalizeRoot(node.path));
      if (!matchesTarget) {
        remaining.add(node.toScanTreeNode());
        continue;
      }
      final nodePath = ScanTreeBuilder.normalizeRoot(node.path);
      if (failedPaths.contains(nodePath)) {
        remaining.add(node.toScanTreeNode());
      } else {
        removedPaths.add(nodePath);
      }
    }

    final base = existing ?? snapshotNode ?? ScanTreeNode.empty(normalizedPath);
    _directoryOverlays.removeWhere((path, _) {
      for (final removedPath in removedPaths) {
        if (path == removedPath || path.startsWith('$removedPath/')) {
          return true;
        }
      }
      return false;
    });
    _directoryOverlays[normalizedPath] = ScanTreeNode(
      name: base.name,
      path: normalizedPath,
      isDirectory: true,
      sizeBytes: base.sizeBytes,
      scanned: true,
      peekScanned: true,
      children: remaining,
    );
    _snapshotVersion++;
    _invalidatedPrefixes.add(normalizedPath);
    if (notify) _notifyListeners();
  }

  ScanTreeNode? _findSnapshotDirectory(ScanTreeNode? node, String targetPath) {
    if (node == null) return null;
    if (node.path == targetPath && node.isDirectory) return node;
    if (!node.isDirectory) return null;
    for (final child in node.children) {
      final found = _findSnapshotDirectory(child, targetPath);
      if (found != null) return found;
    }
    return null;
  }

  @visibleForTesting
  void applySuccessfulDeleteOverlayForTest(
    String directoryPath,
    List<String> targets,
    Map<String, dynamic> report, {
    Map<String, String>? targetPathById,
  }) {
    _applySuccessfulDeleteOverlay(
      directoryPath,
      targets,
      report,
      targetPathById: targetPathById,
    );
  }

  Future<Map<String, dynamic>> emptyTrash({
    bool rescanAfterEmpty = true,
  }) async {
    if (!_ready || _engine == null) {
      throw StateError(_initError ?? 'Native engine not ready');
    }

    _deleting = true;
    _lastError = null;
    notifyListeners();
    var emptyTrashSucceeded = false;
    try {
      final report = VolwardNativeBridge.instance.emptyTrash(_engine!);
      if (report.containsKey('error')) {
        throw StateError(report['error'].toString());
      }
      emptyTrashSucceeded = true;
      if (rescanAfterEmpty && _lastSnapshot != null) {
        await refreshCurrentDirectory();
      }
      return report;
    } catch (e, st) {
      _lastError = '$e';
      debugPrint('VolwardSession empty trash failed: $e\n$st');
      rethrow;
    } finally {
      _deleting = false;
      _notifyListeners();
      unawaited(
        Analytics.instance.track(AnalyticsEvents.emptyTrash, {
          'success': emptyTrashSucceeded ? 1 : 0,
        }),
      );
    }
  }

  Future<ScanSnapshotState?> _loadSnapshotFromFile(String path) async {
    final pathsSeen = (_scanProgress?['paths_seen'] as num?)?.toInt();
    _setScanProgressPhase('LoadingResults', pathsSeen: pathsSeen);

    if (!_ready || _engine == null) {
      throw StateError('Native engine not ready');
    }

    final snap = await Isolate.run(() => _decodeSnapshotFile(path));
    try {
      await File(path).delete();
    } catch (_) {}

    if (snap == null) {
      throw StateError('Invalid snapshot file');
    }
    if (!VolwardNativeBridge.instance.setLastSnapshot(_engine!, snap)) {
      throw StateError('Failed to load scan snapshot into engine');
    }
    _invalidateCapabilityCacheFor(snap['snapshot_id']?.toString());
    return ScanSnapshotState.fromWire(snap);
  }

  void _invalidateCapabilityCacheFor(String? snapshotId) {
    if (snapshotId != null && snapshotId.isNotEmpty) {
      _capabilityCache.invalidateForSnapshot(snapshotId);
    }
  }

  void _logSnapshotMemoryState(String source) {
    final snapshot = _lastSnapshot;
    if (snapshot == null) return;
    final stats = snapshot.stats;
    final progress = _scanProgress;
    final rootPath = snapshot.tree?.path ?? '';
    int? readInt(dynamic value) =>
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

    final pathsSeen =
        readInt(stats['paths_seen']) ?? readInt(progress?['paths_seen']);
    final dirsSeen =
        readInt(stats['dirs_seen']) ?? readInt(progress?['dirs_seen']);
    final filesSeen =
        readInt(stats['files_seen']) ?? readInt(progress?['files_seen']);
    final filesInSnapshot =
        readInt(stats['files_in_snapshot']) ?? snapshot.entryCount;
    final scanPhase =
        stats['scan_state']?.toString() ??
        progress?['phase']?.toString() ??
        '-';
    final pathsSkipped = readInt(stats['paths_skipped']);
    final truncated = stats['truncated']?.toString();
    final incompleteReason = stats['incomplete_reason']?.toString();
    final treeBytes = snapshot.tree?.displayBytes ?? 0;
    final rssBytes = ProcessInfo.currentRss;
    final rssMb = (rssBytes / (1024 * 1024)).toStringAsFixed(1);
    debugPrint(
      'VolwardSession: $source memory snapshot '
      'root=$rootPath '
      'snapshotId=${snapshot.snapshotId} '
      'rss=${rssMb}MB '
      'scan_phase=$scanPhase '
      'paths_seen=${pathsSeen ?? '-'} '
      'dirs_seen=${dirsSeen ?? '-'} '
      'files_seen=${filesSeen ?? '-'} '
      'files_in_snapshot=$filesInSnapshot '
      'paths_skipped=${pathsSkipped ?? '-'} '
      'truncated=${truncated ?? '-'} '
      'incomplete_reason=${incompleteReason ?? '-'} '
      'entryCount=${snapshot.entryCount} '
      'treeBytes=$treeBytes '
      'reclaimable=${snapshot.reclaimableEstimateBytes}',
    );
  }

  Future<ScanSnapshotState?> _runIndexScanOnMainEngine(
    String jobId,
    List<String> roots,
  ) async {
    if (!_ready || _engine == null) {
      throw StateError('Native engine not ready');
    }
    if (!_scanning || _scanCancelRequested) {
      throw ScanCancelledException();
    }
    final bridge = VolwardNativeBridge.instance;
    final startResult = bridge.startScanAsyncWithOptions(
      _engine!,
      jobId,
      roots,
      incremental: _incrementalScan,
    );
    if (startResult.startsWith('error:')) {
      throw StateError(startResult);
    }

    _scanRunningOnMainEngine = true;
    _touchScanActivity(phase: 'Walking');

    while (bridge.isScanRunning(_engine!)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!_scanning || _scanCancelRequested) {
        bridge.cancelScan(_engine!);
        await _waitForNativeScanToStop(bridge);
        throw ScanCancelledException();
      }
      final progress = bridge.getLastProgress(_engine!);
      if (progress != null) {
        final phase = progress['phase']?.toString();
        _touchScanActivity(phase: phase);
        _scanProgress = progress;
        _publishScanProgress();
        _notifyNativeProgressIfNeeded(phase);
      }
    }
    if (_scanCancelRequested || !_scanning) {
      throw ScanCancelledException();
    }

    final progress = bridge.getLastProgress(_engine!);
    final pathsSeen = (progress?['paths_seen'] as num?)?.toInt();
    _setScanProgressPhase('Done', pathsSeen: pathsSeen);
    _touchScanActivity(phase: 'LoadingResults');

    final summary = bridge.getIndexSummaryJson(_engine!);
    if (summary == null || summary.containsKey('error')) {
      throw StateError(
        summary?['error']?.toString() ?? 'Failed to load catalog index',
      );
    }
    return ScanSnapshotState.fromIndexSummary(summary);
  }

  /// Bound the native shutdown wait so a cancelled `runScan()` cannot hang
  /// forever if `isScanRunning` never clears.
  Future<void> _waitForNativeScanToStop(VolwardNativeBridge bridge) async {
    final engine = _engine;
    if (engine == null) return;
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (bridge.isScanRunning(engine) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  void _notifyNativeProgressIfNeeded(String? phase) {
    final now = DateTime.now();
    final phaseChanged = phase != null && phase != _lastNativeProgressPhase;
    final elapsed = _lastNativeProgressNotifyAt == null
        ? null
        : now.difference(_lastNativeProgressNotifyAt!);
    if (phaseChanged ||
        elapsed == null ||
        elapsed >= const Duration(seconds: 1)) {
      _lastNativeProgressPhase = phase;
      _lastNativeProgressNotifyAt = now;
      _notifyListeners();
    }
  }

  void _deleteTempResultFile(String path) {
    unawaited(() async {
      try {
        await File(path).delete();
      } catch (_) {
        // Best-effort cleanup for worker temp files.
      }
    }());
  }

  Future<void> _applyCheckpointFromFile(
    String path,
    int expectedGeneration,
  ) async {
    try {
      final checkpoint = await Isolate.run(() => _decodeSnapshotFile(path));
      try {
        await File(path).delete();
      } catch (_) {}
      if (checkpoint == null) return;

      final tree = checkpoint['tree'];
      if (tree is! Map) return;
      final rootPath = tree['path']?.toString();
      if (rootPath == null || rootPath.isEmpty) return;

      final entries = (checkpoint['entries'] is List)
          ? (checkpoint['entries'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      if (expectedGeneration != _rootSwitchGeneration) return;
      await _applyMerge(rootPath, Map<String, dynamic>.from(tree), entries);
    } catch (e, st) {
      // Two expected, benign errors are swallowed silently:
      // - PathNotFoundException: the checkpoint file was already consumed
      //   (deleted) by a prior _applyCheckpointFromFile for the same path.
      // - FormatException: defensive — if a half-written file is ever read
      //   (the unique-path rename in scan_worker should prevent this), the
      //   checkpoint is simply dropped; the next one supersedes it.
      if (e is! PathNotFoundException && e is! FormatException) {
        debugPrint('VolwardSession: apply checkpoint failed: $e\n$st');
      }
    }
  }

  Future<bool> _applyMerge(
    String targetPath,
    Map<String, dynamic> subtreeTree,
    List<Map<String, dynamic>> subtreeEntries, {
    bool authoritative = false,
  }) async {
    final current = _lastSnapshot;
    if (current == null) return false;
    if (authoritative) {
      final entriesById = <String, ScanEntryRecord>{
        for (final entry in subtreeEntries)
          if (entry['id'] != null)
            entry['id'].toString(): ScanEntryRecord.fromWire(entry),
      };
      final overlay = ScanTreeNode.fromSnapshotJson(
        Map<String, dynamic>.from(subtreeTree),
        entriesById: entriesById,
      );
      final normalizedPath = ScanTreeBuilder.normalizeRoot(targetPath);
      final prefix = normalizedPath.endsWith('/')
          ? normalizedPath
          : '$normalizedPath/';
      _directoryOverlays.removeWhere(
        (path, _) => path == normalizedPath || path.startsWith(prefix),
      );
      _directoryOverlays[normalizedPath] = overlay;

      // Keep the Rust catalog index in sync with this peek result. The UI
      // reads query_directory from the catalog when the index API is active —
      // without this splice the catalog stays stale and the refreshed
      // directory never appears (the "delete/refresh does not update" bug).
      _spliceSubtreeIntoCatalog(normalizedPath, subtreeTree, subtreeEntries);
    }
    final merged = mergeSubtreeIntoSnapshotState(
      snapshot: current,
      targetPath: targetPath,
      subtreeTree: subtreeTree,
      subtreeEntries: subtreeEntries,
      replacementIsAuthoritative: authoritative,
    );
    // Force every merge to look like "new data" to snapshot_id-keyed UI
    // Keep the Rust snapshot_id stable so delete/refresh calls continue to
    // match the native engine, and rely on [_snapshotVersion] / catalogVersion
    // to invalidate Dart-side caches.
    _lastSnapshot = merged;
    _snapshotVersion++;
    _invalidatedPrefixes.add(targetPath);
    // Throttle UI notifications: checkpoints can arrive 5-10×/sec.  We always
    // update _lastSnapshot above for correctness; we just batch widget rebuilds
    // to at most once per _kDisplayNotifyGap so the main thread isn't saturated
    // with O(N log N) display-tree recomputations.  Authoritative merges (peek
    // results) always notify immediately so the user sees results without delay.
    final now = DateTime.now();
    final shouldNotify =
        authoritative ||
        !_scanning ||
        _lastApplyMergeNotify == null ||
        now.difference(_lastApplyMergeNotify!) >= _kDisplayNotifyGap;
    if (shouldNotify) {
      _lastApplyMergeNotify = now;
      _notifyListeners();
    }
    return true;
  }

  /// Pushes a peek-scan subtree into the Rust catalog index so
  /// `query_directory` (read by the UI when the index API is active) reflects
  /// the refreshed directory. Best-effort: a missing index, an unavailable
  /// FFI symbol (older dylib), or a rejected payload must not fail the merge —
  /// the Dart overlay write above already guarantees correct rendering via the
  /// tree fallback path.
  void _spliceSubtreeIntoCatalog(
    String normalizedPath,
    Map<String, dynamic> subtreeTree,
    List<Map<String, dynamic>> subtreeEntries,
  ) {
    final engine = _engine;
    if (engine == null || !hasIndexApi) return;
    if (!VolwardNativeBridge.instance.hasReplaceSubtreeApi) return;
    try {
      final payload = jsonEncode(<String, dynamic>{
        'tree': subtreeTree,
        'entries': subtreeEntries,
      });
      VolwardNativeBridge.instance.replaceDirectoryWithSubtree(
        engine,
        normalizedPath,
        payload,
      );
    } catch (e, st) {
      debugPrint('VolwardSession: splice subtree into catalog failed: $e\n$st');
    }
  }

  void cancelScan() {
    if (!_scanning) return;

    if (_scanRunningOnMainEngine && _engine != null) {
      _scanCancelRequested = true;
      VolwardNativeBridge.instance.cancelScan(_engine!);
      _scanRunningOnMainEngine = false;
    } else {
      _scanCancelRequested = true;
      _workerCancelPort?.send('cancel');
      _workerCancelPort = null;
    }

    final completer = _activeScanCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(ScanCancelledException());
    }
    _scanning = false;
    _finalizeScanTransientState();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_scanning) {
      cancelScan();
    } else {
      _finalizeScanTransientState();
    }
    scanElapsedNotifier.dispose();
    scannedFractionNotifier.dispose();
    scanProgressNotifier.dispose();
    final engine = _engine;
    if (engine != null) {
      VolwardNativeBridge.instance.freeEngine(engine);
    }
    super.dispose();
  }

  // ── Capability analysis (Lemon-style storage capabilities) ─────────────

  bool get hasCapabilityApi =>
      _ready &&
      _engine != null &&
      VolwardNativeBridge.instance.hasCapabilityApi;

  /// Synchronous capability analysis against the current snapshot. Returns
  /// the typed result, or throws [StateError] / [FormatException] on failure.
  Future<CapabilityAnalysisResult> analyzeCapability({
    required String snapshotId,
    required Capability capability,
    AnalysisOptions? options,
  }) async {
    final resolved = options ?? const AnalysisOptions(rootPath: '');
    // Paginated requests carry a cursor and must always hit the analyzer;
    // only terminal (cursor-less) results are cached.
    if (resolved.cursor == null) {
      final cached = _capabilityCache.get(snapshotId, capability, resolved);
      if (cached != null) {
        return cached;
      }
    }
    final raw = _capabilityCall(
      mode: 'analyze',
      snapshotId: snapshotId,
      capability: capability,
      options: resolved,
    );
    final result = _decodeCapabilityResult(raw, capability);
    if (resolved.cursor == null) {
      _capabilityCache.put(snapshotId, capability, resolved, result);
    }
    return result;
  }

  /// Starts an async capability job and returns its job id.
  String startCapabilityAnalysis({
    required String snapshotId,
    required Capability capability,
    AnalysisOptions? options,
  }) {
    final resolved = options ?? const AnalysisOptions(rootPath: '');
    final raw = _capabilityCall(
      mode: 'start',
      snapshotId: snapshotId,
      capability: capability,
      options: resolved,
    );
    final decoded = _decodeCapabilityJson(raw, capability, 'start');
    final error = decoded['error'];
    if (error != null) {
      throw StateError(
        'capability ${capability.wireValue} start failed: '
        '${error is Map<String, dynamic> ? '${error['code']}: ${error['message']}' : error}',
      );
    }
    final jobId = decoded['job_id'];
    if (jobId is! String || jobId.isEmpty) {
      throw FormatException(
        'capability ${capability.wireValue} start response missing job_id',
      );
    }
    return jobId;
  }

  /// Reads the current typed status of a capability job.
  CapabilityJobStatus getCapabilityJobStatus(String jobId) {
    final runner = capabilityStatusReaderForTest;
    final raw = runner != null
        ? runner(jobId)
        : _capabilityCall(mode: 'status', jobId: jobId);
    final decoded = _decodeCapabilityJson(
      raw,
      Capability.spaceAnalysis,
      'status',
    );
    final error = decoded['error'];
    if (error != null) {
      throw StateError(
        'capability job failed: ${error is Map<String, dynamic> ? '${error['code']}: ${error['message']}' : error}',
      );
    }
    return CapabilityJobStatus.fromJson(decoded);
  }

  /// Requests cancellation of an in-flight capability job.
  bool cancelCapabilityAnalysis(String jobId) {
    final runner = capabilityCancelRunnerForTest;
    if (runner != null) return runner(jobId);
    final engine = _requireCapabilityEngine();
    return VolwardNativeBridge.instance.cancelCapabilityAnalysis(engine, jobId);
  }

  /// Polls a capability job until it reaches a terminal state, yielding each
  /// progress snapshot. Use [getCapabilityJobStatus] for the final typed
  /// result after the stream completes.
  Stream<CapabilityAnalysisProgress> watchCapabilityJob(
    String jobId, {
    Duration pollInterval = const Duration(milliseconds: 300),
  }) async* {
    while (true) {
      final status = getCapabilityJobStatus(jobId);
      yield status.progress;
      if (status.isTerminal) {
        return;
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  String _capabilityCall({
    required String mode,
    String? snapshotId,
    Capability? capability,
    AnalysisOptions? options,
    String? jobId,
  }) {
    final runner = switch (mode) {
      'analyze' => capabilityAnalyzeRunnerForTest,
      'start' => capabilityStartRunnerForTest,
      _ => null,
    };
    if (runner != null) {
      return runner(
        snapshotId!,
        capability!.wireValue,
        jsonEncode(options!.toJson()),
      );
    }
    final engine = _requireCapabilityEngine();
    final bridge = VolwardNativeBridge.instance;
    return switch (mode) {
      'analyze' => bridge.analyzeCapability(
        engine,
        snapshotId!,
        capability!.wireValue,
        jsonEncode(options!.toJson()),
      ),
      'start' => bridge.startCapabilityAnalysis(
        engine,
        snapshotId!,
        capability!.wireValue,
        jsonEncode(options!.toJson()),
      ),
      'status' => bridge.getCapabilityJobStatus(engine, jobId!),
      _ => throw ArgumentError('unknown capability mode $mode'),
    };
  }

  Pointer<Void> _requireCapabilityEngine() {
    if (!_ready || _engine == null) {
      throw StateError(_initError ?? 'Native engine not ready');
    }
    return _engine!;
  }

  Map<String, dynamic> _decodeCapabilityJson(
    String raw,
    Capability capability,
    String context,
  ) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw FormatException(
        'invalid capability $context response for ${capability.wireValue}: $raw',
      );
    }
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw FormatException(
      'invalid capability $context response for ${capability.wireValue}: $raw',
    );
  }

  CapabilityAnalysisResult _decodeCapabilityResult(
    String raw,
    Capability capability,
  ) {
    final decoded = _decodeCapabilityJson(raw, capability, 'analyze');
    final error = decoded['error'];
    if (error != null) {
      throw StateError(
        'capability ${capability.wireValue} failed: '
        '${error is Map<String, dynamic> ? '${error['code']}: ${error['message']}' : error}',
      );
    }
    final result = decoded['result'];
    if (result is! Map<String, dynamic>) {
      throw FormatException(
        'capability ${capability.wireValue} analyze response missing result',
      );
    }
    return CapabilityAnalysisResult.fromJson(result);
  }
}

Map<String, dynamic>? _decodeSnapshotJsonFile(String path) {
  final raw = File(path).readAsStringSync();
  final decoded = jsonDecode(raw);
  return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
}

ScanSnapshotState? _restoreSnapshotStateFile(String path) {
  final snap = _decodeSnapshotFile(path);
  return snap == null ? null : ScanSnapshotState.fromWire(snap);
}

/// Decodes a snapshot or checkpoint file, dispatching on the file extension.
///
/// `.pb`   → protobuf wire format (written by Rust via `write_snapshot_pb_atomic`)
/// anything else → JSON (legacy format)
///
/// Called from Isolate.run, so it must be a top-level function.
Map<String, dynamic>? _decodeSnapshotFile(String path) {
  if (path.endsWith('.pb')) {
    final bytes = File(path).readAsBytesSync();
    return decodeSnapshotPb(bytes);
  }
  return _decodeSnapshotJsonFile(path);
}
