import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'bridge/native_bridge.dart';
import 'bridge/scan_worker.dart';

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
  final Set<String> _selectedEntryIds = {};
  SendPort? _workerCancelPort;

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
  Set<String> get selectedEntryIds => Set.unmodifiable(_selectedEntryIds);

  String get scanTargetLabel =>
      _scanRoots.isEmpty ? 'Home (default)' : _scanRoots.join(', ');

  List<String> get permissionHints {
    final hints = _capabilities['permission_hints'];
    if (hints is List) {
      return hints.map((e) => e.toString()).toList();
    }
    return const [];
  }

  Future<void> _initialize() async {
    await Future<void>.delayed(Duration.zero);
    try {
      final bridge = VolwardNativeBridge.instance;
      _engine = bridge.createEngine();
      _capabilities = bridge.probeCapabilities(_engine!);
      _deepScanReady = bridge.isDeepScanReady(_engine!);
      _ready = true;
    } catch (e, st) {
      _initError = '$e';
      debugPrint('VolwardSession init failed: $e\n$st');
    }
    notifyListeners();
  }

  void _syncSnapshotToEngine(Map<String, dynamic>? snapshot) {
    if (!_ready || _engine == null || snapshot == null) return;
    VolwardNativeBridge.instance.setLastSnapshot(_engine!, snapshot);
  }

  void setScanRoots(List<String> roots) {
    _scanRoots = List.from(roots);
    notifyListeners();
  }

  void clearScanRoots() {
    _scanRoots = [];
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
    _scanning = true;
    _lastError = null;
    _lastDeleteReport = null;
    _scanProgress = null;
    _workerCancelPort = null;
    notifyListeners();

    final receivePort = ReceivePort();
    final cancelPort = ReceivePort(); // receives worker's cancel SendPort
    final completer = Completer<Map<String, dynamic>?>();
    late StreamSubscription<dynamic> sub;

    // Listen for progress / done / error from the worker.
    var scanFinished = false;
    sub = receivePort.listen((msg) {
      if (scanFinished) return;
      if (msg is! Map) return;
      final m = Map<String, dynamic>.from(msg);
      final type = m['type']?.toString();
      if (type == 'progress') {
        _scanProgress = Map<String, dynamic>.from(m)..remove('type');
        notifyListeners();
      } else if (type == 'done') {
        scanFinished = true;
        final snap = m['snapshot'];
        completer.complete(
          snap is Map ? Map<String, dynamic>.from(snap) : null,
        );
        sub.cancel();
        receivePort.close();
        cancelPort.close();
      } else if (type == 'error') {
        scanFinished = true;
        completer.completeError(m['error']?.toString() ?? 'Scan failed');
        sub.cancel();
        receivePort.close();
        cancelPort.close();
      }
    });

    // Receive the worker's cancel receive-port SendPort.
    cancelPort.listen((msg) {
      if (msg is SendPort) {
        _workerCancelPort = msg;
      }
    });

    try {
      final jobId = 'job-${DateTime.now().millisecondsSinceEpoch}';
      _lastJobId = jobId;
      await Isolate.spawn(volwardScanIsolate, [
        receivePort.sendPort,
        _scanRoots,
        cancelPort.sendPort,
      ]);
      _lastSnapshot = await completer.future.timeout(
        const Duration(minutes: 30),
      );
      _syncSnapshotToEngine(_lastSnapshot);
      notifyListeners();
      return _lastSnapshot?['snapshot_id']?.toString() ?? 'done';
    } catch (e, st) {
      if (!scanFinished) {
        scanFinished = true;
        sub.cancel();
        receivePort.close();
        cancelPort.close();
      }
      _lastError = '$e';
      debugPrint('VolwardSession scan failed: $e\n$st');
      rethrow;
    } finally {
      _scanning = false;
      _workerCancelPort = null;
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

  void cancelScan() {
    final cancelPort = _workerCancelPort;
    if (cancelPort != null) {
      cancelPort.send('cancel');
      _workerCancelPort = null;
    }
    _scanning = false;
    notifyListeners();
  }

  @override
  void dispose() {
    final engine = _engine;
    if (engine != null) {
      VolwardNativeBridge.instance.freeEngine(engine);
    }
    super.dispose();
  }
}
