import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../bridge/scan_worker.dart';
import '../../cache_restore_policy.dart';
import '../../scan_preview.dart';
import '../../scan_root_record.dart';
import '../../scan_snapshot_merge.dart';
import '../../scan_snapshot_state.dart';
import '../../scan_tree.dart';
import '../../snapshot_cache.dart';
import '../contracts/native_engine_ports.dart';
import '../contracts/scan_contracts.dart';
import '../contracts/scan_session_host.dart';
import '../contracts/snapshot_decoder.dart';
import 'scan_progress_estimate.dart';
import 'snapshot_persistence.dart';

enum ScanSessionNotificationKind { batched, immediate }

/// Owns scan lifecycle, restore generations, preview state and worker state.
class ScanSession extends ChangeNotifier implements ScanLifecycle {
  ScanSession({
    required this._host,
    required this._persistence,
    required this.snapshotFileDecoder,
    this._persistSessionStateEnabled = true,
  });

  final ScanSessionHost _host;
  final SnapshotPersistence _persistence;
  final bool _persistSessionStateEnabled;
  final SnapshotFileDecoder snapshotFileDecoder;
  final StreamController<ScanSessionNotificationKind> _notificationController =
      StreamController<ScanSessionNotificationKind>.broadcast(sync: true);

  bool _scanning = false;
  bool _scanPreparing = false;
  String? _lastJobId;
  ScanSnapshotState? _lastSnapshot;
  Map<String, dynamic>? _scanProgress;
  List<String> _scanRoots = [];
  bool _incrementalScan = false;
  String? _lastCustomRoot;
  List<String> _recentCustomRoots = [];
  int _rootSwitchGeneration = 0;
  int _rootSwitchRequestGeneration = 0;
  final Set<String> _peekInFlight = {};
  final Set<String> _peekCompleted = {};
  final Map<String, Completer<void>> _pendingForcedPeeks = {};
  final Map<String, int> _peekOperationTokens = {};
  int _nextPeekOperationToken = 0;
  bool _targetPreviewLoading = false;
  DateTime? _targetPreviewStartedAt;
  int _cacheRestoreGeneration = 0;
  Completer<void>? _cacheRestoreCompleter;
  bool _restoringSnapshot = false;

  final ValueNotifier<String?> scanElapsedNotifier = ValueNotifier(null);
  final ValueNotifier<double?> scannedFractionNotifier = ValueNotifier(null);
  final ValueNotifier<ScanProgressViewState> scanProgressNotifier =
      ValueNotifier(const ScanProgressViewState());

  SendPort? _workerCancelPort;
  Timer? _scanElapsedTimer;
  DateTime? _scanStartedAt;
  int _transientFinalizeCount = 0;
  DateTime? _lastApplyMergeNotify;
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
  bool _scanPauseRequested = false;
  int _nextScanRunId = 0;
  int? _activeScanRunId;
  int? _completedScanRunId;
  String? _scanStartErrorToPreserve;

  static const int _maxConcurrentPeeks = 2;
  static const int _maxPreviewEntries = 2000;
  static const int _maxAutoRestoreBytes = 128 * 1024 * 1024;
  static const int _maxRecentCustomRoots = 5;
  static const Duration _kDisplayNotifyGap = Duration(milliseconds: 700);
  static const Duration _scanStallTimeout = Duration(minutes: 20);
  static const Duration _scanSaveLoadTimeout = Duration(hours: 2);
  static const Duration _scanAbsoluteMax = Duration(hours: 8);
  static const Duration _nativeScanStopTimeout = Duration(seconds: 8);
  static const Duration _minTargetPreviewLoading = Duration(milliseconds: 180);
  static const Duration _peekScanTimeout = Duration(seconds: 60);

  @visibleForTesting
  String Function()? defaultRootForTest;
  @visibleForTesting
  bool Function(String path)? rootExistsForTest;
  @visibleForTesting
  Future<ScanSnapshotState?> Function(String jobId, List<String> roots)?
  scanRunnerForTest;
  @visibleForTesting
  Future<List<Map<String, dynamic>>> Function(String path)?
  scanRootPreviewReaderForTest;
  @visibleForTesting
  Future<bool> Function()? pauseCurrentScanForTest;
  @visibleForTesting
  String Function(String root, String cacheDir)? pauseRequestForTest;
  @visibleForTesting
  String? Function()? pauseErrorForTest;
  @visibleForTesting
  Future<void> Function()? scanPreparationWaitForTest;
  @visibleForTesting
  Duration? nativeScanStopTimeoutForTest;
  @visibleForTesting
  Duration? restoreDelayForTest;
  @visibleForTesting
  VoidCallback? restoreDelayStartedForTest;
  @visibleForTesting
  Duration? cacheRestoreTimeoutForTest;
  @visibleForTesting
  bool treatAsIndexApiForTest = false;
  @visibleForTesting
  ScanSnapshotState? engineIndexSnapshotForTest;
  @visibleForTesting
  int startIndexLoadCallsForTest = 0;
  @visibleForTesting
  List<String>? indexLoadAsyncResultsForTest;
  @visibleForTesting
  bool Function()? isIndexLoadingForTest;

  bool get _ready => _host.ready;
  String? get _initError => _host.initError;
  String? get _lastError => _host.lastError;
  set _lastError(String? value) => _host.lastError = value;
  bool get hasIndexApi =>
      treatAsIndexApiForTest || _host.indexEngine.hasIndexApi;
  @override
  bool get hasSnapshotFileApi => _host.hasSnapshotFileApi;
  @override
  bool get canUseIncrementalScan =>
      treatAsIndexApiForTest || _host.canUseIncrementalScan;
  ScanRootRecordStore get _rootRecordStore => _host.rootRecordStore;
  ScanEnginePort get _scanEngine => _host.scanEngine;
  IndexEnginePort get _indexEngine => _host.indexEngine;

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

  Stream<ScanSessionNotificationKind> get notifications =>
      _notificationController.stream;

  void _notifyListeners() {
    notifyListeners();
    if (!_notificationController.isClosed) {
      _notificationController.add(ScanSessionNotificationKind.batched);
    }
  }

  void _notifyImmediately() {
    notifyListeners();
    if (!_notificationController.isClosed) {
      _notificationController.add(ScanSessionNotificationKind.immediate);
    }
  }

  bool get _persistenceEnabled =>
      _persistSessionStateEnabled || _host.persistSessionStateEnabled;

  String _defaultScanRoot() {
    return defaultScanRootPath(
      environment: Platform.environment,
      isWindows: () => Platform.isWindows,
    );
  }

