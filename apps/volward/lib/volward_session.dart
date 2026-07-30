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

/// Thrown when the user cancels an in-progress scan.
class ScanCancelledException implements Exception {
  ScanCancelledException([this.message = 'Scan cancelled']);
  final String message;

  @override
  String toString() => message;
}

/// Holds the native Volward engine pointer and exposes async wrappers for UI.
class VolwardSession extends ChangeNotifier {
  VolwardSession() {
    _initialize();
  }

  @visibleForTesting
  VolwardSession.test() : _ready = true;

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

  // Incremental counters for scannedFraction — recomputed once per snapshot
  // update inside _recomputeProgressCounters(), then read O(1) by the UI.
  int _scannedDirCount = 0;
  int _totalDirCount = 0;
  int _snapshotVersion = 0;
  final Set<String> _invalidatedPrefixes = {};
  DateTime? _lastProgressRecompute;
  // Track whether the native engine's last_snapshot matches _lastSnapshot.
  // False after restoring a snapshot from disk (defers expensive FFI hydration
  // to just before runScan()), or when _lastSnapshot changes without FFI sync.
  bool _engineHydrated = false;
  // Guards switchScanRoot against concurrent invocations (e.g. rapid taps
  // while previewTarget's Isolate is in flight).
  bool _switchingRoot = false;
  // Holds the full snapshot restored from disk, separate from _lastSnapshot
  // which may be overwritten by a lightweight preview snapshot before runScan()
  // is called.  _hydrateEngineIfNeeded() prefers this so Rust always receives
  // a structurally complete snapshot rather than a preview stub.
  ScanSnapshotState? _restoredSnapshotForHydration;
  // Throttle display-update notifications from _applyMerge. Checkpoints can
  // arrive 5-10×/sec; rebuilding the full widget tree that often is the primary
  // source of UI jank. We still update _lastSnapshot on every checkpoint for
  // correctness; we just batch the UI wake-ups to ≤ 1 per _kDisplayNotifyGap.
  DateTime? _lastApplyMergeNotify;
  static const Duration _kDisplayNotifyGap = Duration(milliseconds: 700);
  // Exposes the scan elapsed label as a ValueNotifier so the sticky bar can
  // react to the 1-Hz tick independently without triggering a full page rebuild.
  final ValueNotifier<String?> scanElapsedNotifier = ValueNotifier(null);
  // Directory-scan progress (0–1, or null when hidden). Updated after the
  // deferred tree walk in [_recomputeProgressCounters] so progress widgets can
  // rebuild locally without a full [notifyListeners] / page rebuild.
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

  /// Fail only when progress stalls during walk/classify (not total wall time).
  static const Duration _scanStallTimeout = Duration(minutes: 20);

  /// Allow long JSON serialize/deserialize after walk completes.
  static const Duration _scanSaveLoadTimeout = Duration(hours: 2);

  /// Safety net for runaway scans; normal Home scans should finish well below this.
  static const Duration _scanAbsoluteMax = Duration(hours: 8);

  bool get ready => _ready;
  String? get initError => _initError;
  String? get lastError => _lastError;
  Map<String, dynamic> get capabilities => _capabilities;
  bool get deepScanReady => _deepScanReady;
  bool get scanning => _scanning;
  bool get deleting => _deleting;
  String? get lastJobId => _lastJobId;
  ScanSnapshotState? get lastSnapshot => _lastSnapshot;
  Map<String, dynamic>? get lastDeleteReport => _lastDeleteReport;
  Map<String, dynamic>? get scanProgress => _scanProgress;
  List<String> get scanRoots => List.unmodifiable(_scanRoots);
  bool get incrementalScan => _incrementalScan;
  Set<String> get selectedEntryIds => Set.unmodifiable(_selectedEntryIds);

  int get snapshotVersion => _snapshotVersion;

  Set<String> get invalidatedPrefixes => Set.unmodifiable(_invalidatedPrefixes);

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
  /// (0.0–1.0). Returns null when a scan is not running, when the tree is
  /// empty, or when every directory is already scanned (so the progress
  /// indicator is hidden rather than stuck at 100%).
  ///
  /// Prefer listening to [scannedFractionNotifier] for UI that should update
  /// when counters finish their deferred recompute (without a full page notify).
  double? get scannedFraction {
    if (!_scanning || _totalDirCount == 0) return null;
    final f = _scannedDirCount / _totalDirCount;
    return f >= 1.0 ? null : f;
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
    _scanElapsedTimer?.cancel();
    _scanElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_scanning) {
        // Only update the elapsed label — don't fire a full notifyListeners()
        // which would rebuild the entire page on every tick.
        scanElapsedNotifier.value = scanElapsedLabel;
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

    final preferredRoot = _scanRoots.isNotEmpty
        ? _scanRoots.first
        : _defaultScanRoot();
    final path = await SnapshotCache.latestSnapshotPath(
      preferredRoot: preferredRoot,
    );
    if (path == null) return;

    _restoringSnapshot = true;
    notifyListeners();
    try {
      final restored = await Isolate.run(() => _restoreSnapshotStateFile(path));
      if (restored == null) return;
      // Skip synchronous setLastSnapshot (jsonEncode + FFI) here — it blocks
      // the main thread for hundreds of ms on large snapshots.  Instead mark
      // the engine as needing hydration; _hydrateEngineIfNeeded() will do the
      // FFI call just before the next runScan(), which is the only place Rust
      // needs an up-to-date snapshot anyway.
      _lastSnapshot = restored;
      _restoredSnapshotForHydration = _lastSnapshot;
      _engineHydrated = false;
      debugPrint('VolwardSession: restored cached snapshot from $path');
    } catch (e, st) {
      debugPrint('VolwardSession: restore cached snapshot failed: $e\n$st');
    } finally {
      _restoringSnapshot = false;
      notifyListeners();
    }
  }

