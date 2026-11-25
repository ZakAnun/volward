import 'package:flutter_test/flutter_test.dart';
import 'package:volward/features/ai_coverage/controllers/ai_analysis_workspace_controller.dart';
import 'dart:async';

void main() {
  test('late completion from an old owner is ignored', () {
    final controller = AiAnalysisWorkspaceController.forTest(
      ownerId: 'old-owner',
    );
    final generation = controller.beginOperation();

    controller.rebindOwner('new-owner');

    expect(controller.activeOwnerId, 'new-owner');
    expect(controller.isCurrent(generation), isFalse);
    expect(controller.displayState, AiWorkspaceDisplayState.loading);
  });

  test('busy callback is released after delete completes', () async {
    final busyStates = <bool>[];
    final controller = AiAnalysisWorkspaceController.forTest(
      ownerId: 'owner',
      onBusyChanged: busyStates.add,
    );

    final result = await controller.runBusy(() async {
      expect(controller.busy, isTrue);
      return 'done';
    });

    expect(result, 'done');
    expect(controller.busy, isFalse);
    expect(busyStates, [true, false]);
  });

  test('a second busy operation is rejected', () async {
    final controller = AiAnalysisWorkspaceController.forTest(ownerId: 'owner');
    final first = controller.runBusy(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );

    expect(await controller.runBusy(() async => 'second'), isNull);
    await first;
  });

  test('an asynchronous old-owner completion is ignored', () async {
    final controller = AiAnalysisWorkspaceController.forTest(
      ownerId: 'old-owner',
    );
    final completion = Completer<String>();
    final applied = <String>[];
    final pending = controller.runOwnerOperation(
      () => completion.future,
      onCurrentResult: applied.add,
    );

    controller.rebindOwner('new-owner');
    completion.complete('stale');
    await pending;

    expect(applied, isEmpty);
    expect(controller.displayState, AiWorkspaceDisplayState.loading);
  });

  test('rebinding keeps the old operation busy until it completes', () async {
    final controller = AiAnalysisWorkspaceController.forTest(ownerId: 'old');
    final oldCompletion = Completer<void>();
    final first = controller.runBusy(() => oldCompletion.future);
    expect(controller.busy, isTrue);

    controller.rebindOwner('new');
    expect(controller.busy, isTrue);
    expect(await controller.runBusy(() async => 'new'), isNull);

    oldCompletion.complete();
    await first;
    expect(controller.busy, isFalse);
  });

  test('display state changes are observable to controller listeners', () {
    final controller = AiAnalysisWorkspaceController.forTest(ownerId: 'owner');
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.syncDisplayState(AiWorkspaceDisplayState.precheck);
    controller.syncDisplayState(AiWorkspaceDisplayState.results);

    expect(controller.displayState, AiWorkspaceDisplayState.results);
    expect(notifications, 2);
  });
}
