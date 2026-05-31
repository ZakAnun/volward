import 'native_bridge.dart';

/// Top-level entry for [Isolate.run] — must not capture UI isolate state.
@pragma('vm:entry-point')
Map<String, dynamic>? volwardScanWorker(List<String> roots) {
  final bridge = VolwardNativeBridge.open();
  final engine = bridge.createEngine();
  try {
    final jobId = 'job-${DateTime.now().millisecondsSinceEpoch}';
    bridge.startScan(engine, jobId, roots);
    return bridge.getLastSnapshot(engine);
  } finally {
    bridge.freeEngine(engine);
  }
}
