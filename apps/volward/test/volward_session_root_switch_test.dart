import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/volward_session.dart';

class RecordingSession extends VolwardSession {
  RecordingSession() : super.test();

  int previewCalls = 0;
  int peekCalls = 0;
  int scanCalls = 0;
  bool? lastPeekForce;

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
  Future<String> runScan() async {
    scanCalls++;
    return 'scan-$scanCalls';
  }
}

Future<void> waitUntil(bool Function() done, {int maxTicks = 20}) async {
  for (var tick = 0; tick < maxTicks && !done(); tick++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('prepared root previews without starting a full scan', () async {
    final session = RecordingSession();
    await session.switchScanRoot('/prepared', startFullScan: false);
    await waitUntil(() => session.previewCalls == 1);

    expect(session.scanRoots, ['/prepared']);
    expect(session.previewCalls, 1);
    expect(session.peekCalls, 0);
    expect(session.scanCalls, 0);
  });

  test('existing switchScanRoot callers still auto-start', () async {
    final session = RecordingSession();
    await session.switchScanRoot('/legacy');
    await waitUntil(() => session.previewCalls == 1 && session.scanCalls == 1);

    expect(session.previewCalls, 1);
    expect(session.peekCalls, 0);
    expect(session.scanCalls, 1);
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
}
