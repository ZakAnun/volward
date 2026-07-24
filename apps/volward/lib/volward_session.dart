import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'bridge/native_bridge.dart';
import 'bridge/scan_worker.dart';
import 'scan_preview.dart';
import 'scan_snapshot_merge.dart';
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

  Pointer<Void>? _engine;
  bool _ready = false;
  String? _initError;
  String? _lastError;
  Map<String, dynamic> _capabilities = {};
  bool _deepScanReady = false;
  bool _scanning = false;
  bool _deleting = false;
  String? _lastJobId;
  Map<String, dynamic>? _lastSnapshot;
  Map<String, dynamic>? _lastDeleteReport;
  Map<String, dynamic>? _scanProgress;
  List<String> _scanRoots = [];
  bool _incrementalScan = false;
  final Set<String> _selectedEntryIds = {};
  SendPort? _workerCancelPort;
  Timer? _scanElapsedTimer;
  DateTime? _scanStartedAt;

  Completer<Map<String, dynamic>?>? _activeScanCompleter;
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
  Map<String, dynamic>? get lastSnapshot => _lastSnapshot;
  Map<String, dynamic>? get lastDeleteReport => _lastDeleteReport;
  Map<String, dynamic>? get scanProgress => _scanProgress;
  List<String> get scanRoots => List.unmodifiable(_scanRoots);
  bool get incrementalScan => _incrementalScan;
  Set<String> get selectedEntryIds => Set.unmodifiable(_selectedEntryIds);

  /// Whether the bundled native library supports file-based snapshot I/O.
  bool get hasSnapshotFileApi =>
      VolwardNativeBridge.instance.hasSnapshotFileApi;

  /// Whether the bundled native library supports incremental scan options.
  bool get hasScanOptionsApi => VolwardNativeBridge.instance.hasScanOptionsApi;

  /// Increment scan requires both snapshot file API and scan options FFI.
  bool get canUseIncrementalScan =>
      hasSnapshotFileApi && hasScanOptionsApi;

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
        notifyListeners();
      }
    });
  }

  void _stopScanElapsedTimer() {
    _scanElapsedTimer?.cancel();
    _scanElapsedTimer = null;
    _scanStartedAt = null;
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

  Future<Map<String, dynamic>?> _awaitScanWithStallGuard(
    Future<Map<String, dynamic>?> future,
  ) async {
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
    final path =
        await SnapshotCache.latestSnapshotPath(preferredRoot: preferredRoot);
    if (path == null) return;

    _restoringSnapshot = true;
    notifyListeners();
    try {
      final snap = await Isolate.run(() => _decodeSnapshotJsonFile(path));
      if (snap == null) return;
      if (!VolwardNativeBridge.instance.setLastSnapshot(_engine!, snap)) {
        debugPrint('VolwardSession: failed to hydrate engine from cached snapshot');
        return;
      }
      _lastSnapshot = snap;
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

    _lastSnapshot = buildPreviewSnapshot(rootPath: root, quickListEntries: entries);
    notifyListeners();
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
    _lastError = null;
    _lastDeleteReport = null;
    _scanProgress = null;
    _workerCancelPort = null;
    _scanChannelsClosed = false;
    _lastScanActivityAt = null;
    _savingPhaseStartedAt = null;
    _startScanElapsedTimer();
    notifyListeners();

    _scanReceivePort = ReceivePort();
    _scanCancelInitPort = ReceivePort();
    final completer = Completer<Map<String, dynamic>?>();
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
            snap is Map ? Map<String, dynamic>.from(snap) : null,
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
      return _lastSnapshot?['snapshot_id']?.toString() ?? 'done';
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
    final snapshotId = _lastSnapshot?['snapshot_id']?.toString();
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

  Future<Map<String, dynamic>?> _loadSnapshotFromFile(String path) async {
    final pathsSeen = (_scanProgress?['paths_seen'] as num?)?.toInt();
    _setScanProgressPhase('LoadingResults', pathsSeen: pathsSeen);

    if (!_ready || _engine == null) {
      throw StateError('Native engine not ready');
    }

    final snap = await Isolate.run(() => _decodeSnapshotJsonFile(path));
    try {
      await File(path).delete();
    } catch (_) {}

    if (snap == null) {
      throw StateError('Invalid snapshot file');
    }
    if (!VolwardNativeBridge.instance.setLastSnapshot(_engine!, snap)) {
      throw StateError('Failed to load scan snapshot into engine');
    }
    return snap;
  }

  Future<void> _applyCheckpointFromFile(String path) async {
    try {
      final checkpoint = await Isolate.run(() => _decodeSnapshotJsonFile(path));
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

      _applyMerge(rootPath, Map<String, dynamic>.from(tree), entries);
    } catch (e, st) {
      debugPrint('VolwardSession: apply checkpoint failed: $e\n$st');
    }
  }

  void _applyMerge(
    String targetPath,
    Map<String, dynamic> subtreeTree,
    List<Map<String, dynamic>> subtreeEntries,
  ) {
    final current = _lastSnapshot;
    if (current == null) return;
    final merged = mergeSubtreeIntoSnapshot(
      snapshot: current,
      targetPath: targetPath,
      subtreeTree: subtreeTree,
      subtreeEntries: subtreeEntries,
    );
    // Force every merge to look like "new data" to snapshot_id-keyed UI
    // caches, even though checkpoints from the same scan job would
    // otherwise all share the same Rust-side snapshot_id.
    merged['snapshot_id'] = 'live-${DateTime.now().microsecondsSinceEpoch}';
    _lastSnapshot = merged;
    notifyListeners();
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
