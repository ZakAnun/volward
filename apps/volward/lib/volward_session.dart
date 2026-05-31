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
  String? _lastJobId;
  Map<String, dynamic>? _lastSnapshot;

  bool get ready => _ready;
  String? get initError => _initError;
  String? get lastError => _lastError;
  Map<String, dynamic> get capabilities => _capabilities;
  bool get deepScanReady => _deepScanReady;
  bool get scanning => _scanning;
  String? get lastJobId => _lastJobId;
  Map<String, dynamic>? get lastSnapshot => _lastSnapshot;

  List<String> get permissionHints {
    final hints = _capabilities['permission_hints'];
    if (hints is List) {
      return hints.map((e) => e.toString()).toList();
    }
    return const [];
  }

  Future<void> _initialize() async {
    // Let the first frame paint before loading the dylib on the UI isolate.
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

  Future<String> runScan({List<String> roots = const []}) async {
    if (!_ready) {
      throw StateError(_initError ?? 'Native engine not ready');
    }
    _scanning = true;
    _lastError = null;
    notifyListeners();
    try {
      final jobId = 'job-${DateTime.now().millisecondsSinceEpoch}';
      _lastJobId = jobId;
      // Scan runs in a worker isolate so jwalk does not freeze the UI thread.
      _lastSnapshot = await Isolate.run(() => volwardScanWorker(roots));
      notifyListeners();
      return _lastSnapshot?['snapshot_id']?.toString() ?? 'done';
    } catch (e, st) {
      _lastError = '$e';
      debugPrint('VolwardSession scan failed: $e\n$st');
      rethrow;
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  void cancelScan() {
    if (_engine != null) {
      VolwardNativeBridge.instance.cancelScan(_engine!);
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