  void setScanRoots(List<String> roots) {
    _scanRoots = List.from(roots);
    notifyListeners();
  }

  void clearScanRoots() {
    _scanRoots = [];
    notifyListeners();
  }

  /// Synchronises the native engine's last_snapshot with the Dart-side
  /// [_lastSnapshot].  Called just before [runScan] so the heavy
  /// jsonEncode+FFI work happens on a predictable, intentional code path
  /// rather than during snapshot restore (which would freeze the UI).
  void _hydrateEngineIfNeeded() {
    if (_engineHydrated) return;
    // Prefer the full restored snapshot over _lastSnapshot, which may have been
    // overwritten by a lightweight preview stub (buildPreviewSnapshot) that Rust
    // cannot meaningfully parse as an incremental base.
    final snap = _restoredSnapshotForHydration ?? _lastSnapshot;
    if (snap == null || _engine == null) return;
    if (VolwardNativeBridge.instance.setLastSnapshot(_engine!, snap.toWire())) {
      _engineHydrated = true;
      _restoredSnapshotForHydration = null; // consumed — free the memory
    } else {
      debugPrint('VolwardSession: failed to hydrate engine before scan');
    }
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
    // Debounce rapid taps: if a previous switchScanRoot is still awaiting
    // previewTarget's Isolate, ignore the new call to avoid _scanRoots being
    // overwritten mid-flight and two _runScanAutostart() competing.
    if (_switchingRoot) return;
    _switchingRoot = true;
    var handedOffToBackground = false;
    try {
      final newRoots = path != null ? [path] : <String>[];
      final newRoot = path ?? _defaultScanRoot();
      final currentRoot = _scanRoots.isNotEmpty
          ? _scanRoots.first
          : _defaultScanRoot();

      if (_scanning) {
        final isSubtree =
            newRoot == currentRoot || newRoot.startsWith('$currentRoot/');

        if (isSubtree) {
          // Keep the full scan running — just narrow the display and peek-scan
          // the new root so it fills in immediately.
          _scanRoots = newRoots;
          notifyListeners();
          unawaited(peekScan(newRoot));
          return;
        }
        // Unrelated root: cancel first, then fall through to fresh scan below.
        cancelScan();
        // Reset hydration state so the engine doesn't carry the old root's
        // snapshot into the new scan as an incremental base.
        _engineHydrated = true;
        _restoredSnapshotForHydration = null;
      }

      // Fresh scan for the new root.
      _scanRoots = newRoots;
      _lastSnapshot = null;
      _restoredSnapshotForHydration = null;
      _engineHydrated = true;
      _snapshotVersion++;
      _invalidatedPrefixes.clear();
      notifyListeners();
      handedOffToBackground = true;
      unawaited(_previewThenRunScanAutostart());
    } finally {
      if (!handedOffToBackground) {
        _switchingRoot = false;
      }
    }
  }

  Future<void> _previewThenRunScanAutostart() async {
    try {
      await previewTarget();
      // Fire-and-forget — errors surface via _lastError / notifyListeners.
      unawaited(_runScanAutostart());
    } finally {
      _switchingRoot = false;
    }
  }

  /// Internal helper: start a scan and store the completion status without
  /// surfacing a Future to the caller (used by [switchScanRoot]).
  Future<void> _runScanAutostart() async {
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
  Future<void> previewTarget() async {
    if (!_ready || _engine == null) return;
    if (!VolwardNativeBridge.instance.hasQuickListApi) return;

    final root = _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot();
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
      return;
    }

    final previewEntries = entries.length > _maxPreviewEntries
        ? entries.take(_maxPreviewEntries).toList(growable: false)
        : entries;
    _lastSnapshot = ScanSnapshotState.fromWire(
      buildPreviewSnapshot(rootPath: root, quickListEntries: previewEntries),
    );
    notifyListeners();
  }

