import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_root_record.dart';
import 'package:volward/snapshot_cache.dart';
import 'package:volward/volward_session.dart';

import 'support/cached_snapshot.dart';

class RecordingSession extends VolwardSession {
  RecordingSession() : super.test();

  int previewCalls = 0;
  int peekCalls = 0;
  int scanCalls = 0;
  bool? lastPeekForce;
  final List<ScanRunMode> scanModes = [];

  @override
  Future<void> previewTarget({int? expectedGeneration}) async {
    previewCalls++;
  }

  @override
  Future<bool> peekScan(String path, {bool force = false}) async {
    peekCalls++;
    lastPeekForce = force;
    return true;
  }

  @override
  Future<String> runScan({ScanRunMode mode = ScanRunMode.auto}) async {
    scanCalls++;
    scanModes.add(mode);
    return 'scan-$scanCalls';
  }
}

Future<void> waitUntil(bool Function() done, {int maxTicks = 20}) async {
  for (var tick = 0; tick < maxTicks && !done(); tick++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('empty root auto-starts a full scan after switch', () async {
    final session = RecordingSession();
    await session.switchScanRoot('/empty');
    await waitUntil(() => session.scanCalls == 1);
    expect(session.scanRoots, ['/empty']);
    expect(session.scanCalls, 1);
  });

  test('completed root restores and does not scan', () async {
    final temp = await Directory.systemTemp.createTemp(
      'volward-switch-completed',
    );
    addTearDown(() {
      SnapshotCache.cacheDirForTest = null;
      temp.deleteSync(recursive: true);
    });
    SnapshotCache.cacheDirForTest = temp;
    const cachedRoot = '/Users/test/Downloads';
    writeCachedSnapshot(
      cacheDir: temp,
      manifestName: 'downloads',
      snapshotName: 'downloads',
      root: cachedRoot,
      snapshotId: 'downloads-scan',
      scannedAtMs: 1700000000200,
      sizeBytes: 512,
      reclaimableBytes: 7,
    );

    final session = RecordingSession()..setScanRoots(['/other']);
    await session.switchScanRoot(cachedRoot);
    await waitUntil(() => session.lastSnapshot?.snapshotId == 'downloads-scan');
    expect(session.scanCalls, 0);
  });

  test('same running root keeps its scan and forces a peek', () async {
    final session = RecordingSession()
      ..setScanRoots(['/active'])
      ..primeTransientScanStateForTest(scanning: true, openScanPorts: false);

    await session.switchScanRoot('/active');
    await waitUntil(() => session.previewCalls == 1 && session.peekCalls == 1);

    expect(session.previewCalls, 1);
    expect(session.peekCalls, 1);
    expect(session.lastPeekForce, isTrue);
    expect(session.scanCalls, 0);
  });

  test('validated switch preserves the current root on failure', () async {
    final session = RecordingSession()
      ..setScanRoots(['/existing'])
      ..rootExistsForTest = ((path) => path != '/blocked');

    await expectLater(
      session.switchScanRoot('/blocked', validateBeforeSwitch: true),
      throwsA(isA<FileSystemException>()),
    );

    expect(session.scanRoots, ['/existing']);
    expect(session.previewCalls, 0);
    expect(session.scanCalls, 0);
  });

  test('preview failure happens before the current root is mutated', () async {
    final session = RecordingSession()
      ..setScanRoots(['/existing'])
      ..rootExistsForTest = ((_) => true)
      ..scanRootPreviewReaderForTest = ((_) async {
        throw StateError('preview denied');
      });

    await expectLater(
      session.switchScanRoot('/blocked', validateBeforeSwitch: true),
      throwsStateError,
    );

    expect(session.scanRoots, ['/existing']);
    expect(session.previewCalls, 0);
    expect(session.scanCalls, 0);
  });

  test('pause failure keeps the current root', () async {
    final session = RecordingSession()
      ..setScanRoots(['/a'])
      ..primeTransientScanStateForTest(scanning: true, openScanPorts: false)
      ..pauseCurrentScanForTest = () async => false;
    await session.switchScanRoot('/b');
    expect(session.scanRoots, ['/a']);
    expect(session.lastError, isNotNull);
    expect(session.scanCalls, 0);
  });

  test('scanning root pauses then target empty auto-starts', () async {
    final session = RecordingSession()
      ..setScanRoots(['/a'])
      ..primeTransientScanStateForTest(scanning: true, openScanPorts: false)
      ..pauseCurrentScanForTest = () async => true;
    await session.switchScanRoot('/b');
    await waitUntil(() => session.scanCalls == 1);
    expect(session.scanRoots, ['/b']);
  });

  test('paused root restores its checkpoint and resumes', () async {
    final temp = await Directory.systemTemp.createTemp('volward-switch-paused');
    addTearDown(() {
      SnapshotCache.cacheDirForTest = null;
      temp.deleteSync(recursive: true);
    });
    SnapshotCache.cacheDirForTest = temp;
    const pausedRoot = '/Users/test/Paused';
    writeCachedSnapshot(
      cacheDir: temp,
      manifestName: 'checkpoint-source',
      snapshotName: 'checkpoint-source',
      root: pausedRoot,
      snapshotId: 'paused-scan',
      scannedAtMs: 1700000000300,
      sizeBytes: 256,
      reclaimableBytes: 3,
    );
    final checkpointPath = '${temp.path}/snapshots/checkpoint-source.json';
    final store = ScanRootRecordStore(temp);
    await store.save(
      ScanRootRecord(
        root: pausedRoot,
        status: ScanRootStatus.paused,
        snapshotId: 'paused-scan',
        checkpointPath: checkpointPath,
        updatedAtMs: 1700000000300,
      ),
    );

    final session = RecordingSession()
      ..rootRecordStoreForTest = store
      ..setScanRoots(['/other']);
    await session.switchScanRoot(pausedRoot);
    await waitUntil(() => session.scanCalls == 1);

    expect(session.lastSnapshot?.snapshotId, 'paused-scan');
    expect(session.scanModes, [ScanRunMode.resume]);
  });
}
