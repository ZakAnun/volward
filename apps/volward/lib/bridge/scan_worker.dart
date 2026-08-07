import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'native_bridge.dart';

typedef VolwardScanBridge = VolwardNativeBridge;

VolwardScanBridge _openScanBridge() => VolwardNativeBridge.open();

Future<T> waitForPeekWorkerResult<T>(
  Future<T> resultFuture, {
  required Duration timeout,
  required void Function() cancel,
}) async {
  try {
    return await resultFuture.timeout(timeout);
  } on TimeoutException {
    cancel();
    return resultFuture;
  }
}

void stabilizePeekSnapshotEntryIds(Map<String, dynamic> snapshot) {
  final stableIdByPath = <String, String>{};
  final entries = snapshot['entries'];
  if (entries is List) {
    for (final rawEntry in entries.whereType<Map>()) {
      final path = rawEntry['path_or_uri']?.toString();
      if (path == null || path.isEmpty) continue;
      final stableId = 'path:$path';
      rawEntry['id'] = stableId;
      stableIdByPath[path] = stableId;
    }
  }

  void visit(dynamic rawNode) {
    if (rawNode is! Map) return;
    final path = rawNode['path']?.toString();
    final stableId = path == null ? null : stableIdByPath[path];
    if (stableId != null) rawNode['entry_id'] = stableId;
    final children = rawNode['children'];
    if (children is List) {
      for (final child in children) {
        visit(child);
      }
    }
  }

  visit(snapshot['tree']);
}

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
    bridge = _openScanBridge();
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

    var tickCount = 0;
    Timer.periodic(const Duration(milliseconds: 300), (timer) {
      tickCount++;
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

          progressPort.send(<String, dynamic>{
            'type': 'progress',
            'phase': 'Done',
            'paths_seen': pathsSeen?.toInt() ?? 0,
          });

          String? indexPath;
          if (bridge.hasIndexApi) {
            final idxTmpPath =
                '${Directory.systemTemp.path}/volward-$jobId.index.json';
            final result = bridge.writeLastIndexToPath(engine, idxTmpPath);
            if (result != null && !result.startsWith('error:')) {
              indexPath = idxTmpPath;
              progressPort.send(<String, dynamic>{
                'type': 'done',
                'snapshot_id': result,
                'index_path': indexPath,
              });
            } else {
              final tmpExt = bridge.hasSnapshotFilePbApi ? 'pb' : 'json';
              final tmpPath =
                  '${Directory.systemTemp.path}/volward-$jobId.$tmpExt';
              final snapshotId = _persistSnapshot(bridge, engine, tmpPath);
              if (snapshotId.startsWith('error:')) {
                progressPort.send(<String, dynamic>{
                  'type': 'error',
                  'error': snapshotId,
                });
                return;
              }
              progressPort.send(<String, dynamic>{
                'type': 'done',
                'snapshot_path': tmpPath,
                'snapshot_id': snapshotId,
              });
            }
          } else {
            final tmpExt = bridge.hasSnapshotFilePbApi ? 'pb' : 'json';
            final tmpPath =
                '${Directory.systemTemp.path}/volward-$jobId.$tmpExt';
            final snapshotId = _persistSnapshot(bridge, engine, tmpPath);
            if (snapshotId.startsWith('error:')) {
              progressPort.send(<String, dynamic>{
                'type': 'error',
                'error': snapshotId,
              });
              return;
            }
            progressPort.send(<String, dynamic>{
              'type': 'done',
              'snapshot_path': tmpPath,
              'snapshot_id': snapshotId,
            });
          }
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

      // Old builds without the catalog index API still stream checkpoints.
      if (!bridge.hasIndexApi &&
          bridge.hasCheckpointApi &&
          tickCount % 7 == 0) {
        // Prefer the protobuf variant (atomic temp+rename, smaller payload)
        // when the dylib supports it; fall back to JSON for older builds.
        final usePb = bridge.hasSnapshotFilePbApi;
        final ext = usePb ? 'pb' : 'json';
        final checkpointPath =
            '${Directory.systemTemp.path}/volward-$jobId-checkpoint.$ext';
        final checkpointId = usePb
            ? bridge.writeLastCheckpointToPathPb(engine, checkpointPath)
            : bridge.writeLastCheckpointToPath(engine, checkpointPath);
        if (checkpointId != null && !checkpointId.startsWith('error:')) {
          // The pb path uses temp+rename internally (atomic), so the file at
          // checkpointPath is always complete when the call returns.  The JSON
          // path reuses the same fixed path (File::create truncates), which
          // races a concurrent read — rename to a unique path so the reader
          // always sees a fully-written file regardless of format.
          final uniquePath =
              '${Directory.systemTemp.path}/volward-$jobId-checkpoint-$tickCount.$ext';
          try {
            File(checkpointPath).renameSync(uniquePath);
          } catch (_) {
            // Rename failed (unexpected); skip this checkpoint rather than risk
            // sending a path that may be overwritten mid-read.
            return;
          }
          progressPort.send(<String, dynamic>{
            'type': 'checkpoint',
            'snapshot_path': uniquePath,
          });
        }
      }
    });
  } catch (e, st) {
    progressPort.send(<String, dynamic>{'type': 'error', 'error': '$e\n$st'});
    bridge.freeEngine(engine);
    cancelRecv.close();
  }
}

