import 'dart:async';
import 'dart:isolate';

import 'native_bridge.dart';

/// Isolate entry: [SendPort progressPort, List<String> roots, SendPort cancelInitPort].
///
/// Uses `Timer.periodic` (event-loop-based) so a [RawReceivePort] for cancel
/// signals from the main isolate can be serviced between timer ticks.
@pragma('vm:entry-point')
void volwardScanIsolate(List<dynamic> args) {
  final progressPort = args[0] as SendPort;
  final roots = (args[1] as List).cast<String>();
  final cancelInitPort = args[2] as SendPort; // main uses this to learn our cancel port

  final bridge = VolwardNativeBridge.open();
  final engine = bridge.createEngine();

  // Port to receive cancel signals from the main isolate.
  final cancelRecv = RawReceivePort((_) {
    bridge.cancelScan(engine);
  });
  // Tell the main isolate how to send us a cancel signal.
  cancelInitPort.send(cancelRecv.sendPort);

  try {
    progressPort.send(<String, dynamic>{
      'type': 'progress',
      'phase': 'DiscoveringRoots',
      'paths_seen': 0,
    });

    final jobId = 'job-${DateTime.now().millisecondsSinceEpoch}';

    // Non-blocking start — Rust spawns a background scan thread.
    final snapshotId = bridge.startScanAsync(engine, jobId, roots);
    if (snapshotId.startsWith('error:')) {
      progressPort.send(<String, dynamic>{'type': 'error', 'error': snapshotId});
      bridge.freeEngine(engine);
      cancelRecv.close();
      return;
    }

    // Poll every 300ms. Timer.periodic keeps the event loop alive so the
    // cancel RawReceivePort can process incoming cancel messages.
    Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (!bridge.isScanRunning(engine)) {
        timer.cancel();
        try {
          final snap = bridge.getLastSnapshot(engine);
          final entryCount =
              snap?['entries'] is List ? (snap!['entries'] as List).length : 0;
          progressPort.send(<String, dynamic>{
            'type': 'progress',
            'phase': 'Done',
            'paths_seen': entryCount,
          });
          progressPort.send(<String, dynamic>{'type': 'done', 'snapshot': snap});
        } catch (e) {
          progressPort
              .send(<String, dynamic>{'type': 'error', 'error': e.toString()});
        } finally {
          bridge.freeEngine(engine);
          cancelRecv.close(); // allows isolate to exit
        }
        return;
      }

      final progress = bridge.getLastProgress(engine);
      if (progress != null) {
        progressPort.send(<String, dynamic>{
          'type': 'progress',
          ...progress,
        });
      }
    });
  } catch (e) {
    progressPort.send(<String, dynamic>{'type': 'error', 'error': e.toString()});
    bridge.freeEngine(engine);
    cancelRecv.close();
  }
}
