import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/volward_session.dart';

void main() {
  group('VolwardSession scan cleanup', () {
    test('runScan clears transient scan state at completion', () async {
      final session = VolwardSession.test();
      session.setScanRoots(['/root']);
      session.primeTransientScanStateForTest(progress: {
        'phase': 'Walking',
        'paths_seen': 12,
      }, scanning: false);
      session.scanRunnerForTest = (jobId, roots) async {
        expect(jobId, startsWith('job-'));
        expect(roots, ['/root']);
        return ScanSnapshotState.fromWire({
          'snapshot_id': 'snap-run',
          'scanned_at_ms': 1,
          'reclaimable_estimate_bytes': 0,
          'entries': const [],
          'tree': {
            'name': 'root',
            'path': '/root',
            'is_dir': true,
            'children': const [],
          },
          'stats': const {},
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
      session.primeTransientScanStateForTest(progress: {
        'phase': 'Walking',
        'paths_seen': 42,
        'dirs_seen': 10,
        'files_seen': 32,
      }, lastJobId: 'job-cancel-test');
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
      session.primeTransientScanStateForTest(progress: {
        'phase': 'SavingResults',
        'paths_seen': 10,
      }, lastJobId: 'job-dispose-test');

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
        'entries': const [],
        'tree': {
          'name': 'root',
          'path': '/root',
          'is_dir': true,
          'children': const [
            {
              'name': 'Library',
              'path': '/root/Library',
              'is_dir': true,
              'children': const [],
            },
          ],
        },
        'stats': const {},
      });
      final subtreeTree = <String, dynamic>{
        'name': 'root',
        'path': '/root',
        'is_dir': true,
        'children': const [
          {
            'name': 'Library',
            'path': '/root/Library',
            'is_dir': true,
            'children': const [],
          },
        ],
      };

      session.setSnapshotForTest(snapshot);
      var notifyCount = 0;
      session.addListener(() {
        notifyCount++;
      });

      session.primeTransientScanStateForTest(progress: {
        'phase': 'Walking',
        'paths_seen': 1,
      });
      await session.applyMergeForTest('/root', subtreeTree, const []);
      expect(notifyCount, 1);

      session.clearTransientScanStateForTest();
      session.primeTransientScanStateForTest(progress: {
        'phase': 'Walking',
        'paths_seen': 2,
      });
      await session.applyMergeForTest('/root', subtreeTree, const []);
      expect(notifyCount, 2);
    });
  });
}
