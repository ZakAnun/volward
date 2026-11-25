import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/features/ai_coverage/controllers/ai_analysis_delete_controller.dart';

void main() {
  test(
    'delete completion after detach clears busy without old notification',
    () async {
      final deletion = AiAnalysisDeleteController.forTest(delayedDelete: true);
      var notifications = 0;
      final confirmGate = Completer<bool>();

      final pending = deletion.deleteSelected(
        generation: 0,
        confirm: (_) => confirmGate.future,
        onCompleted: () => notifications++,
      );
      confirmGate.complete(true);
      await pumpEventQueue();
      deletion.detachOwner();
      deletion.completeDelayedDelete(const {'deleted_count': 1});
      await pending;

      expect(deletion.deleteState.busy, isFalse);
      expect(notifications, 0);
    },
  );

  test('successful delete notifies completion once', () async {
    final deletion = AiAnalysisDeleteController.forTest(delayedDelete: true);
    var notifications = 0;

    final pending = deletion.deleteSelected(
      generation: 0,
      confirm: (_) async => true,
      onCompleted: () => notifications++,
    );
    deletion.completeDelayedDelete(const {'deleted_count': 3});
    final completed = await pending;

    expect(completed, isTrue);
    expect(notifications, 1);
    expect(deletion.deleteState.busy, isFalse);
  });

  test('partial delete records retry targets and failure counts', () async {
    final deletion = AiAnalysisDeleteController.forTest(delayedDelete: true);
    var notifications = 0;

    final pending = deletion.deleteSelected(
      generation: 0,
      confirm: (_) async => true,
      onCompleted: () => notifications++,
    );
    deletion.completeDelayedDelete({
      'failed_paths': ['/a', '/b'],
      'freed_bytes': 42,
    });
    final completed = await pending;

    expect(completed, isFalse);
    expect(notifications, 0);
    expect(deletion.retryTargets, ['/a', '/b']);
    expect(deletion.partialDeleteFailedCount, 2);
    expect(deletion.partialDeleteFreedBytes, 42);
  });
}
