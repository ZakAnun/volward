import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'native_bridge.dart';

/// Isolate entry:
/// [SendPort progressPort, List<String> roots, SendPort cancelInitPort, bool incremental].
///
/// Uses `Timer.periodic` (event-loop-based) so a [RawReceivePort] for cancel
/// signals from the main isolate can be serviced between timer ticks.
@pragma('vm:entry-point')
void volwardScanIsolate(List<dynamic> args) {
  final progressPort = args[0] as SendPort;
  final roots = (args[1] as List).cast<String>();
  final cancelInitPort = args[2] as SendPort;
  final incremental = args[3] as bool;

  VolwardNativeBridge bridge;
  Pointer<Void> engine;
  RawReceivePort cancelRecv;

  try {
    bridge = VolwardNativeBridge.open();
    engine = bridge.createEngine();
    cancelRecv = RawReceivePort((_) {
      bridge.cancelScan(engine);
    });
  } catch (e, st) {
    progressPort.send(<String, dynamic>{
      'type': 'error',
      'error':
          'Native bridge failed to start: $e\n$st\n'
          'Rebuild Rust: cd apps/volward/macos && bash build_rust.sh then restart the app (R).',
    });
    return;
  }

  cancelInitPort.send(cancelRecv.sendPort);

  try {
    progressPort.send(<String, dynamic>{
      'type': 'progress',
      'phase': 'DiscoveringRoots',
      'paths_seen': 0,
    });

    final jobId = 'job-${DateTime.now().millisecondsSinceEpoch}';

    if (incremental && !bridge.hasScanOptionsApi) {
      progressPort.send(<String, dynamic>{
        'type': 'error',
        'error':
            'error:incremental scan requires volward_start_scan_async_with_options — rebuild Rust',
      });
      bridge.freeEngine(engine);
      cancelRecv.close();
      return;
    }

    final startResult = bridge.hasScanOptionsApi
        ? bridge.startScanAsyncWithOptions(
            engine,
            jobId,
            roots,
            incremental: incremental,
          )
        : bridge.startScanAsync(engine, jobId, roots);
    if (startResult.startsWith('error:')) {
      progressPort.send(<String, dynamic>{
        'type': 'error',
        'error': startResult,
      });
      bridge.freeEngine(engine);
      cancelRecv.close();
      return;
    }

    Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (!bridge.isScanRunning(engine)) {
        timer.cancel();
        try {
          final progress = bridge.getLastProgress(engine);
          final pathsSeen = progress?['paths_seen'] as num?;

          progressPort.send(<String, dynamic>{
            'type': 'progress',
            'phase': 'SavingResults',
            'paths_seen': pathsSeen?.toInt() ?? 0,
          });

          final tmpPath = '${Directory.systemTemp.path}/volward-$jobId.json';
          final snapshotId = _persistSnapshot(bridge, engine, tmpPath);
          if (snapshotId.startsWith('error:')) {
            progressPort.send(<String, dynamic>{
              'type': 'error',
              'error': snapshotId,
            });
            return;
          }

          progressPort.send(<String, dynamic>{
            'type': 'progress',
            'phase': 'Done',
            'paths_seen': pathsSeen?.toInt() ?? 0,
          });
          progressPort.send(<String, dynamic>{
            'type': 'done',
            'snapshot_path': tmpPath,
            'snapshot_id': snapshotId,
          });
        } catch (e, st) {
          progressPort.send(<String, dynamic>{
            'type': 'error',
            'error': '$e\n$st',
          });
        } finally {
          bridge.freeEngine(engine);
          cancelRecv.close();
        }
        return;
      }

      final progress = bridge.getLastProgress(engine);
      if (progress != null) {
        progressPort.send(<String, dynamic>{'type': 'progress', ...progress});
      }
    });
  } catch (e, st) {
    progressPort.send(<String, dynamic>{'type': 'error', 'error': '$e\n$st'});
    bridge.freeEngine(engine);
    cancelRecv.close();
  }
}

/// Writes snapshot to [path]; returns snapshot_id or `error:…`.
String _persistSnapshot(
  VolwardNativeBridge bridge,
  Pointer<Void> engine,
  String path,
) {
  if (bridge.hasSnapshotFileApi) {
    return bridge.writeLastSnapshotToPath(engine, path);
  }

  final snap = bridge.getLastSnapshot(engine);
  if (snap == null) {
    return 'error:no snapshot';
  }
  final snapshotId = snap['snapshot_id']?.toString();
  if (snapshotId == null || snapshotId.isEmpty) {
    return 'error:missing snapshot_id';
  }
  File(path).writeAsStringSync(jsonEncode(snap));
  return snapshotId;
}
