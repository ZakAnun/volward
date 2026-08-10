import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/volward_session.dart';

void main() {
  group('VolwardSession scan cleanup', () {
    test('runScan clears transient scan state at completion', () async {
      final session = VolwardSession.test();
      session.setScanRoots(['/root']);
      session.primeTransientScanStateForTest(
        progress: {'phase': 'Walking', 'paths_seen': 12},
        scanning: false,
      );
      session.scanRunnerForTest = (jobId, roots) async {
        expect(jobId, startsWith('job-'));
        expect(roots, ['/root']);
        return ScanSnapshotState.fromWire({
          'snapshot_id': 'snap-run',
          'scanned_at_ms': 1,
          'reclaimable_estimate_bytes': 0,
          'entries': [],
          'tree': {
            'name': 'root',
            'path': '/root',
            'is_dir': true,
            'children': [],
          },
          'stats': {},
        });
      };

      final snapshotId = await session.runScan();

      expect(snapshotId, 'snap-run');
      expect(session.transientFinalizeCount, 1);
      expect(session.lastJobId, isNull);
      expect(session.scanRunnerForTest, isNull);
      expect(session.scanProgress, isNull);
      expect(session.hasTransientScanStateForTest, isFalse);
      expect(session.scanElapsedNotifier.value, isNull);
      expect(session.scannedFractionNotifier.value, isNull);
      expect(session.refreshTargetPath, '/root');
    });

    test('cancelScan clears transient scan state', () {
      final session = VolwardSession.test();
      session.setScanRoots(['/root']);
      session.setCurrentPathForTest('/root/Documents');
      session.primeTransientScanStateForTest(
        progress: {
          'phase': 'Walking',
          'paths_seen': 42,
          'dirs_seen': 10,
          'files_seen': 32,
        },
        lastJobId: 'job-cancel-test',
      );
      session.scanElapsedNotifier.value = '12s';
      session.scannedFractionNotifier.value = 0.42;

      session.cancelScan();

      expect(session.transientFinalizeCount, 1);
      expect(session.lastJobId, isNull);
      expect(session.scanProgress, isNull);
      expect(session.scanElapsedNotifier.value, isNull);
      expect(session.scannedFractionNotifier.value, isNull);
      expect(session.refreshTargetPath, '/root/Documents');
      expect(session.currentDirectoryPath, '/root/Documents');
      expect(session.scanRoots, ['/root']);
      expect(session.hasTransientScanStateForTest, isFalse);
    });

    test('dispose clears transient scan state', () {
      final session = VolwardSession.test();
      session.setScanRoots(['/root']);
      session.setCurrentPathForTest('/root/Documents');
      session.primeTransientScanStateForTest(
        progress: {'phase': 'SavingResults', 'paths_seen': 10},
        lastJobId: 'job-dispose-test',
      );

      session.dispose();

      expect(session.transientFinalizeCount, 1);
      expect(session.lastJobId, isNull);
      expect(session.hasTransientScanStateForTest, isFalse);
      expect(session.scanElapsedNotifier.value, isNull);
      expect(session.scannedFractionNotifier.value, isNull);
    });

    test('cleanup resets merge throttle for a rapid second scan', () async {
      final session = VolwardSession.test();
      final snapshot = ScanSnapshotState.fromWire({
        'snapshot_id': 'snap-merge',
        'scanned_at_ms': 1,
        'reclaimable_estimate_bytes': 0,
        'entries': [],
        'tree': {
          'name': 'root',
          'path': '/root',
          'is_dir': true,
          'children': [
            {
              'name': 'Library',
              'path': '/root/Library',
              'is_dir': true,
              'children': [],
            },
          ],
        },
        'stats': {},
      });
      final subtreeTree = <String, dynamic>{
        'name': 'root',
        'path': '/root',
        'is_dir': true,
        'children': [
          {
            'name': 'Library',
            'path': '/root/Library',
            'is_dir': true,
            'children': [],
          },
        ],
      };

      session.setSnapshotForTest(snapshot);
      var notifyCount = 0;
      session.addListener(() {
        notifyCount++;
      });

      session.primeTransientScanStateForTest(
        progress: {'phase': 'Walking', 'paths_seen': 1},
      );
      await session.applyMergeForTest('/root', subtreeTree, []);
      expect(notifyCount, 1);

      session.clearTransientScanStateForTest();
      session.primeTransientScanStateForTest(
        progress: {'phase': 'Walking', 'paths_seen': 2},
      );
      await session.applyMergeForTest('/root', subtreeTree, []);
      expect(notifyCount, 2);
    });

    test('applyMerge keeps the native snapshot id stable', () async {
      final session = VolwardSession.test();
      final snapshot = ScanSnapshotState.fromWire({
        'snapshot_id': 'snap-native',
        'scanned_at_ms': 1,
        'reclaimable_estimate_bytes': 0,
        'entries': [],
        'tree': {
          'name': 'root',
          'path': '/root',
          'is_dir': true,
          'children': [
            {
              'name': 'Documents',
              'path': '/root/Documents',
              'is_dir': true,
              'children': [],
            },
          ],
        },
        'stats': {},
      });
      final subtreeTree = <String, dynamic>{
        'name': 'Documents',
        'path': '/root/Documents',
        'is_dir': true,
        'children': [
          {
            'name': 'a.txt',
            'path': '/root/Documents/a.txt',
            'is_dir': false,
            'size_bytes': 1,
            'entry_id': 'e1',
            'children': [],
          },
        ],
      };

      session.setSnapshotForTest(snapshot);
      await session.applyMergeForTest('/root/Documents', subtreeTree, [
        {
          'id': 'e1',
          'display_name': 'a.txt',
          'path_or_uri': '/root/Documents/a.txt',
          'size_bytes': 1,
          'category': 'Other',
          'risk_level': 'Low',
          'source_type': 'File',
          'deletable': true,
          'reason': 'test',
        },
      ]);

      expect(session.lastSnapshot?.snapshotId, 'snap-native');
    });
  });
}