  /// Triggers a small, scoped scan of [path] so its contents/size become
  /// available immediately, without waiting for the background full scan
  /// to reach it. No-op if a peek for this path is already in flight or
  /// already completed this session, or if the concurrency limit is hit
  /// (extra clicks are simply dropped — the background scan will cover the
  /// path eventually regardless).
  Future<void> peekScan(String path) async {
    if (!_ready || _engine == null) return;
    if (_peekInFlight.contains(path) || _peekCompleted.contains(path)) return;
    if (_peekInFlight.length >= _maxConcurrentPeeks) return;
    // volwardPeekScanIsolate requires startScanAsyncWithOptions. If the dylib
    // is outdated, log once and let the isolate report the error — at least
    // the peek won't silently add this path to _peekCompleted and block retries.
    if (!VolwardNativeBridge.instance.hasScanOptionsApi) {
      debugPrint(
        'VolwardSession: peekScan skipped for $path — rebuild Rust '
        '(cd apps/volward/macos && bash build_rust.sh) then restart (R).',
      );
      return;
    }

    _peekInFlight.add(path);
    ReceivePort? receivePort;
    try {
      receivePort = ReceivePort();
      await Isolate.spawn(volwardPeekScanIsolate, [receivePort.sendPort, path]);
      final message = await receivePort.first;
      if (message is! Map) return;
      final type = message['type']?.toString();
      if (type == 'done') {
        final tree = message['tree'];
        final entriesRaw = message['entries'];
        if (tree is Map) {
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
    // Sync the native engine with the current Dart snapshot before scanning.
    // This is deferred from restore to avoid blocking the UI on startup.
    _hydrateEngineIfNeeded();
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
    _lastError = null;
    _lastDeleteReport = null;
    _scanProgress = null;
    _workerCancelPort = null;
    _scanChannelsClosed = false;
    _lastScanActivityAt = null;
    _savingPhaseStartedAt = null;
    _peekInFlight.clear();
    _peekCompleted.clear();
    // Clear stale fraction from a previous scan, then seed counters from
    // whatever tree is already in _lastSnapshot (usually the preview).
    // Without the seed, scannedFraction stays null until the first checkpoint
    // and the UI shows "…" rather than a real % at startup.
    _scannedDirCount = 0;
    _totalDirCount = 0;
    _publishScannedFraction();
    _recomputeProgressCounters(force: true);
    _startScanElapsedTimer();
    notifyListeners();

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
        if (path != null && path.isNotEmpty) {
          unawaited(_applyCheckpointFromFile(path));
        }
      } else if (type == 'done') {
        _touchScanActivity(phase: 'LoadingResults');
        _closeScanChannels();
        final path = m['snapshot_path']?.toString();
        if (path != null && path.isNotEmpty) {
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
      _lastSnapshot = await _awaitScanWithStallGuard(completer.future);
      notifyListeners();
      return _lastSnapshot?.snapshotId ?? 'done';
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
    _engineHydrated = true; // Engine now matches the snapshot we just loaded.
    return ScanSnapshotState.fromWire(snap);
  }

  Future<void> _applyCheckpointFromFile(String path) async {
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

  /// Recomputes [_scannedDirCount] and [_totalDirCount] by walking the raw
  /// [_lastSnapshot] tree. O(tree size) but throttled to at most once per 500ms
  /// to avoid jank from frequent checkpoints on large trees. Pass [force: true]
  /// to bypass the throttle (e.g., at scan startup or completion).
  void _recomputeProgressCounters({bool force = false}) {
    // Throttle: skip if called within 500ms of the last recompute, unless forced.
    final now = DateTime.now();
    if (!force && _lastProgressRecompute != null) {
      final elapsed = now.difference(_lastProgressRecompute!);
      if (elapsed < const Duration(milliseconds: 500)) {
        return; // skip this update, counters are recent enough
      }
    }
    _lastProgressRecompute = now;

    // Defer the O(tree) traversal to the next event-loop iteration so it does
    // not block the current frame's build/layout/paint pipeline.  Progress UI
    // listens to [scannedFractionNotifier] and tolerates being one tick late.
    final snapshot = _lastSnapshot; // capture before async gap
    unawaited(
      Future<void>(() {
        if (snapshot == null || !identical(snapshot, _lastSnapshot)) return;
        var total = 0;
        var done = 0;
        void visit(ScanTreeNode node) {
          if (!node.isDirectory) return;
          total++;
          if (node.scanned) done++;
          for (final c in node.children) {
            visit(c);
          }
        }

        final root = snapshot.tree;
        if (root != null) {
          visit(root);
        }
        _scannedDirCount = done;
        _totalDirCount = total;
        // Local notifier only — do NOT call notifyListeners() here (that would
        // rebuild the whole page on every deferred walk).
        _publishScannedFraction();
      }),
    );
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
    _recomputeProgressCounters();
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
      notifyListeners();
    }
  }

  void cancelScan() {
    if (!_scanning) return;

    _workerCancelPort?.send('cancel');
    _workerCancelPort = null;
    _closeScanChannels();

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
