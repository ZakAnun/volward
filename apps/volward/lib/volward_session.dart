import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'bridge/native_bridge.dart';
import 'bridge/scan_worker.dart';
import 'proto/snapshot_pb_decoder.dart';
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

  VolwardSession.test() : _ready = true;

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
  bool _incrementalScan = false;
  final Set<String> _selectedEntryIds = {};
  final Set<String> _peekInFlight = {};
  final Set<String> _peekCompleted = {};
  static const int _maxConcurrentPeeks = 2;
  static const int _maxPreviewEntries = 2000;
  static const int _maxAutoRestoreBytes = 128 * 1024 * 1024;
  int _snapshotVersion = 0;
  final Set<String> _invalidatedPrefixes = {};
  // Monotonic token for root switches. If the user picks folders quickly, only
  // the latest preview/scan handoff may update the visible snapshot.
  int _rootSwitchGeneration = 0;

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
  SendPort? _workerCancelPort;
  Timer? _scanElapsedTimer;
  DateTime? _scanStartedAt;

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

  /// Fail only when progress stalls during walk/classify (not total wall time).
  static const Duration _scanStallTimeout = Duration(minutes: 20);

  /// Allow long JSON serialize/deserialize after walk completes.
  static const Duration _scanSaveLoadTimeout = Duration(hours: 2);

  /// Safety net for runaway scans; normal Home scans should finish well below this.
  static const Duration _scanAbsoluteMax = Duration(hours: 8);

  static const Duration _minTargetPreviewLoading = Duration(milliseconds: 180);

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
  bool get incrementalScan => _incrementalScan;
  Set<String> get selectedEntryIds => Set.unmodifiable(_selectedEntryIds);

  int get snapshotVersion => _snapshotVersion;

  Set<String> get invalidatedPrefixes => Set.unmodifiable(_invalidatedPrefixes);

  Set<String> consumeInvalidatedPrefixes() {
    final prefixes = Set<String>.from(_invalidatedPrefixes);
    _invalidatedPrefixes.clear();
    return prefixes;
  }

  @visibleForTesting
  void setSnapshotForTest(ScanSnapshotState snapshot) {
    _lastSnapshot = snapshot;
    _snapshotVersion++;
    _invalidatedPrefixes.clear();
    notifyListeners();
  }

  @visibleForTesting
  void updateSnapshotForTest(
    ScanSnapshotState snapshot, {
    required String affectedPrefix,
  }) {
    _lastSnapshot = snapshot;
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
  void _publishScannedFraction() {
    final next = scannedFraction;
    if (scannedFractionNotifier.value != next) {
      scannedFractionNotifier.value = next;
    }
  }

  /// Whether the bundled native library supports file-based snapshot I/O.
  bool get hasSnapshotFileApi =>
      VolwardNativeBridge.instance.hasSnapshotFileApi;

  /// Whether the bundled native library supports incremental scan options.
  bool get hasScanOptionsApi => VolwardNativeBridge.instance.hasScanOptionsApi;

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
    _scanElapsedTimer?.cancel();
    _scanElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_scanning) {
        // Only update the elapsed label — don't fire a full notifyListeners()
        // which would rebuild the entire page on every tick.
        scanElapsedNotifier.value = scanElapsedLabel;
        _publishScannedFraction();
      }
    });
  }

  void _stopScanElapsedTimer() {
    _scanElapsedTimer?.cancel();
    _scanElapsedTimer = null;
    _scanStartedAt = null;
    scanElapsedNotifier.value = null;
  }

  void _setScanProgressPhase(String phase, {int? pathsSeen}) {
    _touchScanActivity(phase: phase);
    _scanProgress = {
      'phase': phase,
      if (pathsSeen != null) 'paths_seen': pathsSeen,
      if (_scanProgress?['paths_seen'] != null && pathsSeen == null)
        'paths_seen': _scanProgress!['paths_seen'],
    };
    _publishScannedFraction();
    notifyListeners();
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
          'Volward: bundled libvolward_facade.dylib is outdated (missing snapshot file FFI). '
          'Run: cd apps/volward/macos && bash build_rust.sh — then fully restart the app (R).',
        );
      }
      _ready = true;
      await restoreCachedSnapshotIfNeeded();
    } catch (e, st) {
      _initError = '$e';
      debugPrint('VolwardSession init failed: $e\n$st');
    }
    notifyListeners();
  }

  String _defaultScanRoot() {
    return Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/';
  }

  /// Reload the last on-disk snapshot into memory (after hot reload / restart).
  Future<void> restoreCachedSnapshotIfNeeded() async {
    if (!_ready || _engine == null || _lastSnapshot != null || _scanning) {
      return;
    }
    await _restoreCachedSnapshot();
  }

  Future<void> _restoreCachedSnapshot() async {
    if (!_ready || _engine == null || _scanning) return;

    final preferredRoot =
        _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot();
    final path = await SnapshotCache.latestSnapshotPath(
      preferredRoot: preferredRoot,
    );
    if (path == null) return;
    final cacheFile = File(path);
    try {
      final size = await cacheFile.length();
      if (size > _maxAutoRestoreBytes) {
        debugPrint(
          'VolwardSession: skip auto-restore for oversized cache '
          '$path (${size ~/ (1024 * 1024)} MB)',
        );
        return;
      }
    } catch (_) {
      return;
    }

    _restoringSnapshot = true;
    notifyListeners();
    try {
      ScanSnapshotState? restored;
      if (hasIndexApi) {
        final loaded = VolwardNativeBridge.instance.loadIndexFromPath(
          _engine!,
          path,
        );
        if (loaded) {
          final summary = VolwardNativeBridge.instance.getIndexSummaryJson(
            _engine!,
          );
          if (summary != null && !summary.containsKey('error')) {
            restored = ScanSnapshotState.fromIndexSummary(summary);
          }
        }
      }
      restored ??= await Isolate.run(() => _restoreSnapshotStateFile(path));
      if (restored == null) return;
      _lastSnapshot = restored;
      debugPrint('VolwardSession: restored cached snapshot from $path');
    } catch (e, st) {
      debugPrint('VolwardSession: restore cached snapshot failed: $e\n$st');
    } finally {
      _restoringSnapshot = false;
      notifyListeners();
    }
  }

  /// Path the UI is currently browsing — used as the refresh target.
  /// Set by [setCurrentDirectory] from [HomePage] column selection.
  String? get currentDirectoryPath => _currentDirectoryPath;

  /// The path that [refreshCurrentDirectory] will target (Design §6.1):
  /// focused subdirectory → scan root → default home.
  String get refreshTargetPath =>
      _currentDirectoryPath ??
      (_scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot());

  /// Called by [HomePage] whenever the column selection changes.
  void setCurrentDirectory(String? path) {
    if (_currentDirectoryPath == path) return;
    _currentDirectoryPath = path;
    // No notifyListeners() — this is UI-state bookkeeping, not display data.
  }

  @visibleForTesting
  void setCurrentPathForTest(String path) => _currentDirectoryPath = path;

  void setScanRoots(List<String> roots) {
    _scanRoots = List.from(roots);
    _currentDirectoryPath = null;
    notifyListeners();
  }

  void clearScanRoots() {
    _scanRoots = [];
    _currentDirectoryPath = null;
    notifyListeners();
  }

  /// Switch the active scan root, implementing Plan B:
  ///
  /// * If a scan is already running **and** [path] is a strict sub-directory of
  ///   the current scan root, the background scan is left untouched.  A peek
  ///   scan is triggered immediately so the new subtree fills in quickly, and
  ///   [_scanRoots] is updated so the UI filters to [path].
  ///
  /// * Otherwise (unrelated root, or no active scan) the current scan is
  ///   cancelled, the new root is previewed, and a fresh full scan is started
  ///   automatically.
  Future<void> switchScanRoot(String? path) async {
    final generation = ++_rootSwitchGeneration;
    final newRoots = path != null ? [path] : <String>[];
    final newRoot = ScanTreeBuilder.normalizeRoot(path ?? _defaultScanRoot());
    final currentRoot = ScanTreeBuilder.normalizeRoot(
      _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot(),
    );
    final keepRunningScan = _scanning &&
        (newRoot == currentRoot || newRoot.startsWith('$currentRoot/'));

    if (_scanning && !keepRunningScan) {
      cancelScan();
    }

    _scanRoots = newRoots;
    _currentDirectoryPath = null;
    _lastSnapshot = null;
    _lastDeleteReport = null;
    _targetPreviewLoading = true;
    _targetPreviewStartedAt = DateTime.now();
    _snapshotVersion++;
    _invalidatedPrefixes.clear();
    _peekInFlight.clear();
    _peekCompleted.clear();
    notifyListeners();

    unawaited(
      _previewThenContinueRootSwitch(
        generation,
        newRoot: newRoot,
        startFullScan: !keepRunningScan,
      ),
    );
  }

  Future<void> _previewThenContinueRootSwitch(
    int generation, {
    required String newRoot,
    required bool startFullScan,
  }) async {
    await previewTarget(expectedGeneration: generation);
    if (generation != _rootSwitchGeneration) return;
    if (startFullScan) {
      await _waitForScanIdle(generation);
      if (generation != _rootSwitchGeneration) return;
      // Fire-and-forget — errors surface via _lastError / notifyListeners.
      unawaited(_runScanAutostart(generation));
    } else {
      unawaited(peekScan(newRoot, force: true));
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
    if (!_ready || _engine == null) return;
    if (!VolwardNativeBridge.instance.hasQuickListApi) {
      _clearTargetPreviewLoading(expectedGeneration);
      return;
    }

    final root = ScanTreeBuilder.normalizeRoot(
      _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot(),
    );
    List<Map<String, dynamic>> entries;
    try {
      entries = await Isolate.run(() {
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
      _clearTargetPreviewLoading(expectedGeneration);
      return;
    }

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
        path,
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
  Future<void> refreshCurrentDirectory() async {
    if (!_ready || _engine == null) return;
    final path = refreshTargetPath;
    final root = ScanTreeBuilder.normalizeRoot(
      _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot(),
    );
    final target = ScanTreeBuilder.normalizeRoot(path);
    if (target == root) {
      _currentDirectoryPath = null;
    } else {
      _currentDirectoryPath = path;
    }
    _invalidatedPrefixes.add(path);
    _snapshotVersion++;
    notifyListeners();
    try {
      if (target == root) {
        await runScan();
      } else {
        await peekScan(path, force: true);
      }
    } catch (e, st) {
      debugPrint('VolwardSession: refreshCurrentDirectory failed: $e\n$st');
    }
  }

  /// Triggers a small, scoped scan of [path] so its contents/size become
  /// available immediately, without waiting for the background full scan
  /// to reach it. No-op if a peek for this path is already in flight or
  /// already completed this session, or if the concurrency limit is hit
  /// (extra clicks are simply dropped — the background scan will cover the
  /// path eventually regardless).
  Future<void> peekScan(String path, {bool force = false}) async {
    if (!_ready || _engine == null) return;
    if (_peekInFlight.contains(path)) return;
    if (!force && _peekCompleted.contains(path)) return;
    if (_peekInFlight.length >= _maxConcurrentPeeks) return;
    final generation = _rootSwitchGeneration;

    _peekInFlight.add(path);
    notifyListeners();
    ReceivePort? receivePort;
    try {
      receivePort = ReceivePort();
      await Isolate.spawn(volwardPeekScanIsolate, [receivePort.sendPort, path]);
      final message = await receivePort.first;
      if (message is! Map) return;
      final type = message['type']?.toString();
      if (type == 'done') {
        if (generation != _rootSwitchGeneration) return;
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
          await _applyMerge(
            path,
            Map<String, dynamic>.from(tree),
            entries,
            authoritative: true,
          );
          _peekCompleted.add(path);
        }
      } else {
        debugPrint(
          'VolwardSession: peekScan($path) failed: ${message['error']}',
        );
      }
    } catch (e, st) {
      debugPrint('VolwardSession: peekScan($path) error: $e\n$st');
    } finally {
      receivePort?.close();
      _peekInFlight.remove(path);
      notifyListeners();
    }
  }

  void setIncrementalScan(bool incremental) {
    if (incremental && !canUseIncrementalScan) return;
    if (_incrementalScan == incremental) return;
    _incrementalScan = incremental;
    notifyListeners();
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
    if (!hasSnapshotFileApi) {
      throw StateError(
        'Native library is outdated. Run: cd apps/volward/macos && bash build_rust.sh '
        '— then fully restart the app (R).',
      );
    }
    if (_incrementalScan && !canUseIncrementalScan) {
      throw StateError(
        'Incremental scan requires an updated native library. Run: cd apps/volward/macos && bash build_rust.sh '
        '— then fully restart the app (R).',
      );
    }

    final effectiveRoots = _scanRoots.isNotEmpty
        ? _scanRoots
        : [
            Platform.environment['HOME'] ??
                Platform.environment['USERPROFILE'] ??
                '/',
          ];

    _scanning = true;
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
    _startScanElapsedTimer();
    _setScanProgressPhase('DiscoveringRoots', pathsSeen: 0);

    if (hasIndexApi) {
      final jobId = 'job-${DateTime.now().millisecondsSinceEpoch}';
      _lastJobId = jobId;
      try {
        final snapshot = await _awaitScanWithStallGuard(
          _runIndexScanOnMainEngine(jobId, effectiveRoots),
        );
        if (scanGeneration == _rootSwitchGeneration) {
          _lastSnapshot = snapshot;
          notifyListeners();
        }
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
        _lastScanActivityAt = null;
        _savingPhaseStartedAt = null;
        _stopScanElapsedTimer();
        _publishScannedFraction(); // hide progress once scanning ends
        notifyListeners();
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
        notifyListeners();
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
          _loadSnapshotFromFile(path).then((snap) {
            if (!completer.isCompleted) {
              completer.complete(snap);
            }
          }).catchError((Object e, StackTrace st) {
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
        notifyListeners();
      }
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
      _activeScanCompleter = null;
      _workerCancelPort = null;
      _scanning = false;
      _lastScanActivityAt = null;
      _savingPhaseStartedAt = null;
      _stopScanElapsedTimer();
      _publishScannedFraction(); // hide progress once scanning ends
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> deleteEntries(
    List<String> entryIds, {
    bool dryRun = false,
    bool rescanAfterDelete = false,
  }) async {
    if (!_ready || _engine == null) {
      throw StateError(_initError ?? 'Native engine not ready');
    }
    final snapshotId = _lastSnapshot?.snapshotId;
    if (snapshotId == null || snapshotId.isEmpty) {
      throw StateError('No scan snapshot — run a scan first');
    }

    _deleting = true;
    _lastError = null;
    notifyListeners();
    try {
      final report = VolwardNativeBridge.instance.deleteEntries(
        _engine!,
        snapshotId,
        entryIds,
        dryRun: dryRun,
      );
      if (report.containsKey('error')) {
        throw StateError(report['error'].toString());
      }
      if (!dryRun) {
        _lastDeleteReport = report;
      }
      if (!dryRun && rescanAfterDelete) {
        await runScan();
      }
      return report;
    } catch (e, st) {
      _lastError = '$e';
      debugPrint('VolwardSession delete failed: $e\n$st');
      rethrow;
    } finally {
      _deleting = false;
      notifyListeners();
    }
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
    try {
      final report = VolwardNativeBridge.instance.emptyTrash(_engine!);
      if (report.containsKey('error')) {
        throw StateError(report['error'].toString());
      }
      if (rescanAfterEmpty && _lastSnapshot != null) {
        await runScan();
      }
      return report;
    } catch (e, st) {
      _lastError = '$e';
      debugPrint('VolwardSession empty trash failed: $e\n$st');
      rethrow;
    } finally {
      _deleting = false;
      notifyListeners();
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
    return ScanSnapshotState.fromWire(snap);
  }

  Future<ScanSnapshotState?> _runIndexScanOnMainEngine(
    String jobId,
    List<String> roots,
  ) async {
    if (!_ready || _engine == null) {
      throw StateError('Native engine not ready');
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
        // Wait for the native worker to exit so the next scan can start
        // cleanly on the shared main engine.
        while (bridge.isScanRunning(_engine!)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        throw ScanCancelledException();
      }
      final progress = bridge.getLastProgress(_engine!);
      if (progress != null) {
        final phase = progress['phase']?.toString();
        _touchScanActivity(phase: phase);
        _scanProgress = progress;
        _notifyNativeProgressIfNeeded(phase);
      }
    }
    if (_scanCancelRequested) {
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
      notifyListeners();
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

  Future<void> _applyMerge(
    String targetPath,
    Map<String, dynamic> subtreeTree,
    List<Map<String, dynamic>> subtreeEntries, {
    bool authoritative = false,
  }) async {
    final current = _lastSnapshot;
    if (current == null) return;
    final merged = mergeSubtreeIntoSnapshotState(
      snapshot: current,
      targetPath: targetPath,
      subtreeTree: subtreeTree,
      subtreeEntries: subtreeEntries,
      replacementIsAuthoritative: authoritative,
    );
    // Force every merge to look like "new data" to snapshot_id-keyed UI
    // caches, even though checkpoints from the same scan job would
    // otherwise all share the same Rust-side snapshot_id.
    _lastSnapshot = ScanSnapshotState(
      snapshotId: 'live-${DateTime.now().microsecondsSinceEpoch}',
      scannedAtMs: merged.scannedAtMs,
      stats: merged.stats,
      reclaimableEstimateBytes: merged.reclaimableEstimateBytes,
      tree: merged.tree,
      entryCount: merged.entryCount,
      categoryCounts: merged.categoryCounts,
      deletableCategoryCounts: merged.deletableCategoryCounts,
      deletableCount: merged.deletableCount,
      extraFields: merged.extraFields,
    );
    _snapshotVersion++;
    _invalidatedPrefixes.add(targetPath);
    // Throttle UI notifications: checkpoints can arrive 5-10×/sec.  We always
    // update _lastSnapshot above for correctness; we just batch widget rebuilds
    // to at most once per _kDisplayNotifyGap so the main thread isn't saturated
    // with O(N log N) display-tree recomputations.  Authoritative merges (peek
    // results) always notify immediately so the user sees results without delay.
    final now = DateTime.now();
    final shouldNotify = authoritative ||
        !_scanning ||
        _lastApplyMergeNotify == null ||
        now.difference(_lastApplyMergeNotify!) >= _kDisplayNotifyGap;
    if (shouldNotify) {
      _lastApplyMergeNotify = now;
      notifyListeners();
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
      _closeScanChannels();
    }

    final completer = _activeScanCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(ScanCancelledException());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _stopScanElapsedTimer();
    scanElapsedNotifier.dispose();
    scannedFractionNotifier.dispose();
    _closeScanChannels();
    final engine = _engine;
    if (engine != null) {
      VolwardNativeBridge.instance.freeEngine(engine);
    }
    super.dispose();
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