  String _preferredRestoreRoot() {
    return _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot();
  }

  void _invalidateCapabilityCacheFor(String? snapshotId) =>
      _host.invalidateCapabilityCache(snapshotId);

  @override
  Future<void> loadSessionStateIfNeeded() =>
      _persistence.loadIfNeeded(_loadSessionState);

  Future<void> _loadSessionState() async {
    final generation = _rootSwitchGeneration;
    if (_scanRoots.isNotEmpty) return;
    try {
      final map = await _persistence.load();
      if (map == null) return;
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
      // Session state is a cache hint only.
    }
  }

  Future<void> _persistSessionState() async {
    if (!_persistenceEnabled) return;
    try {
      await _persistence.persist(<String, dynamic>{
        'scan_roots': _scanRoots,
        if (recentCustomRoots.isNotEmpty) ...{
          'last_custom_root': recentCustomRoots.first,
          'last_custom_roots': recentCustomRoots,
        },
      });
    } catch (e, st) {
      debugPrint('ScanSession: persist session state failed: $e\n$st');
    }
  }

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
    _recentCustomRoots = <String>[
      normalized,
      for (final root in _recentCustomRoots)
        if (root != normalized) root,
    ].take(_maxRecentCustomRoots).toList();
    _lastCustomRoot = normalized;
    unawaited(_persistSessionState());
  }

  void _cancelPendingForcedPeeks() {
    final pending = _pendingForcedPeeks.values.toList(growable: false);
    _pendingForcedPeeks.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.complete();
    }
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
      _scanPauseRequested ||
      _scanRunningOnMainEngine ||
      !_scanChannelsClosed ||
      scanRunnerForTest != null;

  void _clearScanTransientState() {
    _closeScanChannels();
    _scanPreparing = false;
    _scanProgress = null;
    _lastJobId = null;
    _activeScanRunId = null;
    _workerCancelPort = null;
    _activeScanCompleter = null;
    _scanRunningOnMainEngine = false;
    _scanCancelRequested = false;
    _scanPauseRequested = false;
    _lastScanActivityAt = null;
    _savingPhaseStartedAt = null;
    _lastNativeProgressNotifyAt = null;
    _lastNativeProgressPhase = null;
    _lastApplyMergeNotify = null;
    scanRunnerForTest = null;
  }

  void _finalizeScanTransientState() {
    if (!_hasScanTransientState) return;
    _transientFinalizeCount++;
    _clearScanTransientState();
    _stopScanElapsedTimer();
    _publishScanProgress();
  }

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

  double? get _scannedFraction => estimateScanFraction(
    scanning: _scanning,
    phase: _scanProgress?['phase']?.toString() ?? 'DiscoveringRoots',
    scanStartedAt: _scanStartedAt,
    now: DateTime.now(),
  );

  String? get _scanElapsedLabel {
    if (!_scanning || _scanStartedAt == null) return null;
    final elapsed = DateTime.now().difference(_scanStartedAt!);
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    return minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
  }

  void _publishScanProgress() {
    final fraction = _scannedFraction;
    if (scannedFractionNotifier.value != fraction) {
      scannedFractionNotifier.value = fraction;
    }
    final phase = _scanning ? (_scanProgress?['phase']?.toString()) : null;
    final next = ScanProgressViewState(phase: phase, fraction: fraction);
    if (scanProgressNotifier.value != next) {
      scanProgressNotifier.value = next;
    }
  }

  void _startScanElapsedTimer() {
    _scanStartedAt = DateTime.now();
    scanElapsedNotifier.value = _scanElapsedLabel;
    _publishScanProgress();
    _scanElapsedTimer?.cancel();
    _scanElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_scanning) {
        scanElapsedNotifier.value = _scanElapsedLabel;
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
        // Best-effort worker temp cleanup.
      }
    }());
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
      'ScanSession: $source memory snapshot '
      'root=$rootPath snapshotId=${snapshot.snapshotId} rss=${rssMb}MB '
      'scan_phase=$scanPhase paths_seen=${pathsSeen ?? '-'} '
      'dirs_seen=${dirsSeen ?? '-'} files_seen=${filesSeen ?? '-'} '
      'files_in_snapshot=$filesInSnapshot paths_skipped=${pathsSkipped ?? '-'} '
      'truncated=${truncated ?? '-'} incomplete_reason=${incompleteReason ?? '-'} '
      'entryCount=${snapshot.entryCount} treeBytes=$treeBytes '
      'reclaimable=${snapshot.reclaimableEstimateBytes}',
    );
  }

  Future<ScanSnapshotState?> _loadSnapshotFromFile(String path) async {
    final pathsSeen = (_scanProgress?['paths_seen'] as num?)?.toInt();
    _setScanProgressPhase('LoadingResults', pathsSeen: pathsSeen);
    if (!_ready) throw StateError('Native engine not ready');
    final decoder = snapshotFileDecoder;
    final snap = await Isolate.run(() => decoder(path));
    try {
      await File(path).delete();
    } catch (_) {}
    if (snap == null) throw StateError('Invalid snapshot file');
    if (!_indexEngine.setLastSnapshot(snap)) {
      throw StateError('Failed to load scan snapshot into engine');
    }
    _invalidateCapabilityCacheFor(snap['snapshot_id']?.toString());
    return ScanSnapshotState.fromWire(snap);
  }

  Future<void> _applyCheckpointFromFile(
    String path,
    int expectedGeneration,
  ) async {
    try {
      final decoder = snapshotFileDecoder;
      final checkpoint = await Isolate.run(() => decoder(path));
      try {
        await File(path).delete();
      } catch (_) {}
      if (checkpoint == null) return;
      final tree = checkpoint['tree'];
      if (tree is! Map) return;
      final rootPath = tree['path']?.toString();
      if (rootPath == null || rootPath.isEmpty) return;
      final entries = checkpoint['entries'] is List
          ? (checkpoint['entries'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];
      if (expectedGeneration != _rootSwitchGeneration) return;
      await _applyMerge(rootPath, Map<String, dynamic>.from(tree), entries);
    } catch (e, st) {
      if (e is! PathNotFoundException && e is! FormatException) {
        debugPrint('ScanSession: apply checkpoint failed: $e\n$st');
      }
    }
  }

  Future<ScanSnapshotState?> _runIndexScanOnMainEngine(
    String jobId,
    List<String> roots, {
    required bool incremental,
  }) async {
    if (!_ready) throw StateError('Native engine not ready');
    if (!_scanning || _scanCancelRequested) {
      throw ScanCancelledException();
    }
    final startResult = _scanEngine.startScanAsyncWithOptions(
      jobId,
      roots,
      incremental: incremental,
    );
    if (startResult.startsWith('error:')) {
      throw StateError(startResult);
    }
    _scanRunningOnMainEngine = true;
    _scanPreparing = false;
    _touchScanActivity(phase: 'Walking');
    _notifyListeners();
    while (_scanEngine.isScanRunning()) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (_scanPauseRequested) {
        final stopped = await _waitForNativeScanToStop();
        if (!stopped) continue;
        throw ScanCancelledException();
      }
      if (!_scanning || _scanCancelRequested) {
        _scanEngine.cancelScan();
        await _waitForNativeScanToStop();
        throw ScanCancelledException();
      }
      final progress = _scanEngine.getLastProgress();
      if (progress != null) {
        final phase = progress['phase']?.toString();
        _touchScanActivity(phase: phase);
        _scanProgress = progress;
        _publishScanProgress();
        _notifyNativeProgressIfNeeded(phase);
      }
    }
    if (_scanPauseRequested || _scanCancelRequested || !_scanning) {
      throw ScanCancelledException();
    }
    final progress = _scanEngine.getLastProgress();
    final pathsSeen = (progress?['paths_seen'] as num?)?.toInt();
    _setScanProgressPhase('Done', pathsSeen: pathsSeen);
    _touchScanActivity(phase: 'LoadingResults');
    final summary = _indexEngine.getIndexSummaryJson();
    if (summary == null || summary.containsKey('error')) {
      throw StateError(
        summary?['error']?.toString() ?? 'Failed to load catalog index',
      );
    }
    return ScanSnapshotState.fromIndexSummary(summary);
  }

  Future<bool> _waitForNativeScanToStop() =>
      _waitUntilNativeScanStops(_scanEngine.isScanRunning);

  Future<bool> _waitUntilNativeScanStops(bool Function() isRunning) async {
    final timeout = nativeScanStopTimeoutForTest ?? _nativeScanStopTimeout;
    final startedAt = DateTime.now();
    while (isRunning()) {
      if (DateTime.now().difference(startedAt) >= timeout) return false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return true;
  }

  @visibleForTesting
  Future<bool> waitForNativeScanToStopForTest(bool Function() isRunning) =>
      _waitUntilNativeScanStops(isRunning);

  Future<bool> _applyMerge(
    String targetPath,
    Map<String, dynamic> subtreeTree,
    List<Map<String, dynamic>> subtreeEntries, {
    bool authoritative = false,
  }) async {
    final current = _lastSnapshot;
    if (current == null) return false;
    final merged = mergeSubtreeIntoSnapshotState(
      snapshot: current,
      targetPath: targetPath,
      subtreeTree: subtreeTree,
      subtreeEntries: subtreeEntries,
      replacementIsAuthoritative: authoritative,
    );
    _lastSnapshot = merged;
    await _host.commitMergedSnapshot(
      snapshot: merged,
      targetPath: targetPath,
      subtreeTree: subtreeTree,
      subtreeEntries: subtreeEntries,
      authoritative: authoritative,
    );
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

  ScanSnapshotState? get lastSnapshot => _lastSnapshot;
  String? get lastJobId => _lastJobId;
  Map<String, dynamic>? get scanProgress => _scanProgress;
  @override
  bool get scanning => _scanning;
  List<String> get scanRoots => List.unmodifiable(_scanRoots);
  @override
  bool get hasAuthoritativeSnapshotForCurrentRoot => _hasAuthoritativeSnapshot;
  @override
  int get rootSwitchGeneration => _rootSwitchGeneration;
  @override
  bool get incrementalScan => _incrementalScan;
  bool get restoringSnapshot => _restoringSnapshot;
  bool get targetPreviewLoading => _targetPreviewLoading;
  String get scanTargetLabel =>
      _scanRoots.isEmpty ? 'Home (default)' : _scanRoots.join(', ');
  String? get scanElapsedLabel => _scanElapsedLabel;
  double? get scannedFraction => _scannedFraction;
  Set<String> get peekInFlight => Set.unmodifiable(_peekInFlight);
  int get transientFinalizeCount => _transientFinalizeCount;
  String get currentRoot =>
      scanRoots.isEmpty ? _defaultScanRoot() : scanRoots.first;

  @visibleForTesting
  void setScanRootsForTest(List<String> roots) {
    _scanRoots = List<String>.from(roots);
  }

  @visibleForTesting
  void setLastSnapshotForTest(ScanSnapshotState snapshot) {
    _lastSnapshot = snapshot;
  }

  @visibleForTesting
  void setSnapshotForTest(ScanSnapshotState snapshot) {
    _lastSnapshot = snapshot;
    _invalidateCapabilityCacheFor(snapshot.snapshotId);
    unawaited(
      _host.commitMergedSnapshot(
        snapshot: snapshot,
        targetPath: snapshot.tree?.path ?? '',
        subtreeTree: const {},
        subtreeEntries: const [],
        authoritative: true,
      ),
    );
    _notifyListeners();
  }

  @visibleForTesting
  void primeTransientScanStateForTest({
    Map<String, dynamic>? progress,
    bool scanning = true,
    bool preparing = false,
    bool openScanPorts = true,
    String? lastJobId,
  }) {
    _scanProgress = progress == null
        ? null
        : Map<String, dynamic>.from(progress);
    _scanning = scanning;
    _scanPreparing = preparing;
    _activeScanRunId = scanning ? ++_nextScanRunId : null;
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
    unawaited(
      _host.commitMergedSnapshot(
        snapshot: snapshot,
        targetPath: affectedPrefix,
        subtreeTree: const {},
        subtreeEntries: const [],
        authoritative: true,
      ),
    );
    _notifyListeners();
  }

  @visibleForTesting
  void clearTransientScanStateForTest() {
    _scanning = false;
    _finalizeScanTransientState();
  }

  void clearTransientState() {
    _scanning = false;
    _finalizeScanTransientState();
  }

  @visibleForTesting
  Future<bool> applyMergeForTest(
    String targetPath,
    Map<String, dynamic> subtreeTree,
    List<Map<String, dynamic>> subtreeEntries, {
    bool authoritative = false,
  }) => _applyMerge(
    targetPath,
    subtreeTree,
    subtreeEntries,
    authoritative: authoritative,
  );

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
      _scanPauseRequested ||
      _scanRunningOnMainEngine ||
      !_scanChannelsClosed ||
      scanRunnerForTest != null;

  @visibleForTesting
  Future<void> switchRootForTest(String path) => switchRoot(path);

  Future<void> switchRoot(String path, {bool incremental = false}) async {
    _incrementalScan = incremental;
    await _switchScanRoot(path);
  }

  @override
  Future<void> switchScanRoot(
    String? path, {
    bool validateBeforeSwitch = false,
  }) => _switchScanRoot(path, validateBeforeSwitch: validateBeforeSwitch);

  @override
  Future<String> resolveStartupRoot() => _resolveStartupRoot();

  @override
  Future<void> restoreCachedSnapshotIfNeeded() =>
      _restoreCachedSnapshotIfNeeded();

  @visibleForTesting
  Future<bool> restoreCachedSnapshotForTest({String? preferredPath}) =>
      _restoreCachedSnapshot(preferredPath: preferredPath);

  @override
  void setScanRoots(List<String> roots) {
    _scanRoots = roots
        .map(ScanTreeBuilder.normalizeRoot)
        .toList(growable: false);
    _host.resetBrowseStateForRootChange();
    unawaited(_persistSessionState());
    _notifyListeners();
  }

  void clearScanRoots() {
    _scanRoots = [];
    _host.resetBrowseStateForRootChange();
    unawaited(_persistSessionState());
    _notifyListeners();
  }

  @override
  void setIncrementalScan(bool incremental) {
    if (incremental && !canUseIncrementalScan) return;
    if (_incrementalScan == incremental) return;
    _incrementalScan = incremental;
    _notifyListeners();
  }

  Future<String> startScan({ScanRunMode mode = ScanRunMode.auto}) =>
      runScan(mode: mode);

  @override
  Future<String> runScan({ScanRunMode mode = ScanRunMode.auto}) =>
      _runScan(mode: mode);

  Future<bool> pauseCurrentScanForSwitch() => _pauseCurrentScanForSwitch();

  @override
  void cancelScan() => _cancelScan();

  @override
  Future<void> validateScanRoot(String path) => _validateScanRoot(path);

  @override
  Future<void> previewTarget({int? expectedGeneration}) =>
      _previewTarget(expectedGeneration: expectedGeneration);

  Future<String> _resolveStartupRoot() async {
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

  Future<void> _validateScanRoot(String path) async {
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

  /// Runs a small, scoped scan without replacing the full engine index.
  Future<bool> peekScan(String path, {bool force = false}) async {
    if (!_ready) return false;
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
        cancel: () => cancelPort?.send(null),
      );
      if (message is! Map) return false;
      final type = message['type']?.toString();
      if (type == 'done') {
        if (generation != _rootSwitchGeneration) return false;
        final tree = message['tree'];
        final entriesRaw = message['entries'];
        if (tree is Map) {
          final entries = entriesRaw is List
              ? entriesRaw
                    .whereType<Map>()
                    .map((entry) => Map<String, dynamic>.from(entry))
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
          'ScanSession: peekScan($normalizedPath) failed: ${message['error']}',
        );
      }
    } catch (e, st) {
      debugPrint('ScanSession: peekScan($normalizedPath) error: $e\n$st');
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

  Future<void> _restoreCachedSnapshotIfNeeded() async {
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

  Future<bool> _restoreCachedSnapshot({String? preferredPath}) async {
    if (!_ready || _scanning) return false;
    _lastError = null;
    _restoringSnapshot = true;
    _notifyImmediately();
    var restoredSnapshot = false;
    try {
      await loadSessionStateIfNeeded();
      final generation = ++_cacheRestoreGeneration;

      final preferredRoot = _preferredRestoreRoot();
      final path =
          preferredPath ??
          await SnapshotCache.latestSnapshotPath(preferredRoot: preferredRoot);
      if (path == null) return false;
      if (generation != _cacheRestoreGeneration) return false;
      if (ScanTreeBuilder.normalizeRoot(_preferredRestoreRoot()) !=
          ScanTreeBuilder.normalizeRoot(preferredRoot)) {
        return false;
      }

      ScanSnapshotState? restored;
      var indexRestoreAttempted = false;
      if (hasIndexApi) {
        // Always try the Rust catalog loader before applying the Dart JSON
        // size guard. New dylibs do the load on a Rust worker thread so large
        // legacy snapshots do not block Flutter's main isolate.
        indexRestoreAttempted = true;
        restored = await _restoreIndexCache(path, generation);
        if (generation != _cacheRestoreGeneration) {
          return false;
        }
      }
      if (restored == null) {
        final cacheFile = File(path);
        try {
          final size = await cacheFile.length();
          if (indexRestoreAttempted && size > _maxAutoRestoreBytes) {
            // Async index load already failed; do not mislabel as too-large.
            _lastError ??= 'scan-cache-unreadable';
            return false;
          }
          if (size > _maxAutoRestoreBytes) {
            _lastError = 'scan-cache-too-large';
            debugPrint(
              'VolwardSession: skip Dart snapshot restore for oversized cache '
              '$path (${size ~/ (1024 * 1024)} MB)',
            );
            return false;
          }
        } catch (_) {
          return false;
        }
        final decoder = snapshotFileDecoder;
        final snap = await Isolate.run(() => decoder(path));
        restored = snap == null ? null : ScanSnapshotState.fromWire(snap);
      }
      if (restored == null) return false;
      final restoredRoot = restored.tree?.path;
      if (restoredRoot == null ||
          ScanTreeBuilder.normalizeRoot(restoredRoot) !=
              ScanTreeBuilder.normalizeRoot(_preferredRestoreRoot())) {
        return false;
      }
      restoreDelayStartedForTest?.call();
      await Future<void>.delayed(restoreDelayForTest ?? Duration.zero);
      if (generation != _cacheRestoreGeneration) return false;
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

  Future<bool> _restorePausedCheckpoint(String root) async {
    final record = await _rootRecordStore.load(root);
    final path = record?.checkpointPath;
    if (record?.status != ScanRootStatus.paused ||
        path == null ||
        path.isEmpty ||
        !await File(path).exists()) {
      return false;
    }
    return _restoreCachedSnapshot(preferredPath: path);
  }

  ScanSnapshotState? _snapshotFromLoadedEngineIndex(String preferredRoot) {
    final injected = engineIndexSnapshotForTest;
    if (injected != null) {
      final treePath = injected.tree?.path;
      if (treePath != null &&
          indexSummaryMatchesRoot({'root_path': treePath}, preferredRoot)) {
        return injected;
      }
      return null;
    }
    if (treatAsIndexApiForTest) return null;
    final summary = _indexEngine.getIndexSummaryJson();
    if (!indexSummaryMatchesRoot(summary, preferredRoot)) {
      return null;
    }
    return ScanSnapshotState.fromIndexSummary(summary!);
  }

  String? _startTestIndexLoad(String path) {
    final scripted = indexLoadAsyncResultsForTest;
    if (scripted == null || startIndexLoadCallsForTest >= scripted.length) {
      return 'error:test index load script exhausted';
    }
    final result = scripted[startIndexLoadCallsForTest];
    startIndexLoadCallsForTest++;
    return result;
  }

  Future<ScanSnapshotState?> _restoreIndexCache(
    String path,
    int generation,
  ) async {
    if (generation != _cacheRestoreGeneration) return null;

    final preferredRoot = _preferredRestoreRoot();
    final reused = _snapshotFromLoadedEngineIndex(preferredRoot);
    if (reused != null) {
      debugPrint('VolwardSession: reused in-memory index for $preferredRoot');
      return reused;
    }

    final cacheSize = await _fileSizeOrNull(path);
    final timeout =
        cacheRestoreTimeoutForTest ?? cacheRestoreTimeoutForByteSize(cacheSize);

    if (treatAsIndexApiForTest) {
      final scripted = indexLoadAsyncResultsForTest;
      if (scripted != null) {
        final startedAt = DateTime.now();
        Duration remainingTimeout() {
          final elapsed = DateTime.now().difference(startedAt);
          final left = timeout - elapsed;
          return left.isNegative ? Duration.zero : left;
        }

        while (generation == _cacheRestoreGeneration) {
          if (remainingTimeout() <= Duration.zero) {
            debugPrint(
              'VolwardSession: cache restore timed out after '
              '${timeout.inSeconds}s for $path',
            );
            _lastError = 'scan-cache-restore-timeout';
            return null;
          }

          final loading = isIndexLoadingForTest?.call() ?? false;
          if (loading) {
            final drained = await _waitForIndexLoadDrain(
              generation,
              timeout: remainingTimeout(),
            );
            if (!drained) {
              if (generation != _cacheRestoreGeneration) return null;
              continue;
            }
            final loaded = _snapshotFromLoadedEngineIndex(preferredRoot);
            if (loaded != null) return loaded;
            continue;
          }

          final started = _startTestIndexLoad(path);
          if (started == null || started.startsWith('error:')) {
            _lastError = 'scan-cache-unreadable';
            return null;
          }
          if (started.startsWith('busy:')) {
            await _waitForIndexLoadDrain(
              generation,
              timeout: remainingTimeout(),
            );
            continue;
          }

          final drained = await _waitForIndexLoadDrain(
            generation,
            timeout: remainingTimeout(),
          );
          if (!drained) {
            if (generation != _cacheRestoreGeneration) return null;
            continue;
          }
          break;
        }
        if (generation != _cacheRestoreGeneration) return null;
      }
      return _snapshotFromLoadedEngineIndex(preferredRoot);
    }

    if (_indexEngine.hasAsyncIndexLoadApi) {
      final startedAt = DateTime.now();
      Duration remainingTimeout() {
        final elapsed = DateTime.now().difference(startedAt);
        final left = timeout - elapsed;
        return left.isNegative ? Duration.zero : left;
      }

      while (generation == _cacheRestoreGeneration) {
        if (remainingTimeout() <= Duration.zero) {
          _indexEngine.invalidateIndexLoad();
          debugPrint(
            'VolwardSession: cache restore timed out after '
            '${timeout.inSeconds}s for $path',
          );
          _lastError = 'scan-cache-restore-timeout';
          return null;
        }

        if (_indexEngine.isIndexLoading()) {
          final drained = await _waitForIndexLoadDrain(
            generation,
            timeout: remainingTimeout(),
          );
          if (!drained) {
            if (generation != _cacheRestoreGeneration) return null;
            continue;
          }
          final loaded = _snapshotFromLoadedEngineIndex(preferredRoot);
          if (loaded != null) return loaded;
          continue;
        }

        final started = _indexEngine.startLoadIndexFromPathAsync(path);
        if (started == null || started.startsWith('error:')) {
          debugPrint(
            'VolwardSession: async index restore failed to start: $started',
          );
          _lastError = 'scan-cache-unreadable';
          return null;
        }
        if (started.startsWith('busy:')) {
          await _waitForIndexLoadDrain(generation, timeout: remainingTimeout());
          continue;
        }

        final drained = await _waitForIndexLoadDrain(
          generation,
          timeout: remainingTimeout(),
        );
        if (!drained) {
          if (generation != _cacheRestoreGeneration) return null;
          continue;
        }
        break;
      }
      if (generation != _cacheRestoreGeneration) return null;

      final error = _indexEngine.getLastIndexLoadError();
      if (error != null && error.isNotEmpty) {
        debugPrint('VolwardSession: async index restore failed: $error');
        _lastError = 'scan-cache-unreadable';
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
      final loaded = _indexEngine.loadIndexFromPath(path);
      if (!loaded) {
        _lastError = 'scan-cache-unreadable';
        return null;
      }
    }

    return _snapshotFromLoadedEngineIndex(preferredRoot);
  }

  Future<int?> _fileSizeOrNull(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _waitForIndexLoadDrain(
    int generation, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (treatAsIndexApiForTest) {
      final startedAt = DateTime.now();
      while (generation == _cacheRestoreGeneration) {
        final loading = isIndexLoadingForTest?.call() ?? false;
        if (!loading) break;
        if (DateTime.now().difference(startedAt) > timeout) {
          return false;
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      return generation == _cacheRestoreGeneration;
    }

    if (!_indexEngine.hasAsyncIndexLoadApi) return true;
    final startedAt = DateTime.now();
    while (generation == _cacheRestoreGeneration) {
      if (!_indexEngine.isIndexLoading()) break;
      if (DateTime.now().difference(startedAt) > timeout) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return generation == _cacheRestoreGeneration;
  }

  void _invalidateCacheRestore() {
    _cacheRestoreGeneration++;
    if (!treatAsIndexApiForTest && hasIndexApi) {
      _indexEngine.invalidateIndexLoad();
    }
  }

  Future<ScanRootStatus> _statusFor(
    String root, {
    bool considerActiveScan = true,
  }) async {
    final normalized = ScanTreeBuilder.normalizeRoot(root);
    final record = await _rootRecordStore.load(normalized);
    final completedPath = await SnapshotCache.latestSnapshotPath(
      preferredRoot: normalized,
    );
    return ScanRootRecordStore.inferredStatus(
      root: normalized,
      isCurrentAndScanning:
          considerActiveScan &&
          _scanning &&
          _scanRoots.isNotEmpty &&
          ScanTreeBuilder.normalizeRoot(_scanRoots.first) == normalized,
      record: record,
      hasCompletedSnapshot: completedPath != null,
    );
  }

  Future<void> _clearPauseArtifacts(
    String root, [
    ScanRootRecord? existing,
  ]) async {
    final record = existing ?? await _rootRecordStore.load(root);
    final checkpointPath = record?.checkpointPath;
    if (checkpointPath != null && checkpointPath.isNotEmpty) {
      for (final path in [
        checkpointPath,
        checkpointPath.replaceFirst('.index.json', '.manifest.json'),
      ]) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Best effort: Rust also clears pause files after a completed scan.
        }
      }
    }
  }

  Future<bool> _pauseCurrentScanForSwitch() async {
    if (!_scanning) return true;
    if (_scanPreparing) {
      _scanPreparing = false;
      _scanning = false;
      _activeScanRunId = null;
      _stopScanElapsedTimer();
      _scanProgress = null;
      _publishScanProgress();
      return true;
    }
    final root = ScanTreeBuilder.normalizeRoot(
      _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot(),
    );
    final hook = pauseCurrentScanForTest;
    if (hook != null) {
      final paused = await hook();
      if (!paused) {
        _lastError = 'scan-pause-failed';
        _notifyListeners();
        return false;
      }
      if (!await _waitForScanIdle()) {
        _scanPauseRequested = false;
        _lastError = 'scan-pause-failed';
        _notifyListeners();
        return false;
      }
      return true;
    }

    final pauseRequest = pauseRequestForTest;
    if (pauseRequest == null && !_scanRunningOnMainEngine) {
      _lastError = 'scan-pause-failed';
      _notifyListeners();
      return false;
    }
    _scanPauseRequested = true;
    final cacheDir = SnapshotCache.cacheDir().path;
    final checkpointPath =
        pauseRequest?.call(root, cacheDir) ??
        _scanEngine.requestScanPause(root, cacheDir);
    if (checkpointPath.startsWith('error:')) {
      _scanPauseRequested = false;
      _lastError = 'scan-pause-failed';
      _notifyListeners();
      return false;
    }

    final activeScanStartedAt = _scanStartedAt;
    final activeScanRunId = _activeScanRunId;
    if (!await _waitForScanIdle()) {
      _scanPauseRequested = false;
      _lastError = 'scan-pause-failed';
      _notifyListeners();
      return false;
    }
    final completedPath = await SnapshotCache.latestSnapshotPath(
      preferredRoot: root,
    );
    if ((activeScanRunId != null &&
            _completedScanRunId == activeScanRunId &&
            _hasAuthoritativeSnapshot) ||
        await _isFreshCompletedSnapshot(completedPath, activeScanStartedAt)) {
      final saved = await _saveRootRecord(
        ScanRootRecord(
          root: root,
          status: ScanRootStatus.completed,
          snapshotId: _lastSnapshot?.snapshotId ?? '',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (!saved) return false;
      await _clearPauseArtifacts(root);
      return true;
    }
    final pauseError =
        pauseErrorForTest?.call() ??
        (_scanRunningOnMainEngine ? _scanEngine.getLastPauseError() : null);
    if (pauseError != null && pauseError.isNotEmpty) {
      _lastError = 'scan-pause-failed';
      _notifyListeners();
      return false;
    }
    if (!await File(checkpointPath).exists()) {
      _lastError = 'scan-pause-failed';
      _notifyListeners();
      return false;
    }
    final record = ScanRootRecord(
      root: root,
      status: ScanRootStatus.paused,
      snapshotId: _lastSnapshot?.snapshotId ?? '',
      checkpointPath: checkpointPath,
      jobId: _lastJobId,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (!await _saveRootRecord(record)) return false;
    final saved = await _rootRecordStore.load(root);
    if (saved?.status != ScanRootStatus.paused ||
        saved?.checkpointPath != checkpointPath) {
      _lastError = 'scan-pause-failed';
      _notifyListeners();
      return false;
    }
    return true;
  }

  Future<bool> _isFreshCompletedSnapshot(
    String? path,
    DateTime? scanStartedAt,
  ) async {
    if (path == null) return false;
    if (scanStartedAt == null) return false;
    try {
      return !(await File(path).lastModified()).isBefore(scanStartedAt);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _saveRootRecord(ScanRootRecord record) async {
    try {
      await _rootRecordStore.save(record);
      return true;
    } catch (e, st) {
      _lastError = 'scan-pause-failed';
      debugPrint('ScanSession: save scan root record failed: $e\n$st');
      _notifyListeners();
      return false;
    }
  }

  /// Switches to [path], restoring, resuming, or scanning from its cache state.
  Future<void> _switchScanRoot(
    String? path, {
    bool validateBeforeSwitch = false,
  }) async {
    final requestGeneration = ++_rootSwitchRequestGeneration;
    final newRoot = ScanTreeBuilder.normalizeRoot(path ?? _defaultScanRoot());
    final newRoots = path != null ? [newRoot] : <String>[];
    if (validateBeforeSwitch && path != null) {
      try {
        await _validateScanRoot(newRoot);
        await _readTargetPreview(newRoot, throwOnFailure: true);
      } catch (_) {
        if (requestGeneration != _rootSwitchRequestGeneration) return;
        rethrow;
      }
      if (requestGeneration != _rootSwitchRequestGeneration) return;
    }

    final currentRoot = ScanTreeBuilder.normalizeRoot(
      _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot(),
    );
    final keepRunningScan = _scanning && newRoot == currentRoot;
    if (_scanning && !keepRunningScan) {
      final paused = await pauseCurrentScanForSwitch();
      if (!paused) return;
      if (requestGeneration != _rootSwitchRequestGeneration) return;
    }

    // User-selected scan root (folder picker / root switch). Skip null clears and
    // launch-time [setScanRoots] so startup restore is not counted.
    if (path != null) {
      _host.trackScanRootSelected(newRoot);
    }

    if (keepRunningScan) {
      final generation = _rootSwitchGeneration;
      unawaited(() async {
        await _host.previewTargetFromHost(expectedGeneration: generation);
        if (generation != _rootSwitchGeneration) return;
        unawaited(_host.peekScanFromHost(newRoot, force: true));
      }());
      return;
    }

    final generation = ++_rootSwitchGeneration;
    _invalidateCacheRestore();

    _scanRoots = newRoots;
    _lastSnapshot = null;
    _host.resetBrowseStateForRootChange();
    _host.clearDeletionState();
    _targetPreviewLoading = true;
    _targetPreviewStartedAt = DateTime.now();
    _peekInFlight.clear();
    _peekCompleted.clear();
    _cancelPendingForcedPeeks();
    await _persistSessionState();
    _notifyListeners();

    unawaited(_continueRootSwitch(generation, newRoot));
  }

  Future<void> _continueRootSwitch(int generation, String newRoot) async {
    final status = await _statusFor(newRoot);
    if (generation != _rootSwitchGeneration) return;
    switch (status) {
      case ScanRootStatus.completed:
        final restored = await _restoreCachedSnapshot();
        if (generation != _rootSwitchGeneration) return;
        if (!restored) {
          if (_lastError == 'scan-cache-too-large') {
            _clearTargetPreviewLoading(generation);
            return;
          }
          _lastError ??= 'scan-cache-unreadable';
          await _runScanAutostart(generation, ScanRunMode.auto);
        } else {
          _targetPreviewLoading = false;
          _targetPreviewStartedAt = null;
          _notifyListeners();
        }
        return;
      case ScanRootStatus.paused:
        final restored = await _restorePausedCheckpoint(newRoot);
        if (generation != _rootSwitchGeneration) return;
        if (!restored) {
          if (_lastError == 'scan-cache-too-large') {
            _clearTargetPreviewLoading(generation);
            return;
          }
          _lastError ??= 'scan-cache-unreadable';
          await _runScanAutostart(generation, ScanRunMode.auto);
          return;
        }
        await _runScanAutostart(generation, ScanRunMode.resume);
        return;
      case ScanRootStatus.empty:
        await _runScanAutostart(generation, ScanRunMode.auto);
        return;
      case ScanRootStatus.scanning:
        return;
    }
  }

  Future<bool> _waitForScanIdle() async {
    final timeout = nativeScanStopTimeoutForTest ?? _nativeScanStopTimeout;
    final startedAt = DateTime.now();
    while (_scanning) {
      if (DateTime.now().difference(startedAt) >= timeout) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return true;
  }

  /// Internal helper: start a scan and store the completion status without
  /// surfacing a Future to the caller (used by [switchScanRoot]).
  Future<void> _runScanAutostart(
    int generation, [
    ScanRunMode mode = ScanRunMode.auto,
  ]) async {
    if (generation != _rootSwitchGeneration) return;
    final restoreError = switch (_lastError) {
      'scan-cache-unreadable' ||
      'scan-cache-too-large' ||
      'scan-cache-restore-timeout' => _lastError,
      _ => null,
    };
    _scanStartErrorToPreserve = restoreError;
    try {
      await _host.runScanFromHost(mode: mode);
    } on ScanCancelledException {
      // Cancelled by the user or by a subsequent switchScanRoot — ignore.
    } catch (e, st) {
      debugPrint('VolwardSession: auto-started scan failed: $e\n$st');
    } finally {
      if (_scanStartErrorToPreserve == restoreError) {
        _scanStartErrorToPreserve = null;
      }
    }
  }

  /// Instantly renders the chosen target's top-level directory listing,
  /// before any deep scan starts. No-op if the native dylib doesn't support
  /// quick_list_dir yet (old build) — callers fall back to the pre-scan
  /// section in that case.
  Future<void> _previewTarget({int? expectedGeneration}) async {
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
      if (!_ready || !_scanEngine.hasQuickListApi) return null;
      return _scanEngine.quickListDir(root);
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
    _notifyImmediately();
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
    _notifyImmediately();
  }

  void _throwIfScanPreparationIsStale(
    int scanRunId,
    int generation,
    String ownerRoot,
  ) {
    final activeRoot = ScanTreeBuilder.normalizeRoot(
      _scanRoots.isNotEmpty ? _scanRoots.first : _defaultScanRoot(),
    );
    if (_activeScanRunId != scanRunId ||
        !_scanning ||
        generation != _rootSwitchGeneration ||
        activeRoot != ownerRoot) {
      throw ScanCancelledException();
    }
  }

  Future<String> _runScan({ScanRunMode mode = ScanRunMode.auto}) async {
    if (!_ready) {
      throw StateError(_initError ?? 'Native engine not ready');
    }
    if (_scanning) {
      throw StateError('A scan is already in progress');
    }
    final effectiveRoots = List<String>.unmodifiable(
      _scanRoots.isNotEmpty ? _scanRoots : [_defaultScanRoot()],
    );
    final ownerRoot = ScanTreeBuilder.normalizeRoot(effectiveRoots.first);
    final effectiveIncremental = switch (mode) {
      ScanRunMode.resume => true,
      ScanRunMode.rescan => false,
      ScanRunMode.auto => _incrementalScan,
    };

    final testRunner = scanRunnerForTest;
    if (testRunner == null && !hasSnapshotFileApi) {
      throw StateError(
        'Native library is outdated. Rebuild the Rust library for this platform, '
        'then fully restart the app.',
      );
    }
    if (testRunner == null && effectiveIncremental && !canUseIncrementalScan) {
      throw StateError(
        'Incremental scan requires an updated native library. Rebuild the Rust library '
        'for this platform, then fully restart the app.',
      );
    }

    final ownerGeneration = _rootSwitchGeneration;
    final scanRunId = ++_nextScanRunId;
    final ownerSnapshotId = _lastSnapshot?.snapshotId;
    _scanning = true;
    _scanPreparing = true;
    _activeScanRunId = scanRunId;
    _notifyListeners();
    ScanRootRecord? previousRecord;
    var previousSnapshotId = ownerSnapshotId;
    var previousStatus = ScanRootStatus.empty;
    var rescanClearStarted = false;
    try {
      previousRecord = await _rootRecordStore.load(ownerRoot);
      previousSnapshotId = previousRecord?.snapshotId ?? ownerSnapshotId;
      _throwIfScanPreparationIsStale(scanRunId, ownerGeneration, ownerRoot);
      previousStatus = await _statusFor(ownerRoot, considerActiveScan: false);
      _throwIfScanPreparationIsStale(scanRunId, ownerGeneration, ownerRoot);
      if (mode == ScanRunMode.rescan) {
        rescanClearStarted = true;
        await _rootRecordStore.clear(ownerRoot);
        _throwIfScanPreparationIsStale(scanRunId, ownerGeneration, ownerRoot);
      }
    } catch (_) {
      if (_activeScanRunId == scanRunId) {
        _scanPreparing = false;
        _scanning = false;
        _activeScanRunId = null;
        _notifyListeners();
      }
      if (rescanClearStarted) {
        await _restoreRootRecordAfterScanFailure(
          ownerRoot,
          previousRecord,
          previousStatus,
          previousSnapshotId,
        );
      }
      rethrow;
    }

    _invalidateCacheRestore();
    final scanStartedAt = DateTime.now();
    _host.trackScanStarted(root: ownerRoot, incremental: effectiveIncremental);
    var scanSucceeded = false;
    try {
      final scanGeneration = ownerGeneration;
      _targetPreviewLoading = false;
      _targetPreviewStartedAt = null;
      _lastError = _scanStartErrorToPreserve;
      _host.clearDeletionState();
      _scanProgress = null;
      _workerCancelPort = null;
      _scanChannelsClosed = false;
      _scanRunningOnMainEngine = false;
      _scanCancelRequested = false;
      _scanPauseRequested = false;
      _lastScanActivityAt = null;
      _savingPhaseStartedAt = null;
      _lastNativeProgressNotifyAt = null;
      _lastNativeProgressPhase = null;
      _peekInFlight.clear();
      _peekCompleted.clear();
      _host.resetBrowseStateForRootChange();
      _cancelPendingForcedPeeks();
      _startScanElapsedTimer();
      _setScanProgressPhase('DiscoveringRoots', pathsSeen: 0);
      final preparationWait = scanPreparationWaitForTest;
      if (preparationWait != null) {
        await preparationWait();
      } else {
        await _waitForIndexLoadDrain(
          _cacheRestoreGeneration,
          timeout: const Duration(seconds: 120),
        );
      }
      try {
        _throwIfScanPreparationIsStale(scanRunId, scanGeneration, ownerRoot);
      } on ScanCancelledException {
        if (_activeScanRunId == scanRunId) {
          _scanning = false;
          _activeScanRunId = null;
          _finalizeScanTransientState();
          _notifyListeners();
        }
        rethrow;
      }

      if (testRunner != null) {
        _scanPreparing = false;
        _notifyListeners();
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
          final snapshotId = snapshot?.snapshotId ?? 'done';
          await _recordCompletedScan(ownerRoot, snapshotId);
          _completedScanRunId = scanRunId;
          return snapshotId;
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
            _runIndexScanOnMainEngine(
              jobId,
              effectiveRoots,
              incremental: effectiveIncremental,
            ),
          );
          if (scanGeneration == _rootSwitchGeneration) {
            _lastSnapshot = snapshot;
            _invalidateCapabilityCacheFor(snapshot?.snapshotId);
            _logSnapshotMemoryState('scan-complete');
            _notifyListeners();
          }
          scanSucceeded = true;
          final snapshotId = snapshot?.snapshotId ?? 'done';
          await _recordCompletedScan(ownerRoot, snapshotId);
          _completedScanRunId = scanRunId;
          return snapshotId;
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
          if (indexPath != null && indexPath.isNotEmpty) {
            _indexEngine.loadIndexFromPath(indexPath);
          }
        } else if (type == 'done') {
          _touchScanActivity(phase: 'LoadingResults');
          _closeScanChannels();
          final indexPath = m['index_path']?.toString();
          var loadedIndex = true;
          if (indexPath != null && indexPath.isNotEmpty) {
            loadedIndex = _indexEngine.loadIndexFromPath(indexPath);
          }
          final summary = !loadedIndex
              ? null
              : _indexEngine.getIndexSummaryJson();
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
          effectiveIncremental,
        ]);
        _scanPreparing = false;
        _notifyListeners();
        final snapshot = await _awaitScanWithStallGuard(completer.future);
        if (scanGeneration == _rootSwitchGeneration) {
          _lastSnapshot = snapshot;
          _invalidateCapabilityCacheFor(snapshot?.snapshotId);
          _logSnapshotMemoryState('scan-complete');
          _notifyListeners();
        }
        scanSucceeded = true;
        final snapshotId = snapshot?.snapshotId ?? 'done';
        await _recordCompletedScan(ownerRoot, snapshotId);
        _completedScanRunId = scanRunId;
        return snapshotId;
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
    } on ScanCancelledException {
      await _restoreRootRecordAfterScanFailure(
        ownerRoot,
        previousRecord,
        previousStatus,
        previousSnapshotId,
      );
      rethrow;
    } catch (_) {
      await _restoreRootRecordAfterScanFailure(
        ownerRoot,
        previousRecord,
        previousStatus,
        previousSnapshotId,
      );
      rethrow;
    } finally {
      _host.trackScanCompleted(
        root: ownerRoot,
        elapsed: DateTime.now().difference(scanStartedAt),
        entryCount: scanSucceeded ? (_lastSnapshot?.entryCount ?? 0) : 0,
      );
    }
  }

  Future<void> _restoreRootRecordAfterScanFailure(
    String root,
    ScanRootRecord? previousRecord,
    ScanRootStatus previousStatus,
    String? previousSnapshotId,
  ) async {
    final current = await _rootRecordStore.load(root);
    final checkpointPath = current?.checkpointPath;
    if (current?.status == ScanRootStatus.paused &&
        checkpointPath != null &&
        checkpointPath.isNotEmpty &&
        await File(checkpointPath).exists()) {
      return;
    }
    if (previousRecord != null) {
      await _rootRecordStore.save(previousRecord);
    } else if (previousStatus == ScanRootStatus.empty) {
      await _rootRecordStore.clear(root);
    } else if (previousStatus == ScanRootStatus.completed) {
      await _rootRecordStore.save(
        ScanRootRecord(
          root: root,
          status: ScanRootStatus.completed,
          snapshotId: previousSnapshotId ?? '',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  }

  Future<void> _recordCompletedScan(String root, String snapshotId) async {
    final previous = await _rootRecordStore.load(root);
    await _rootRecordStore.save(
      ScanRootRecord(
        root: root,
        status: ScanRootStatus.completed,
        snapshotId: snapshotId,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _clearPauseArtifacts(root, previous);
  }

  void _cancelScan() {
    if (!_scanning) return;

    if (_scanRunningOnMainEngine) {
      _scanCancelRequested = true;
      _scanEngine.cancelScan();
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
    _notifyImmediately();
  }

  @override
  void dispose() {
    if (_scanning) {
      _cancelScan();
    } else {
      _finalizeScanTransientState();
    }
    scanElapsedNotifier.dispose();
    scannedFractionNotifier.dispose();
    scanProgressNotifier.dispose();
    unawaited(_notificationController.close());
    super.dispose();
  }
}