/// Isolate entry: [SendPort resultPort, String path, SendPort cancelInitPort].
///
/// Runs a small, scoped full scan of exactly [path] using its own native
/// engine — completely independent from the main background scan's engine
/// — so it can run concurrently. Used when the user clicks a directory the
/// main background scan hasn't reached yet: because the scoped subtree is
/// usually much smaller than the whole scan root, this finishes quickly and
/// gives the effect of "priority" without reordering the main walk.
@pragma('vm:entry-point')
void volwardPeekScanIsolate(List<dynamic> args) {
  final resultPort = args[0] as SendPort;
  final path = args[1] as String;
  final cancelInitPort = args[2] as SendPort;

  if (!Directory(path).existsSync()) {
    cancelInitPort.send(null);
    resultPort.send(<String, dynamic>{
      'type': 'error',
      'error': 'error:peek directory does not exist: $path',
    });
    return;
  }

  VolwardNativeBridge bridge;
  Pointer<Void> engine;
  RawReceivePort cancelRecv;
  try {
    bridge = _openScanBridge();
    engine = bridge.createEngine();
    cancelRecv = RawReceivePort((_) {
      bridge.cancelScan(engine);
    });
  } catch (e, st) {
    cancelInitPort.send(null);
    resultPort.send(<String, dynamic>{'type': 'error', 'error': '$e\n$st'});
    return;
  }

  cancelInitPort.send(cancelRecv.sendPort);

  Timer? pollTimer;
  var finished = false;
  var snapshotAttempts = 0;
  String? cancellationError;

  void finish(Map<String, dynamic> message) {
    if (finished) return;
    finished = true;
    pollTimer?.cancel();
    resultPort.send(message);
    cancelRecv.close();
    bridge.freeEngine(engine);
  }

  try {
    final jobId = 'peek-${DateTime.now().millisecondsSinceEpoch}';
    final result = bridge.startScanAsync(engine, jobId, [path]);
    if (result.startsWith('error:')) {
      finish(<String, dynamic>{'type': 'error', 'error': result});
      return;
    }

    final waitStartedAt = DateTime.now();
    pollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      try {
        if (bridge.isScanRunning(engine)) {
          if (cancellationError == null &&
              DateTime.now().difference(waitStartedAt) >
                  const Duration(minutes: 2)) {
            cancellationError =
                'error:peek scan timed out while waiting for snapshot';
            bridge.cancelScan(engine);
          }
          return;
        }

        if (cancellationError != null) {
          finish(<String, dynamic>{
            'type': 'error',
            'error': cancellationError,
          });
          return;
        }

        final snapshot = bridge.getLastSnapshot(engine);
        if (snapshot == null) {
          snapshotAttempts++;
          if (snapshotAttempts < 5) return;
          finish(<String, dynamic>{
            'type': 'error',
            'error': 'error:peek scan produced no snapshot',
          });
          return;
        }
        stabilizePeekSnapshotEntryIds(snapshot);
        finish(<String, dynamic>{
          'type': 'done',
          'path': path,
          'tree': snapshot['tree'],
          'entries': snapshot['entries'],
        });
      } catch (e, st) {
        finish(<String, dynamic>{'type': 'error', 'error': '$e\n$st'});
      }
    });
    cancelRecv.handler = (_) {
      if (finished || cancellationError != null) return;
      cancellationError = 'error:peek scan cancelled after timeout';
      try {
        bridge.cancelScan(engine);
      } catch (e, st) {
        finish(<String, dynamic>{'type': 'error', 'error': '$e\n$st'});
      }
    };
  } catch (e, st) {
    finish(<String, dynamic>{'type': 'error', 'error': '$e\n$st'});
  }
}

/// Writes snapshot to [path]; returns snapshot_id or `error:…`.
String _persistSnapshot(
  VolwardNativeBridge bridge,
  Pointer<Void> engine,
  String path,
) {
  // Prefer protobuf (atomic temp+rename, smaller wire size) when the dylib
  // supports it.  Fall back through the JSON file API and finally to the
  // legacy in-memory round-trip for old builds.
  if (bridge.hasSnapshotFilePbApi) {
    return bridge.writeLastSnapshotToPathPb(engine, path);
  }
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
