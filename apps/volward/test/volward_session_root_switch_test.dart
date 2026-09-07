import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_root_record.dart';
import 'package:volward/scan_snapshot_state.dart';
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

class FailingSaveStore extends ScanRootRecordStore {
  FailingSaveStore(super.directory);

  @override
  Future<void> save(ScanRootRecord record) async {
    throw const FileSystemException('record directory is read-only');
  }
}

class FailingCompletedSaveStore extends ScanRootRecordStore {
  FailingCompletedSaveStore(super.directory);

  @override
  Future<void> save(ScanRootRecord record) async {
    if (record.status == ScanRootStatus.completed) {
      throw const FileSystemException('completed record save failed');
    }
    await super.save(record);
  }
}

class DelayedFirstCompletedSaveStore extends ScanRootRecordStore {
  DelayedFirstCompletedSaveStore(super.directory, {this.failFirst = false});

  final bool failFirst;
  final firstCompletedSaveStarted = Completer<void>();
  final releaseFirstCompletedSave = Completer<void>();
  var completedSaveCalls = 0;
  var _armed = false;

  void arm() {
    completedSaveCalls = 0;
    _armed = true;
  }

  @override
  Future<void> save(ScanRootRecord record) async {
    if (_armed && record.status == ScanRootStatus.completed) {
      completedSaveCalls++;
      if (completedSaveCalls == 1) {
        firstCompletedSaveStarted.complete();
        await releaseFirstCompletedSave.future;
        if (failFirst) {
          throw const FileSystemException('completed record save failed');
        }
      }
    }
    await super.save(record);
  }
}

class DelayedFirstLoadStore extends ScanRootRecordStore {
  DelayedFirstLoadStore(super.directory);

  final firstLoadStarted = Completer<void>();
  final releaseFirstLoad = Completer<void>();
  int loadCalls = 0;

  @override
  Future<ScanRootRecord?> load(String root) async {
    loadCalls++;
    if (loadCalls == 1) {
      firstLoadStarted.complete();
      await releaseFirstLoad.future;
    }
    return super.load(root);
  }
}

class ClearedThenDelayedStore extends ScanRootRecordStore {
  ClearedThenDelayedStore(super.directory);

  final clearCompleted = Completer<void>();
  final releaseClear = Completer<void>();

  @override
  Future<void> clear(String root) async {
    await super.clear(root);
    clearCompleted.complete();
    await releaseClear.future;
  }
}

class ClearThenFailStore extends ScanRootRecordStore {
  ClearThenFailStore(super.directory);

  @override
  Future<void> clear(String root) async {
    await super.clear(root);
    throw const FileSystemException('clear failed after deleting record');
  }
}

