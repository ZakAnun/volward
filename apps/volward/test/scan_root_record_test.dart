import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_root_record.dart';

void main() {
  test('save and load a paused record by normalized root', () async {
    final dir = await Directory.systemTemp.createTemp('volward-root-record');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = ScanRootRecordStore(dir);
    const root = '/Users/test/Downloads/';
    await store.save(
      ScanRootRecord(
        root: root,
        status: ScanRootStatus.paused,
        snapshotId: 'job-1-checkpoint',
        checkpointPath: '${dir.path}/pause.json',
        jobId: 'job-1',
        updatedAtMs: 1700000000000,
      ),
    );

    final loaded = await store.load('/Users/test/Downloads');
    expect(loaded, isNotNull);
    expect(loaded!.status, ScanRootStatus.paused);
    expect(loaded.snapshotId, 'job-1-checkpoint');
    expect(loaded.jobId, 'job-1');
    expect(loaded.root, '/Users/test/Downloads');
  });

  test('clear removes the record', () async {
    final dir = await Directory.systemTemp.createTemp(
      'volward-root-record-clear',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = ScanRootRecordStore(dir);
    await store.save(
      const ScanRootRecord(
        root: '/a',
        status: ScanRootStatus.completed,
        snapshotId: 'done',
        updatedAtMs: 1,
      ),
    );
    await store.clear('/a');
    expect(await store.load('/a'), isNull);
  });

  test(
    'inferredStatus prefers live scanning, then record, then completed snapshot',
    () {
      expect(
        ScanRootRecordStore.inferredStatus(
          root: '/a',
          isCurrentAndScanning: true,
          record: null,
          hasCompletedSnapshot: true,
        ),
        ScanRootStatus.scanning,
      );
      expect(
        ScanRootRecordStore.inferredStatus(
          root: '/a',
          isCurrentAndScanning: false,
          record: const ScanRootRecord(
            root: '/a',
            status: ScanRootStatus.paused,
            updatedAtMs: 1,
          ),
          hasCompletedSnapshot: true,
        ),
        ScanRootStatus.paused,
      );
      expect(
        ScanRootRecordStore.inferredStatus(
          root: '/a',
          isCurrentAndScanning: false,
          record: null,
          hasCompletedSnapshot: true,
        ),
        ScanRootStatus.completed,
      );
      expect(
        ScanRootRecordStore.inferredStatus(
          root: '/a',
          isCurrentAndScanning: false,
          record: null,
          hasCompletedSnapshot: false,
        ),
        ScanRootStatus.empty,
      );
    },
  );
}
