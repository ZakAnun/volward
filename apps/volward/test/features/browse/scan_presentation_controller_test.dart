import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/core/contracts/scan_contracts.dart';
import 'package:volward/features/browse/controllers/scan_presentation_controller.dart';

void main() {
  test('scan presentation owns progress, timing and action state', () {
    final controller = ScanPresentationController.forTest();
    final progress = ValueNotifier(
      const ScanProgressViewState(phase: 'Walking', fraction: 0.4),
    );
    final fraction = ValueNotifier<double?>(0.4);
    final elapsed = ValueNotifier<String?>('12s');
    final lifecycle = _FakeScanLifecycle();
    addTearDown(() {
      controller.dispose();
      progress.dispose();
      fraction.dispose();
      elapsed.dispose();
    });

    controller.bindSource(
      progress: progress,
      scannedFraction: fraction,
      elapsedLabel: elapsed,
    );
    lifecycle.scanning = true;
    controller.updateFromLifecycle(
      lifecycle,
      restoringSnapshot: false,
      targetPreviewLoading: true,
      deleting: false,
      postDeleteRefreshPending: false,
      refreshingDirectoryCount: 2,
      progressDetail: const {'phase': 'Walking', 'paths_seen': 12},
    );

    expect(controller.scanning, isTrue);
    expect(controller.targetPreviewLoading, isTrue);
    expect(controller.refreshingDirectoryCount, 2);
    expect(controller.progressState.phase, 'Walking');
    expect(controller.scannedFraction.value, 0.4);
    expect(controller.elapsedLabel.value, '12s');
    expect(controller.progressDetail?['paths_seen'], 12);
  });

  test(
    'scan presentation notifies and owns cancel and pause actions',
    () async {
      var cancellations = 0;
      var pauses = 0;
      final controller = ScanPresentationController(
        onCancelScan: () => cancellations++,
        onPauseScan: () async {
          pauses++;
          return true;
        },
      );
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.markScanning(true);
      controller.cancelScan();

      expect(await controller.pauseScan(), isTrue);
      expect(cancellations, 1);
      expect(pauses, 1);
      expect(notifications, 1);
    },
  );
}

class _FakeScanLifecycle implements ScanLifecycle {
  @override
  bool scanning = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