Future<void> waitUntil(bool Function() done, {int maxTicks = 20}) async {
  for (var tick = 0; tick < maxTicks && !done(); tick++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

ScanSnapshotState scanSnapshot(String id, String root) =>
    ScanSnapshotState.fromWire({
      'snapshot_id': id,
      'tree': {
        'path': root,
        'name': root.split('/').last,
        'is_dir': true,
        'children': const [],
      },
      'entries': const [],
    });

void main() {
  test('stale restore does not apply after a newer switch', () async {
    final temp = await Directory.systemTemp.createTemp(
      'volward-switch-stale-restore',
    );
    addTearDown(() {
      SnapshotCache.cacheDirForTest = null;
      temp.deleteSync(recursive: true);
    });
    SnapshotCache.cacheDirForTest = temp;
    writeCachedSnapshot(
      cacheDir: temp,
      manifestName: 'slow-restore',
      snapshotName: 'slow-restore',
      root: '/slow-restore',
      snapshotId: 'slow-restore-scan',
      scannedAtMs: 1700000000900,
      sizeBytes: 512,
      reclaimableBytes: 7,
    );

    final staleRestoreEntered = Completer<void>();
    final session = RecordingSession();
    session.restoreDelayForTest = const Duration(milliseconds: 50);
    session.restoreDelayStartedForTest = () {
      if (!staleRestoreEntered.isCompleted) {
        staleRestoreEntered.complete();
      }
    };
    unawaited(session.switchScanRoot('/slow-restore'));
    await staleRestoreEntered.future;
    await session.switchScanRoot('/fast');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await waitUntil(
      () => session.scanRoots.first == '/fast' && session.scanCalls >= 1,
    );

    expect(session.scanRoots, ['/fast']);
    expect(session.lastSnapshot?.tree?.path, isNot('/slow-restore'));
  });

  test('rescan overwrites completed cache for the current root only', () async {
    final temp = await Directory.systemTemp.createTemp(
      'volward-rescan-current-root',
    );
    addTearDown(() {
      SnapshotCache.cacheDirForTest = null;
      temp.deleteSync(recursive: true);
    });
    SnapshotCache.cacheDirForTest = temp;
    const rootA = '/Users/test/A';
    const rootB = '/Users/test/B';
    writeCachedSnapshot(
      cacheDir: temp,
      manifestName: 'root-a',
      snapshotName: 'root-a',
      root: rootA,
      snapshotId: 'old-a',
      scannedAtMs: 1700000001000,
      sizeBytes: 100,
      reclaimableBytes: 10,
    );
    writeCachedSnapshot(
      cacheDir: temp,
      manifestName: 'root-b',
      snapshotName: 'root-b',
      root: rootB,
      snapshotId: 'old-b',
      scannedAtMs: 1700000001100,
      sizeBytes: 200,
      reclaimableBytes: 20,
    );
    final store = ScanRootRecordStore(temp);
    await store.save(
      const ScanRootRecord(
        root: rootA,
        status: ScanRootStatus.completed,
        snapshotId: 'old-a',
        updatedAtMs: 1700000001000,
      ),
    );
    await store.save(
      const ScanRootRecord(
        root: rootB,
        status: ScanRootStatus.completed,
        snapshotId: 'old-b',
        updatedAtMs: 1700000001100,
      ),
    );
    final session = VolwardSession.test()
      ..rootRecordStoreForTest = store
      ..setScanRoots(['/other']);

    await session.switchScanRoot(rootA);
    await waitUntil(() => session.lastSnapshot?.snapshotId == 'old-a');
    session.scanRunnerForTest = (_, __) async => scanSnapshot('new-a', rootA);
    await session.runScan(mode: ScanRunMode.rescan);

    expect((await store.load(rootA))?.snapshotId, 'new-a');
    expect((await store.load(rootB))?.snapshotId, 'old-b');
  });

  test(
    'switch waits while a completed scan writes to its owner root',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-completion-owner-root',
      );
      addTearDown(() {
        SnapshotCache.cacheDirForTest = null;
        temp.deleteSync(recursive: true);
      });
      SnapshotCache.cacheDirForTest = temp;
      const ownerRoot = '/Users/test/Owner';
      const currentRoot = '/Users/test/Current';
      writeCachedSnapshot(
        cacheDir: temp,
        manifestName: 'current',
        snapshotName: 'current',
        root: currentRoot,
        snapshotId: 'current-scan',
        scannedAtMs: 1700000001200,
        sizeBytes: 300,
        reclaimableBytes: 30,
      );
      final store = DelayedFirstCompletedSaveStore(temp);
      await store.save(
        const ScanRootRecord(
          root: currentRoot,
          status: ScanRootStatus.completed,
          snapshotId: 'current-scan',
          updatedAtMs: 1700000001200,
        ),
      );
      store.arm();
      final session = VolwardSession.test()
        ..rootRecordStoreForTest = store
        ..setScanRoots([ownerRoot])
        ..pauseCurrentScanForTest = (() async => true)
        ..scanRunnerForTest = (_, __) async =>
            scanSnapshot('owner-scan', ownerRoot);

      final scan = session.runScan(mode: ScanRunMode.rescan);
      await store.firstCompletedSaveStarted.future;
      var switchCompleted = false;
      final switching = session
          .switchScanRoot(currentRoot)
          .then((_) => switchCompleted = true);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(switchCompleted, isFalse);
      expect(session.scanRoots, [ownerRoot]);

      store.releaseFirstCompletedSave.complete();
      await scan;
      await switching;
      await waitUntil(() => session.lastSnapshot?.snapshotId == 'current-scan');

      expect(session.lastSnapshot?.snapshotId, 'current-scan');
      expect((await store.load(ownerRoot))?.snapshotId, 'owner-scan');
      expect((await store.load(currentRoot))?.snapshotId, 'current-scan');
    },
  );

  test('corrupt completed manifest autostarts with unreadable error', () async {
    final temp = await Directory.systemTemp.createTemp(
      'volward-corrupt-manifest',
    );
    addTearDown(() {
      SnapshotCache.cacheDirForTest = null;
      temp.deleteSync(recursive: true);
    });
    SnapshotCache.cacheDirForTest = temp;
    const root = '/Users/test/CorruptManifest';
    writeCachedSnapshot(
      cacheDir: temp,
      manifestName: 'corrupt',
      snapshotName: 'corrupt',
      root: root,
      snapshotId: 'corrupt-scan',
      scannedAtMs: 1700000001300,
      sizeBytes: 400,
      reclaimableBytes: 40,
    );
    File('${temp.path}/manifests/corrupt.json').writeAsStringSync('{');
    final store = ScanRootRecordStore(temp);
    await store.save(
      const ScanRootRecord(
        root: root,
        status: ScanRootStatus.completed,
        snapshotId: 'corrupt-scan',
        updatedAtMs: 1700000001300,
      ),
    );
    final session = RecordingSession()
      ..rootRecordStoreForTest = store
      ..setScanRoots(['/other']);

    await session.switchScanRoot(root);
    await waitUntil(() => session.scanCalls == 1);

    expect(session.scanCalls, 1);
    expect(session.lastError, 'scan-cache-unreadable');
  });

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

  test('same-root reselect accepts the running scan completion', () async {
    final temp = await Directory.systemTemp.createTemp(
      'volward-switch-same-root-completion',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    const root = '/Users/test/Active';
    final store = ScanRootRecordStore(temp);
    final scanGate = Completer<ScanSnapshotState?>();
    final session = VolwardSession.test()
      ..rootRecordStoreForTest = store
      ..setScanRoots([root])
      ..scanRunnerForTest = (_, __) => scanGate.future;

    final scan = session.runScan();
    await waitUntil(() => session.scanning);
    final generation = session.rootSwitchGeneration;

    await session.switchScanRoot(root);
    expect(session.rootSwitchGeneration, generation);

    scanGate.complete(scanSnapshot('same-root-completed', root));
    await scan;

    expect(session.lastSnapshot?.snapshotId, 'same-root-completed');
    expect((await store.load(root))?.status, ScanRootStatus.completed);
    expect((await store.load(root))?.snapshotId, 'same-root-completed');
  });

  test(
    'root switch cancels a scan waiting for root status before it can run',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-switch-during-scan-setup',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      const staleRoot = '/Users/test/Stale';
      const currentRoot = '/Users/test/Current';
      final store = DelayedFirstLoadStore(temp);
      final scanGate = Completer<void>();
      final scannedRoots = <String>[];
      var activeScans = 0;
      var maxActiveScans = 0;
      final session = VolwardSession.test()
        ..rootRecordStoreForTest = store
        ..setScanRoots([staleRoot])
        ..scanRunnerForTest = (_, roots) async {
          scannedRoots.add(roots.single);
          activeScans++;
          maxActiveScans = maxActiveScans < activeScans
              ? activeScans
              : maxActiveScans;
          try {
            await scanGate.future;
            return scanSnapshot('scan-${roots.single}', roots.single);
          } finally {
            activeScans--;
          }
        };

      Object? staleError;
      final staleScan = session.runScan().catchError((Object error) {
        staleError = error;
        return 'stale-scan-cancelled';
      });
      await store.firstLoadStarted.future;

      await session.switchScanRoot(currentRoot);
      await waitUntil(() => scannedRoots.contains(currentRoot));
      store.releaseFirstLoad.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      scanGate.complete();
      await staleScan;
      await waitUntil(() => !session.scanning);

      expect(staleError, isA<ScanCancelledException>());
      expect(scannedRoots, [currentRoot]);
      expect(maxActiveScans, 1);
      expect(session.scanRoots, [currentRoot]);
      expect(session.lastSnapshot?.tree?.path, currentRoot);
      expect(await store.load(staleRoot), isNull);
    },
  );

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
    late RecordingSession session;
    session = RecordingSession()
      ..setScanRoots(['/a'])
      ..primeTransientScanStateForTest(scanning: true, openScanPorts: false)
      ..pauseCurrentScanForTest = () async {
        session.clearTransientScanStateForTest();
        return true;
      };
    await session.switchScanRoot('/b');
    await waitUntil(() => session.scanCalls == 1);
    expect(session.scanRoots, ['/b']);
  });

  test(
    'concurrent same-root switch still waits for pause checkpoint',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-switch-concurrent-pause',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      const currentRoot = '/Users/test/Current';
      final checkpoint = File('${temp.path}/pause.index.json');
      final pauseRequested = Completer<void>();
      final store = ScanRootRecordStore(temp);
      late RecordingSession session;
      session = RecordingSession()
        ..rootRecordStoreForTest = store
        ..setScanRoots([currentRoot])
        ..primeTransientScanStateForTest(scanning: true, openScanPorts: false)
        ..pauseRequestForTest = (_, _) {
          pauseRequested.complete();
          return checkpoint.path;
        }
        ..pauseErrorForTest = () => null;

      var firstSwitchCompleted = false;
      final firstSwitch = session
          .switchScanRoot('/next')
          .then((_) => firstSwitchCompleted = true);
      await pauseRequested.future;

      await session.switchScanRoot(currentRoot);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(firstSwitchCompleted, isFalse);
      await checkpoint.writeAsString('{}');
      session.clearTransientScanStateForTest();
      await firstSwitch.timeout(const Duration(seconds: 1));
      expect((await store.load(currentRoot))?.status, ScanRootStatus.paused);
    },
  );

  test(
    'completed native scan switches when pause checkpoint is absent',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-switch-completed-race',
      );
      addTearDown(() {
        SnapshotCache.cacheDirForTest = null;
        temp.deleteSync(recursive: true);
      });
      SnapshotCache.cacheDirForTest = temp;
      const completedRoot = '/Users/test/CompletedDuringPause';
      writeCachedSnapshot(
        cacheDir: temp,
        manifestName: 'completed-during-pause',
        snapshotName: 'completed-during-pause',
        root: completedRoot,
        snapshotId: 'completed-during-pause-scan',
        scannedAtMs: 1700000000400,
        sizeBytes: 1024,
        reclaimableBytes: 11,
      );
      final store = ScanRootRecordStore(temp);
      late RecordingSession session;
      session = RecordingSession()
        ..rootRecordStoreForTest = store
        ..setScanRoots([completedRoot])
        ..primeTransientScanStateForTest(scanning: true, openScanPorts: false)
        ..pauseRequestForTest = (_, _) {
          scheduleMicrotask(session.clearTransientScanStateForTest);
          return '${temp.path}/missing-pause.index.json';
        }
        ..pauseErrorForTest = () => 'scan already completed';

      await session.switchScanRoot('/next');

      expect(session.scanRoots, ['/next']);
      expect(
        (await store.load(completedRoot))?.status,
        ScanRootStatus.completed,
      );
    },
  );

  test(
    'old authoritative snapshot does not replace current pause checkpoint',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-switch-old-snapshot',
      );
      addTearDown(() {
        SnapshotCache.cacheDirForTest = null;
        temp.deleteSync(recursive: true);
      });
      SnapshotCache.cacheDirForTest = temp;
      const currentRoot = '/Users/test/Existing';
      final checkpoint = File('${temp.path}/pause.index.json');
      await checkpoint.writeAsString('{}');
      final store = ScanRootRecordStore(temp);
      await store.save(
        ScanRootRecord(
          root: currentRoot,
          status: ScanRootStatus.paused,
          snapshotId: 'old-snapshot',
          checkpointPath: checkpoint.path,
          updatedAtMs: 1700000000000,
        ),
      );
      late RecordingSession session;
      session = RecordingSession()
        ..rootRecordStoreForTest = store
        ..setScanRoots([currentRoot])
        ..setSnapshotForTest(
          ScanSnapshotState.fromWire({
            'snapshot_id': 'old-snapshot',
            'tree': {
              'path': currentRoot,
              'name': 'Existing',
              'is_dir': true,
              'children': const [],
            },
            'entries': const [],
          }),
        )
        ..primeTransientScanStateForTest(scanning: true, openScanPorts: false)
        ..pauseRequestForTest = (_, _) {
          scheduleMicrotask(session.clearTransientScanStateForTest);
          return checkpoint.path;
        }
        ..pauseErrorForTest = () => null;

      await session.switchScanRoot('/next');

      expect(session.scanRoots, ['/next']);
      expect((await store.load(currentRoot))?.status, ScanRootStatus.paused);
      expect(await checkpoint.exists(), isTrue);
    },
  );

  test('native stop wait does not treat two-second deadline as idle', () async {
    final session = RecordingSession();
    var nativeRunning = true;
    var waitCompleted = false;
    final waiting = session
        .waitForNativeScanToStopForTest(() => nativeRunning)
        .then((_) => waitCompleted = true);

    await Future<void>.delayed(const Duration(milliseconds: 2100));

    expect(waitCompleted, isFalse);
    nativeRunning = false;
    await waiting.timeout(const Duration(seconds: 1));
  });

  test(
    'record save failure makes pause fail without switching roots',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-switch-record-failure',
      );
      addTearDown(() {
        SnapshotCache.cacheDirForTest = null;
        temp.deleteSync(recursive: true);
      });
      SnapshotCache.cacheDirForTest = temp;
      const currentRoot = '/Users/test/Current';
      final checkpoint = File('${temp.path}/pause.index.json');
      await checkpoint.writeAsString('{}');
      late RecordingSession session;
      session = RecordingSession()
        ..rootRecordStoreForTest = FailingSaveStore(temp)
        ..setScanRoots([currentRoot])
        ..primeTransientScanStateForTest(scanning: true, openScanPorts: false)
        ..pauseRequestForTest = (_, _) {
          scheduleMicrotask(session.clearTransientScanStateForTest);
          return checkpoint.path;
        }
        ..pauseErrorForTest = () => null;

      await expectLater(session.switchScanRoot('/next'), completes);

      expect(session.scanRoots, [currentRoot]);
      expect(session.lastError, 'scan-pause-failed');
    },
  );

  test('cancelled rescan restores the previous completed record', () async {
    final temp = await Directory.systemTemp.createTemp(
      'volward-cancelled-rescan',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    const root = '/Users/test/Completed';
    final store = ScanRootRecordStore(temp);
    await store.save(
      const ScanRootRecord(
        root: root,
        status: ScanRootStatus.completed,
        snapshotId: 'completed-scan',
        updatedAtMs: 1700000000000,
      ),
    );
    final session = VolwardSession.test()
      ..rootRecordStoreForTest = store
      ..setScanRoots([root])
      ..scanRunnerForTest = (_, __) async {
        throw ScanCancelledException();
      };

    await expectLater(
      session.runScan(mode: ScanRunMode.rescan),
      throwsA(isA<ScanCancelledException>()),
    );

    final restored = await store.load(root);
    expect(restored?.status, ScanRootStatus.completed);
    expect(restored?.snapshotId, 'completed-scan');
  });

  test(
    'failed completion save restores the snapshot id captured at scan start',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-failed-completion-rollback',
      );
      addTearDown(() {
        SnapshotCache.cacheDirForTest = null;
        temp.deleteSync(recursive: true);
      });
      SnapshotCache.cacheDirForTest = temp;
      const rootA = '/Users/test/A';
      const rootB = '/Users/test/B';
      writeCachedSnapshot(
        cacheDir: temp,
        manifestName: 'root-a',
        snapshotName: 'root-a',
        root: rootA,
        snapshotId: 'old-a',
        scannedAtMs: 1700000001000,
        sizeBytes: 100,
        reclaimableBytes: 10,
      );
      final store = DelayedFirstCompletedSaveStore(temp, failFirst: true)
        ..arm();
      final session = VolwardSession.test()
        ..rootRecordStoreForTest = store
        ..setScanRoots([rootA])
        ..setSnapshotForTest(scanSnapshot('old-a', rootA))
        ..scanRunnerForTest = (_, __) async => scanSnapshot('new-a', rootA);

      final scan = session.runScan(mode: ScanRunMode.rescan);
      await store.firstCompletedSaveStarted.future;
      session.setSnapshotForTest(scanSnapshot('current-b', rootB));
      store.releaseFirstCompletedSave.complete();

      await expectLater(scan, throwsA(isA<FileSystemException>()));
      final restored = await store.load(rootA);
      expect(restored?.status, ScanRootStatus.completed);
      expect(restored?.snapshotId, 'old-a');
    },
  );

  test(
    'root switch during rescan clear restores the previous completed record',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-switch-during-rescan-clear',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      const staleRoot = '/Users/test/Completed';
      const currentRoot = '/Users/test/Current';
      final store = ClearedThenDelayedStore(temp);
      await store.save(
        const ScanRootRecord(
          root: staleRoot,
          status: ScanRootStatus.completed,
          snapshotId: 'completed-scan',
          updatedAtMs: 1700000000000,
        ),
      );
      final scannedRoots = <String>[];
      final session = VolwardSession.test()
        ..rootRecordStoreForTest = store
        ..setScanRoots([staleRoot])
        ..scanRunnerForTest = (_, roots) async {
          scannedRoots.add(roots.single);
          return scanSnapshot('scan-${roots.single}', roots.single);
        };

      Object? staleError;
      final staleScan = session.runScan(mode: ScanRunMode.rescan).catchError((
        Object error,
      ) {
        staleError = error;
        return 'stale-scan-cancelled';
      });
      await store.clearCompleted.future;

      await session.switchScanRoot(currentRoot);
      store.releaseClear.complete();
      await staleScan;
      await waitUntil(() => scannedRoots.contains(currentRoot));

      final restored = await store.load(staleRoot);
      expect(staleError, isA<ScanCancelledException>());
      expect(restored?.status, ScanRootStatus.completed);
      expect(restored?.snapshotId, 'completed-scan');
      expect(session.scanRoots, [currentRoot]);
      expect(scannedRoots, [currentRoot]);
    },
  );

  test('rescan clear failure restores the previous completed record', () async {
    final temp = await Directory.systemTemp.createTemp(
      'volward-rescan-clear-failure',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    const root = '/Users/test/Completed';
    final store = ClearThenFailStore(temp);
    await store.save(
      const ScanRootRecord(
        root: root,
        status: ScanRootStatus.completed,
        snapshotId: 'completed-scan',
        updatedAtMs: 1700000000000,
      ),
    );
    final session = VolwardSession.test()
      ..rootRecordStoreForTest = store
      ..setScanRoots([root])
      ..scanRunnerForTest = (_, __) async => scanSnapshot('unexpected', root);

    await expectLater(
      session.runScan(mode: ScanRunMode.rescan),
      throwsA(isA<FileSystemException>()),
    );

    final restored = await store.load(root);
    expect(restored?.status, ScanRootStatus.completed);
    expect(restored?.snapshotId, 'completed-scan');
  });

  test(
    'root switch cancels preparation while waiting for index load drain',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-switch-during-index-drain',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      const staleRoot = '/Users/test/Stale';
      const currentRoot = '/Users/test/Current';
      final store = ScanRootRecordStore(temp);
      final drainStarted = Completer<void>();
      final releaseDrain = Completer<void>();
      var drainCalls = 0;
      final scannedRoots = <String>[];
      final session = VolwardSession.test()
        ..rootRecordStoreForTest = store
        ..setScanRoots([staleRoot])
        ..scanPreparationWaitForTest = () async {
          drainCalls++;
          if (drainCalls == 1) {
            drainStarted.complete();
            await releaseDrain.future;
          }
        }
        ..scanRunnerForTest = (_, roots) async {
          scannedRoots.add(roots.single);
          return scanSnapshot('scan-${roots.single}', roots.single);
        };

      Object? staleError;
      final staleScan = session.runScan().catchError((Object error) {
        staleError = error;
        return 'stale-scan-cancelled';
      });
      await drainStarted.future;

      await session.switchScanRoot(currentRoot);
      releaseDrain.complete();
      await staleScan;
      await waitUntil(() => scannedRoots.contains(currentRoot));

      expect(staleError, isA<ScanCancelledException>());
      expect(session.scanRoots, [currentRoot]);
      expect(scannedRoots, [currentRoot]);
      expect(session.lastError, isNot('scan-pause-failed'));
    },
  );

  test('cancelled rescan preserves a newly written paused record', () async {
    final temp = await Directory.systemTemp.createTemp('volward-paused-rescan');
    addTearDown(() => temp.deleteSync(recursive: true));
    const root = '/Users/test/Completed';
    final checkpoint = File('${temp.path}/pause.index.json');
    await checkpoint.writeAsString('{}');
    final store = ScanRootRecordStore(temp);
    await store.save(
      const ScanRootRecord(
        root: root,
        status: ScanRootStatus.completed,
        snapshotId: 'completed-scan',
        updatedAtMs: 1700000000000,
      ),
    );
    final session = VolwardSession.test()
      ..rootRecordStoreForTest = store
      ..setScanRoots([root])
      ..scanRunnerForTest = (_, __) async {
        await store.save(
          ScanRootRecord(
            root: root,
            status: ScanRootStatus.paused,
            snapshotId: 'paused-scan',
            checkpointPath: checkpoint.path,
            updatedAtMs: 1700000000100,
          ),
        );
        throw ScanCancelledException();
      };

    await expectLater(
      session.runScan(mode: ScanRunMode.rescan),
      throwsA(isA<ScanCancelledException>()),
    );

    final paused = await store.load(root);
    expect(paused?.status, ScanRootStatus.paused);
    expect(paused?.checkpointPath, checkpoint.path);
  });

  test(
    'completed record save failure preserves the paused checkpoint',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-completed-save-failure',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      const root = '/Users/test/Paused';
      final checkpoint = File('${temp.path}/pause.index.json');
      final manifest = File('${temp.path}/pause.manifest.json');
      await checkpoint.writeAsString('{}');
      await manifest.writeAsString('{}');
      final store = FailingCompletedSaveStore(temp);
      await store.save(
        ScanRootRecord(
          root: root,
          status: ScanRootStatus.paused,
          snapshotId: 'paused-scan',
          checkpointPath: checkpoint.path,
          updatedAtMs: 1700000000000,
        ),
      );
      final session = VolwardSession.test()
        ..rootRecordStoreForTest = store
        ..setScanRoots([root])
        ..scanRunnerForTest = (_, __) async => scanSnapshot('new-scan', root);

      await expectLater(
        session.runScan(mode: ScanRunMode.resume),
        throwsA(isA<FileSystemException>()),
      );

      expect((await store.load(root))?.status, ScanRootStatus.paused);
      expect(await checkpoint.exists(), isTrue);
      expect(await manifest.exists(), isTrue);
    },
  );

  test(
    'stale oversized-cache error does not block corrupt cache scan',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-switch-stale-restore-error',
      );
      addTearDown(() {
        SnapshotCache.cacheDirForTest = null;
        temp.deleteSync(recursive: true);
      });
      SnapshotCache.cacheDirForTest = temp;
      const oversizedRoot = '/Users/test/Oversized';
      const corruptRoot = '/Users/test/Corrupt';
      writeCachedSnapshot(
        cacheDir: temp,
        manifestName: 'oversized',
        snapshotName: 'oversized',
        root: oversizedRoot,
        snapshotId: 'oversized-scan',
        scannedAtMs: 1700000000500,
        sizeBytes: 1,
        reclaimableBytes: 0,
      );
      final oversizedFile = File('${temp.path}/snapshots/oversized.json');
      final oversizedHandle = oversizedFile.openSync(mode: FileMode.append);
      oversizedHandle.truncateSync(128 * 1024 * 1024 + 1);
      oversizedHandle.closeSync();
      writeCachedSnapshot(
        cacheDir: temp,
        manifestName: 'corrupt',
        snapshotName: 'corrupt',
        root: corruptRoot,
        snapshotId: 'corrupt-scan',
        scannedAtMs: 1700000000600,
        sizeBytes: 1,
        reclaimableBytes: 0,
      );
      File('${temp.path}/snapshots/corrupt.json').writeAsStringSync('{');

      final session = RecordingSession()..setScanRoots(['/other']);
      await session.switchScanRoot(oversizedRoot);
      await waitUntil(() => session.lastError == 'scan-cache-too-large');
      expect(session.scanCalls, 0);

      await session.switchScanRoot(corruptRoot);
      await waitUntil(() => session.scanCalls == 1);

      expect(session.scanCalls, 1);
      expect(session.scanModes, [ScanRunMode.auto]);
    },
  );

  test('oversized cache clears target preview loading and notifies', () async {
    final temp = await Directory.systemTemp.createTemp(
      'volward-switch-oversized-loading',
    );
    addTearDown(() {
      SnapshotCache.cacheDirForTest = null;
      temp.deleteSync(recursive: true);
    });
    SnapshotCache.cacheDirForTest = temp;
    const root = '/Users/test/Oversized';
    writeCachedSnapshot(
      cacheDir: temp,
      manifestName: 'oversized-loading',
      snapshotName: 'oversized-loading',
      root: root,
      snapshotId: 'oversized-loading-scan',
      scannedAtMs: 1700000000800,
      sizeBytes: 1,
      reclaimableBytes: 0,
    );
    final oversizedFile = File('${temp.path}/snapshots/oversized-loading.json');
    final oversizedHandle = oversizedFile.openSync(mode: FileMode.append);
    oversizedHandle.truncateSync(128 * 1024 * 1024 + 1);
    oversizedHandle.closeSync();

    final observableStates = <({String? error, bool loading})>[];
    final session = RecordingSession()..setScanRoots(['/other']);
    session.addListener(() {
      observableStates.add((
        error: session.lastError,
        loading: session.targetPreviewLoading,
      ));
    });

    await session.switchScanRoot(root);
    await waitUntil(() => session.lastError == 'scan-cache-too-large');

    expect(session.targetPreviewLoading, isFalse);
    expect(
      observableStates,
      contains((error: 'scan-cache-too-large', loading: false)),
    );
    expect(session.scanCalls, 0);
  });

  test(
    'corrupt cache error remains observable after automatic scan starts',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'volward-switch-corrupt-error',
      );
      addTearDown(() {
        SnapshotCache.cacheDirForTest = null;
        temp.deleteSync(recursive: true);
      });
      SnapshotCache.cacheDirForTest = temp;
      const corruptRoot = '/Users/test/Corrupt';
      writeCachedSnapshot(
        cacheDir: temp,
        manifestName: 'corrupt-visible',
        snapshotName: 'corrupt-visible',
        root: corruptRoot,
        snapshotId: 'corrupt-visible-scan',
        scannedAtMs: 1700000000700,
        sizeBytes: 1,
        reclaimableBytes: 0,
      );
      File(
        '${temp.path}/snapshots/corrupt-visible.json',
      ).writeAsStringSync('{');
      final scanGate = Completer<ScanSnapshotState?>();
      final observedErrorsAfterScanStart = <String?>[];
      final session = VolwardSession.test()
        ..setScanRoots(['/other'])
        ..scanRunnerForTest = (_, _) => scanGate.future;
      session.addListener(() {
        if (session.scanning) {
          observedErrorsAfterScanStart.add(session.lastError);
        }
      });

      await session.switchScanRoot(corruptRoot);
      await waitUntil(() => session.scanning);

      expect(session.lastError, 'scan-cache-unreadable');
      expect(observedErrorsAfterScanStart, contains('scan-cache-unreadable'));

      scanGate.complete(scanSnapshot('replacement-scan', corruptRoot));
      await waitUntil(() => !session.scanning);
    },
  );

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
