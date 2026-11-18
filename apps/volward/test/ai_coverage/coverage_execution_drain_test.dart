import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:volward/ai/ai_coverage_job_controller.dart';
import 'package:volward/ai/ai_coverage_service.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/cancel_token.dart';
import 'package:volward/ai/coverage_analyze_tree_batch.dart';
import 'package:volward/ai/coverage_engine.dart';
import 'package:volward/ai/coverage_job_isolate_host.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_job_worker.dart';
import 'package:volward/ai/coverage_models.dart';
import 'package:volward/ai/coverage_snapshot_reader.dart';
import 'package:volward/ai/coverage_verdict_store.dart';
import 'package:volward/ai/native_coverage_engine.dart';
import 'package:volward/ai/native_engine_lifetime.dart';
import 'package:volward/bridge/native_bridge.dart';
import 'package:volward/snapshot_cache.dart';

void main() {
  for (final control in ['markAppQuit', 'pause', 'cancel']) {
    for (final operation in ['start', 'resume', 'budget']) {
      test(
        'control-first $control rejects queued $operation on close',
        () async {
          final fixture = await _WorkerFixture.create();
          await fixture.startPaused();
          var controlCompleted = false;
          final stopping = fixture.control(control).then((value) {
            controlCompleted = true;
            return value;
          });
          await fixture.waitForCancellation();
          final b = _outcome(switch (operation) {
            'resume' => fixture.host.resume('B'),
            'budget' => fixture.host.raiseBudgetAndResume(
              snapshotId: 'B',
              budgetTokens: 2000,
              budgetCredits: 0,
            ),
            _ => fixture.host.start('B', budgetTokens: 1000, budgetCredits: 0),
          });
          // Let the host send B before its synchronous admission gate closes.
          await Future<void>.delayed(Duration.zero);
          var shutdownCompleted = false;
          final shutdown = fixture.host.beginShutdown();
          expect(identical(shutdown, fixture.host.beginShutdown()), isTrue);
          final observedShutdown = shutdown.then(
            (_) => shutdownCompleted = true,
          );
          final disposing = fixture.host.dispose();
          expect(identical(disposing, fixture.host.dispose()), isTrue);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          final early = {
            'control': controlCompleted,
            'shutdown': shutdownCompleted,
            'free': fixture.seen.contains('free'),
          };
          fixture.rescue.send('release');
          await observedShutdown.timeout(const Duration(seconds: 2));
          await disposing;
          final result = await stopping;
          expect(await b, isA<StateError>());
          expect(early, {'control': false, 'shutdown': false, 'free': false});
          if (control != 'markAppQuit') {
            expect((result as CoverageJobState).snapshotId, 'A');
          }
          expect(fixture.seen.where((event) => event.startsWith('build:')), [
            'build:A',
          ]);
          expect(await CoverageJobStateStore(fixture.dir).load('B'), isNull);
          expect(fixture.seen, contains('expand'));
          expect(
            fixture.seen.indexOf('expand'),
            lessThan(fixture.seen.indexOf('free')),
          );
          expect(fixture.seen.where((event) => event == 'free'), hasLength(1));
          fixture.expectReplies(control, errors: 1);
        },
      );
    }

    test(
      'pre-close $control completes after drain and permits next job',
      () async {
        final fixture = await _WorkerFixture.create();
        await fixture.startPaused();
        var completed = false;
        final stopping = fixture.control(control).then((value) {
          completed = true;
          return value;
        });
        await fixture.waitForCancellation();
        final early = completed;
        fixture.rescue.send('release');
        await stopping;
        final next = await fixture.host.start(
          'B',
          budgetTokens: 1000,
          budgetCredits: 0,
        );
        expect(next.snapshotId, 'B');
        await fixture.host.waitUntilIdle();
        expect(early, isFalse);
        expect(fixture.seen, contains('build:B'));
      },
    );
  }

  test(
    'control error stays correlated while other requests complete',
    () async {
      final fixture = await _WorkerFixture.create(failCancel: true);
      await fixture.startPaused();
      final pause = fixture.control('pause');
      final quit = fixture.control('markAppQuit');
      final idle = fixture.host.waitUntilIdle();
      final cancel = _outcome(fixture.host.cancel('bad'));
      await fixture.waitForCancellation();
      fixture.rescue.send('release');
      expect((await pause as CoverageJobState).snapshotId, 'A');
      await quit;
      await idle;
      expect(
        await cancel,
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('cancel load failed'),
        ),
      );
      expect((await fixture.host.pause()).snapshotId, 'A');
      await fixture.host.beginShutdown();
      await fixture.host.dispose();
      fixture.expectReplies('markAppQuit', errors: 1);
    },
  );

  test('fatal settles pending control replies and repeated shutdown', () async {
    final fixture = await _WorkerFixture.create();
    await fixture.startPaused();
    final pause = fixture.control('pause');
    final quit = fixture.control('markAppQuit');
    final cancel = fixture.control('cancel');
    final idle = _outcome(fixture.host.waitUntilIdle());
    await fixture.waitForCancellation();
    fixture.expectFatal = true;
    fixture.rescue.send('fatal');
    for (final pending in [pause, quit, cancel, idle]) {
      expect(
        await pending,
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('worker crashed'),
        ),
      );
    }
    final shutdown = fixture.host.beginShutdown();
    expect(identical(shutdown, fixture.host.beginShutdown()), isTrue);
    await expectLater(shutdown, throwsStateError);
    fixture.rescue.send('release');
    await expectLater(fixture.host.dispose(), throwsStateError);
  });

  test(
    'control-first cancel save preserves admission and disposal order',
    () async {
      final fixture = await _WorkerFixture.create(gateCancelSave: true);
      await fixture.startPaused();
      final paused = fixture.host.pause();
      fixture.rescue.send('release');
      await paused;
      final cancel = _outcome(fixture.host.cancel('A'));
      await (() async {
        while (!fixture.seen.contains('cancel-save')) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      })().timeout(const Duration(seconds: 1));
      final b = _outcome(
        fixture.host.start('B', budgetTokens: 1000, budgetCredits: 0),
      );
      await Future<void>.delayed(Duration.zero);
      var stopped = false;
      final shutdown = fixture.host.beginShutdown().then((_) => stopped = true);
      final disposing = fixture.host.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final early = {
        'shutdown': stopped,
        'free': fixture.seen.contains('free'),
      };
      fixture.rescue.send('releaseSave');
      expect(
        (await cancel as CoverageJobState).status,
        CoverageJobStatus.cancelled,
      );
      await shutdown;
      await disposing;
      expect(await b, isA<StateError>());
      expect(early, {'shutdown': false, 'free': false});
      expect(fixture.seen.where((e) => e.startsWith('build:')), ['build:A']);
    },
  );

  for (final first in ['markAppQuit', 'pause']) {
    for (final second in ['pause', 'cancel', 'markAppQuit']) {
      test('service dispatches $second while $first drains', () async {
        final fixture = await _WorkerFixture.create();
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        AiCoverageService.debugHostFactory = (_, _) => fixture.host;
        final service = (await AiCoverageService.tryCreate(
          session: _Reader(
            _engine(_TreeBridge((_) {})),
            catalogPath: 'fixture',
          ),
          provider: _ConcurrentProvider(),
        ))!;
        addTearDown(() async {
          fixture.rescue.send('release');
          service.dispose();
          await service.waitUntilIdle();
          debugDefaultTargetPlatformOverride = null;
          AiCoverageService.debugHostFactory = null;
        });
        final paused = service.states.firstWhere(
          (s) => s.status == CoverageJobStatus.paused,
        );
        await service.start('A', budgetTokens: 1000, budgetCredits: 0);
        await paused;
        Future<Object?> control(String name) => _outcome(switch (name) {
          'pause' => service.pause(),
          'cancel' => service.cancel('A'),
          _ => service.markAppQuit(),
        });
        final a = control(first);
        await fixture.waitForCancellation();
        final b = control(second);
        // The relay observes the command entering the production worker loop.
        final expectedCount = first == second ? 2 : 1;
        var reached = false;
        try {
          await (() async {
            while (fixture.seen.where((e) => e == 'command:$second').length <
                expectedCount) {
              await Future<void>.delayed(const Duration(milliseconds: 1));
            }
          })().timeout(const Duration(milliseconds: 300));
          reached = true;
        } on TimeoutException {
          // Release before asserting so the old implementation can clean up.
        }
        fixture.rescue.send('release');
        final firstResult = await a;
        final secondResult = await b;
        expect(
          reached,
          isTrue,
          reason: '$second must reach the worker before drain',
        );
        expect(firstResult, isNot(isA<Error>()));
        expect(secondResult, isNot(isA<Error>()));
      });
    }
  }

  for (final fatal in [false, true]) {
    test(
      'service settles controls and queued jobs on ${fatal ? 'fatal' : 'close'}',
      () async {
        final fixture = await _WorkerFixture.create();
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        AiCoverageService.debugHostFactory = (_, _) => fixture.host;
        final service = (await AiCoverageService.tryCreate(
          session: _Reader(
            _engine(_TreeBridge((_) {})),
            catalogPath: 'fixture',
          ),
          provider: _ConcurrentProvider(),
        ))!;
        addTearDown(() async {
          fixture.rescue.send('release');
          service.dispose();
          if (fatal) {
            await expectLater(service.waitUntilIdle(), throwsStateError);
          } else {
            await service.waitUntilIdle();
          }
          debugDefaultTargetPlatformOverride = null;
          AiCoverageService.debugHostFactory = null;
        });
        final paused = service.states.firstWhere(
          (s) => s.status == CoverageJobStatus.paused,
        );
        await service.start('A', budgetTokens: 1000, budgetCredits: 0);
        await paused;
        final quit = _outcome(service.markAppQuit());
        await fixture.waitForCancellation();
        final pause = _outcome(service.pause());
        final cancel = _outcome(service.cancel('A'));
        final b = _queue(service, 'start', 'B');
        final c = _queue(service, 'start', 'C');
        await (() async {
          while (!fixture.seen.contains('command:cancel')) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        })().timeout(const Duration(seconds: 2));
        if (fatal) {
          fixture.expectFatal = true;
          fixture.rescue.send('fatal');
          await quit;
        }
        service.dispose();
        fixture.rescue.send('release');
        final results = await Future.wait([quit, pause, cancel, b, c]);
        if (fatal) {
          await expectLater(
            service.waitUntilIdle().timeout(const Duration(seconds: 2)),
            throwsStateError,
          );
        } else {
          await service.waitUntilIdle().timeout(const Duration(seconds: 2));
        }
        if (fatal) {
          expect(results.take(3), everyElement(isA<StateError>()));
        } else {
          expect(results.take(3), everyElement(isNot(isA<Error>())));
          expect(fixture.seen.where((e) => e == 'free'), hasLength(1));
        }
        expect(results.skip(3), everyElement(isA<StateError>()));
        expect(fixture.seen.where((e) => e.startsWith('build:')), ['build:A']);
      },
    );
  }

  test(
    'service correlates control error without blocking later controls',
    () async {
      final fixture = await _WorkerFixture.create(failCancel: true);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      AiCoverageService.debugHostFactory = (_, _) => fixture.host;
      final service = (await AiCoverageService.tryCreate(
        session: _Reader(_engine(_TreeBridge((_) {})), catalogPath: 'fixture'),
        provider: _ConcurrentProvider(),
      ))!;
      addTearDown(() async {
        fixture.rescue.send('release');
        service.dispose();
        await service.waitUntilIdle();
        debugDefaultTargetPlatformOverride = null;
        AiCoverageService.debugHostFactory = null;
      });
      final paused = service.states.firstWhere(
        (s) => s.status == CoverageJobStatus.paused,
      );
      await service.start('A', budgetTokens: 1000, budgetCredits: 0);
      await paused;
      final quit = _outcome(service.markAppQuit());
      await fixture.waitForCancellation();
      final bad = _outcome(service.cancel('bad'));
      final pause = _outcome(service.pause());
      fixture.rescue.send('release');
      expect(await quit, isNull);
      expect(
        await bad,
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('cancel load failed'),
        ),
      );
      expect(await pause, isA<CoverageJobState>());
      expect(await service.pause(), isA<CoverageJobState>());
    },
  );

  test('pause keeps its manual reason when quit and shutdown arrive', () async {
    final fixture = await _WorkerFixture.create(gateRunning: true);
    await fixture.host.start('A', budgetTokens: 1000, budgetCredits: 0);
    await (() async {
      while (!fixture.seen.contains('provider-entered')) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    })().timeout(const Duration(seconds: 2));
    final pause = fixture.host.pause();
    await fixture.waitForCancellation();
    final quit = fixture.host.markAppQuit();
    await (() async {
      while (!fixture.seen.contains('command:markAppQuit')) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    })().timeout(const Duration(seconds: 2));
    final shutdown = fixture.host.beginShutdown();
    await (() async {
      while (!fixture.seen.contains('command:shutdown')) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    })().timeout(const Duration(seconds: 2));
    fixture.rescue.send('release');
    await pause;
    await quit;
    await shutdown;
    expect(
      (await CoverageJobStateStore(fixture.dir).load('A'))?.pauseReason,
      CoveragePauseReason.manual,
    );
  });

  test('dispose and quit stay pending while execution cannot drain', () async {
    final fixture = await _WorkerFixture.create();
    await fixture.startPaused();
    var quitDone = false;
    var disposeDone = false;
    final quit = _outcome(fixture.host.markAppQuit()).then((value) {
      quitDone = true;
      return value;
    });
    await fixture.waitForCancellation();
    final dispose = fixture.host.dispose().then((_) => disposeDone = true);
    await Future<void>.delayed(const Duration(milliseconds: 3200));
    final early = [quitDone, disposeDone, fixture.seen.contains('free')];
    fixture.rescue.send('release');
    await quit;
    await dispose;
    expect(early, [false, false, false]);
    expect(fixture.seen.where((event) => event == 'free'), hasLength(1));
  });

  // A failed tree batch publishes paused while its successful sibling still
  // owns work that must expand a native tree node after its provider returns.
  for (final operation in ['start', 'resume', 'budget']) {
    test('paused execution rejects queued main $operation on close', () async {
      final dir = await Directory.systemTemp.createTemp('execution-drain-');
      SnapshotCache.cacheDirForTest = dir;
      final events = <String>[];
      final bridge = _TreeBridge(events.add);
      final provider = _ConcurrentProvider();
      final lifetime = NativeEngineLifetime();
      final service = (await AiCoverageService.tryCreate(
        session: _Reader(_engine(bridge, lifetime: lifetime)),
        provider: provider,
        runJobOnMainIsolate: true,
      ))!;
      addTearDown(() async {
        provider.releaseSibling();
        service.dispose();
        await service.waitUntilIdle();
        SnapshotCache.cacheDirForTest = null;
        await dir.delete(recursive: true);
      });
      final paused = service.states.firstWhere(
        (state) => state.status == CoverageJobStatus.paused,
      );
      await service.start('A', budgetTokens: 1000, budgetCredits: 0);
      await paused;
      expect(provider.calls, 2);
      expect(
        (await CoverageJobStateStore(dir).load('A'))?.status,
        CoverageJobStatus.paused,
      );
      final b = _queue(service, operation, 'B');
      final c = _queue(service, operation, 'C');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      lifetime.close(() => bridge.freeEngine(Pointer.fromAddress(123)));
      service.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final cancelledBeforeRelease = provider.token!.isCancelled;
      final freedBeforeRelease = events.contains('free');
      provider.releaseSibling();
      await service.waitUntilIdle().timeout(const Duration(seconds: 2));
      expect(await b, isA<StateError>());
      expect(await c, isA<StateError>());
      expect(cancelledBeforeRelease, isTrue);
      expect(freedBeforeRelease, isFalse);
      expect(events.where((event) => event.startsWith('build:')), ['build:A']);
      expect(events, contains('expand'));
      expect(events.indexOf('expand'), lessThan(events.indexOf('free')));
      expect(events.where((event) => event == 'free'), hasLength(1));
      expect(await CoverageJobStateStore(dir).load('B'), isNull);
      expect(await CoverageJobStateStore(dir).load('C'), isNull);
    });
  }

  for (final operation in [null, 'start', 'resume', 'budget', 'cancel']) {
    test(
      'paused execution worker shutdown drains ${operation ?? 'without idle waiter'}',
      () async {
        final dir = await Directory.systemTemp.createTemp('worker-drain-');
        final outside = ReceivePort();
        final seen = <String>[];
        final rescueReady = Completer<SendPort>();
        final subscription = outside.listen((event) {
          if (event is SendPort) {
            rescueReady.complete(event);
          } else {
            seen.add(event as String);
          }
        });
        final host = CoverageJobIsolateHost(
          catalogPath: 'fixture',
          workerConfig: {'outside': outside.sendPort, 'directory': dir.path},
          workerEntryPoint: _realControllerWorker,
        );
        await host.ensureStarted();
        final rescue = await rescueReady.future;
        addTearDown(() async {
          rescue.send('release');
          await host.dispose();
          await subscription.cancel();
          outside.close();
          await dir.delete(recursive: true);
        });
        final paused = host.states.firstWhere(
          (state) => state.status == CoverageJobStatus.paused,
        );
        await host.start('A', budgetTokens: 1000, budgetCredits: 0);
        await paused;
        expect(
          (await CoverageJobStateStore(dir).load('A'))?.status,
          CoverageJobStatus.paused,
        );
        Future<Object>? pending;
        if (operation != null) {
          final command = switch (operation) {
            'resume' => host.resume('B'),
            'budget' => host.raiseBudgetAndResume(
              snapshotId: 'B',
              budgetTokens: 2000,
              budgetCredits: 0,
            ),
            'cancel' => host.cancel('B'),
            _ => host.start('B', budgetTokens: 1000, budgetCredits: 0),
          };
          pending = command.then<Object>(
            (value) => value,
            onError: (Object error) => error,
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        var acknowledged = false;
        final shutdown = host.beginShutdown().then((_) => acknowledged = true);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final earlyAck = acknowledged;
        // No admitted idle waiter is needed to keep the worker alive.
        final disposing = host.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final earlyFree = seen.contains('free');
        rescue.send('release');
        await shutdown.timeout(const Duration(seconds: 2));
        await disposing;
        await Future<void>.delayed(Duration.zero);
        if (pending != null) expect(await pending, isA<StateError>());
        expect(
          {'shutdownAck': earlyAck, 'nativeFree': earlyFree},
          {'shutdownAck': false, 'nativeFree': false},
        );
        expect(seen, contains('cancelled:true'));
        expect(seen.where((event) => event.startsWith('build:')), ['build:A']);
        expect(seen.indexOf('expand'), greaterThanOrEqualTo(0));
        expect(seen.indexOf('expand'), lessThan(seen.indexOf('free')));
        expect(seen.where((event) => event == 'free'), hasLength(1));
      },
    );
  }

  test('paused execution service keeps pause reachable behind B', () async {
    final dir = await Directory.systemTemp.createTemp('service-worker-drain-');
    final outside = ReceivePort();
    final rescueReady = Completer<SendPort>();
    final cancellation = Completer<bool>();
    final subscription = outside.listen((event) {
      if (event is SendPort) rescueReady.complete(event);
      if (event is String &&
          event.startsWith('cancelled:') &&
          !cancellation.isCompleted) {
        cancellation.complete(event == 'cancelled:true');
      }
    });
    final host = CoverageJobIsolateHost(
      catalogPath: 'fixture',
      workerConfig: {'outside': outside.sendPort, 'directory': dir.path},
      workerEntryPoint: _realControllerWorker,
    );
    await host.ensureStarted();
    final rescue = await rescueReady.future;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    AiCoverageService.debugHostFactory = (_, _) => host;
    final service = (await AiCoverageService.tryCreate(
      session: _Reader(_engine(_TreeBridge((_) {})), catalogPath: 'fixture'),
      provider: _ConcurrentProvider(),
    ))!;
    addTearDown(() async {
      rescue.send('release');
      service.dispose();
      await service.waitUntilIdle();
      await subscription.cancel();
      outside.close();
      debugDefaultTargetPlatformOverride = null;
      AiCoverageService.debugHostFactory = null;
      await dir.delete(recursive: true);
    });
    final paused = service.states.firstWhere(
      (state) => state.status == CoverageJobStatus.paused,
    );
    await service.start('A', budgetTokens: 1000, budgetCredits: 0);
    await paused;
    final b = _queue(service, 'start', 'B');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final pause = service.pause().then<Object>(
      (value) => value,
      onError: (Object error) => error,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    rescue.send('query');
    final cancelledBeforeShutdown = await cancellation.future.timeout(
      const Duration(seconds: 1),
    );
    service.dispose();
    rescue.send('release');
    await service.waitUntilIdle().timeout(const Duration(seconds: 2));
    await pause;
    expect(await b, isA<StateError>());
    expect(cancelledBeforeShutdown, isTrue);
  });

  // Terminal state is assigned before its asynchronous save finishes. Even
  // without sibling batches it is not an execution-completion signal.
  for (final appQuit in [false, true]) {
    test(
      'quit drains terminal ${appQuit ? 'appQuit' : 'completed'} save',
      () async {
        final dir = await Directory.systemTemp.createTemp('terminal-drain-');
        final store = _TerminalStore(dir);
        final token = CancelToken();
        final bridge = _TreeBridge((_) {}, empty: true);
        final controller = _controller(
          _engine(bridge),
          store,
          _ConcurrentProvider(),
          token,
        );
        addTearDown(() async {
          if (!store.release.isCompleted) store.release.complete();
          await controller.waitUntilIdle();
          controller.dispose();
          await dir.delete(recursive: true);
        });
        await controller.start(
          'A',
          budgetTokens: 1000,
          budgetCredits: 0,
          detachRun: true,
        );
        Future<void>? firstQuit;
        if (appQuit) firstQuit = controller.markAppQuit();
        await store.entered.future.timeout(const Duration(seconds: 2));
        expect(
          controller.state?.status,
          appQuit ? CoverageJobStatus.paused : CoverageJobStatus.completed,
        );
        if (appQuit) {
          expect(controller.state?.pauseReason, CoveragePauseReason.appQuit);
        }
        var drained = false;
        final quit = controller.markAppQuit().then((_) => drained = true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final earlyDrain = drained;
        store.release.complete();
        await quit;
        await firstQuit;
        await controller.waitUntilIdle();
        expect(earlyDrain, isFalse);
      },
    );
  }
}

Future<Object> _queue(AiCoverageService service, String operation, String id) {
  final command = switch (operation) {
    'resume' => service.resume(id),
    'budget' => service.raiseBudgetAndResume(
      snapshotId: id,
      budgetTokens: 2000,
      budgetCredits: 0,
    ),
    _ => service.start(id, budgetTokens: 1000, budgetCredits: 0),
  };
  return command.then<Object>(
    (value) => value,
    onError: (Object error) => error,
  );
}

NativeCoverageEngine _engine(
  _TreeBridge bridge, {
  NativeEngineLifetime? lifetime,
}) => NativeCoverageEngine(
  bridge: bridge,
  engine: Pointer.fromAddress(123),
  offloadHeavyCalls: false,
  lifetime: lifetime,
);

CoverageJobController _controller(
  NativeCoverageEngine engine,
  CoverageJobStateStore store,
  _ConcurrentProvider provider,
  CancelToken token,
) => CoverageJobController(
  engine: engine,
  stateStore: store,
  verdictStore: CoverageVerdictStore(store.directory),
  analyzeBatch: (_) async => const BatchOutcome(
    usage: BatchUsage(tokens: 0, credits: 0),
    verdicts: [],
  ),
  analyzeTreeBatch: createCoverageAnalyzeTreeBatch(
    provider: provider,
    cancelToken: token,
  ),
  preferTreeCoveragePlan: true,
  cancelToken: token,
);

void _realControllerWorker(List<dynamic> args) async {
  final main = args[0] as SendPort;
  final config = args[1] as Map;
  final outside = config['outside'] as SendPort;
  final bridge = _TreeBridge(outside.send);
  final provider = _ConcurrentProvider(
    gateRunning: config['gateRunning'] == true,
    onEnter: () => outside.send('provider-entered'),
  );
  final token = CancelToken();
  final directory = Directory(config['directory'] as String);
  final store = config['gateCancelSave'] == true
      ? _CancelSaveStore(directory, outside.send)
      : config['failCancel'] == true
      ? _CancelErrorStore(directory)
      : CoverageJobStateStore(directory);
  final controller = _controller(_engine(bridge), store, provider, token);
  controller.states.listen(
    (state) => main.send({'type': 'state', 'state': state.toJson()}),
  );
  final rescue = ReceivePort();
  rescue.listen((message) {
    if (message == 'fatal') {
      main.send({'type': 'error', 'message': 'worker crashed'});
      return;
    }
    outside.send('cancelled:${token.isCancelled}');
    if (message == 'release') provider.releaseSibling();
    if (message == 'releaseSave' &&
        store is _CancelSaveStore &&
        !store.release.isCompleted) {
      store.release.complete();
    }
  });
  outside.send(rescue.sendPort);
  final control = ReceivePort();
  final wire = ReceivePort();
  wire.listen((message) {
    outside.send('command:${(message as Map)['cmd']}');
    control.sendPort.send(message);
  });
  main.send({'type': 'ready', 'controlPort': wire.sendPort});
  final replies = ReceivePort();
  replies.listen((reply) {
    final message = reply as Map;
    outside.send(
      'reply:${message['type']}:${message['cmd']}:${message['requestId']}',
    );
    main.send(reply);
    if (message['type'] == 'ack' && message['cmd'] == 'dispose') {
      replies.close();
    }
  });
  await runCoverageWorkerCommands(
    controlPort: control,
    mainPort: replies.sendPort,
    controller: controller,
    setResumePlanCache: (_) {},
    onDispose: () {
      controller.dispose();
      bridge.freeEngine(Pointer.fromAddress(123));
      rescue.close();
      wire.close();
    },
  );
}

Future<Object?> _outcome(Future<dynamic> future) =>
    future.then<Object?>((value) => value, onError: (Object error) => error);

class _WorkerFixture {
  _WorkerFixture(this.host, this.dir, this.rescue, this.seen);
  final CoverageJobIsolateHost host;
  final Directory dir;
  final SendPort rescue;
  final List<String> seen;
  bool expectFatal = false;

  static Future<_WorkerFixture> create({
    bool failCancel = false,
    bool gateCancelSave = false,
    bool gateRunning = false,
  }) async {
    final dir = await Directory.systemTemp.createTemp('control-drain-');
    final outside = ReceivePort();
    final ready = Completer<SendPort>();
    final seen = <String>[];
    final subscription = outside.listen((event) {
      if (event is SendPort) {
        ready.complete(event);
      } else {
        seen.add(event as String);
      }
    });
    final host = CoverageJobIsolateHost(
      catalogPath: 'fixture',
      workerConfig: {
        'outside': outside.sendPort,
        'directory': dir.path,
        'failCancel': failCancel,
        'gateCancelSave': gateCancelSave,
        'gateRunning': gateRunning,
      },
      workerEntryPoint: _realControllerWorker,
    );
    await host.ensureStarted();
    final rescue = await ready.future;
    final fixture = _WorkerFixture(host, dir, rescue, seen);
    addTearDown(() async {
      rescue.send('release');
      if (gateCancelSave) rescue.send('releaseSave');
      if (fixture.expectFatal) {
        await expectLater(host.dispose(), throwsStateError);
      } else {
        await host.dispose();
      }
      await subscription.cancel();
      outside.close();
      await dir.delete(recursive: true);
    });
    return fixture;
  }

  Future<void> startPaused() async {
    final paused = host.states.firstWhere(
      (s) => s.status == CoverageJobStatus.paused,
    );
    await host.start('A', budgetTokens: 1000, budgetCredits: 0);
    await paused;
    expect(
      (await CoverageJobStateStore(dir).load('A'))?.status,
      CoverageJobStatus.paused,
    );
  }

  Future<Object?> control(String command) => _outcome(switch (command) {
    'markAppQuit' => host.markAppQuit(),
    'cancel' => host.cancel('A'),
    _ => host.pause(),
  });

  Future<void> waitForCancellation() async {
    await (() async {
      while (!seen.contains('cancelled:true')) {
        rescue.send('query');
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    })().timeout(const Duration(seconds: 1));
  }

  void expectReplies(String control, {required int errors}) {
    final replies = seen.where((e) => e.startsWith('reply:')).toList();
    expect(
      replies.where((e) => e.startsWith('reply:ack:$control:')),
      hasLength(1),
    );
    expect(
      replies.where((e) => e.startsWith('reply:error:')),
      hasLength(errors),
    );
    // Every production reply belongs to a unique host request, including quit.
    final ids = replies.map((e) => e.split(':').last).toList();
    expect(ids, isNot(contains('null')));
    expect(ids.toSet(), hasLength(ids.length));
  }
}

class _CancelErrorStore extends CoverageJobStateStore {
  _CancelErrorStore(super.directory);
  @override
  Future<CoverageJobState?> load(String snapshotId) async {
    if (snapshotId == 'bad') throw StateError('cancel load failed');
    return super.load(snapshotId);
  }
}

class _CancelSaveStore extends CoverageJobStateStore {
  _CancelSaveStore(super.directory, this.event);
  final void Function(String) event;
  final release = Completer<void>();
  @override
  Future<void> save(CoverageJobState state) async {
    await super.save(state);
    if (state.status == CoverageJobStatus.cancelled) {
      event('cancel-save');
      await release.future;
    }
  }
}

class _TerminalStore extends CoverageJobStateStore {
  _TerminalStore(super.directory);
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> save(CoverageJobState state) async {
    await super.save(state);
    if (state.status == CoverageJobStatus.completed ||
        state.pauseReason == CoveragePauseReason.appQuit) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
  }
}

class _ConcurrentProvider implements AiProvider, TreeAiProvider {
  _ConcurrentProvider({this.gateRunning = false, this.onEnter});
  final bool gateRunning;
  final void Function()? onEnter;
  final siblingEntered = Completer<void>();
  final release = Completer<void>();
  CancelToken? token;
  int calls = 0;
  void releaseSibling() {
    if (!release.isCompleted) release.complete();
  }

  @override
  Future<AnalyzeResult> analyzeTreeNodes(
    List<CoverageTreeNode> nodes, {
    CancelToken? cancelToken,
  }) async {
    token = cancelToken;
    calls++;
    onEnter?.call();
    if (gateRunning) {
      await release.future;
      return AnalyzeResult(
        verdicts: nodes
            .map(
              (node) => AiVerdict(
                path: node.path,
                verdict: 'drill_down',
                confidence: 'high',
                reason: 'test',
              ),
            )
            .toList(),
      );
    }
    if (nodes.first.path == '/node0') {
      await siblingEntered.future;
      throw StateError('first tree batch failed');
    }
    if (!siblingEntered.isCompleted) siblingEntered.complete();
    await release.future;
    // Already-started provider work may complete successfully after cancel.
    // The production controller then has a native expansion left to perform.
    return AnalyzeResult(
      verdicts: nodes
          .map(
            (node) => AiVerdict(
              path: node.path,
              verdict: 'drill_down',
              confidence: 'high',
              reason: 'test',
            ),
          )
          .toList(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Reader implements CoverageSnapshotReader {
  _Reader(this.coverageEngine, {this.catalogPath});
  final String? catalogPath;
  @override
  final CoverageEngine coverageEngine;
  @override
  bool get hasAiTreeCoverageApi => true;
  @override
  bool get hasIndexApi => false;
  @override
  String? get currentCoverageSnapshotId => 'A';
  @override
  Future<String?> catalogIndexPathForAiCoverage(String snapshotId) async =>
      catalogPath;
}

class _TreeBridge implements VolwardNativeBridge {
  _TreeBridge(this.event, {this.empty = false});
  final void Function(String) event;
  final bool empty;
  bool freed = false;
  @override
  bool get hasAsyncAiCoveragePlanApi => false;
  @override
  String? buildAiTreeCoveragePlanJson(Pointer<Void> engine, String snapshotId) {
    event('build:$snapshotId');
    return jsonEncode({
      'snapshot_id': snapshotId,
      'root_path': '/',
      'plan_version': 3,
      'seed_node_count': empty ? 0 : 81,
      'total_unclassified': empty ? 0 : 81,
    });
  }

  @override
  String? nextAiTreeCoveragePageJson(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 200,
  }) => jsonEncode({
    'snapshot_id': snapshotId,
    'plan_version': planVersion,
    'next_cursor': null,
    'nodes': empty
        ? []
        : List.generate(
            81,
            (i) => {
              'path': '/node$i',
              'size_bytes': 1,
              'file_count': 1,
              'subdir_count': 0,
              'role': 'unknown',
            },
          ),
  });
  @override
  String? nextAiTailCoveragePageJson(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 200,
  }) => jsonEncode({
    'snapshot_id': snapshotId,
    'plan_version': planVersion,
    'next_cursor': null,
    'rows': [],
  });
  @override
  String? listLocalCoverageVerdictsJson(
    Pointer<Void> engine,
    String snapshotId,
    int cursor, {
    int limit = 5000,
  }) => '{"verdicts":[],"next_cursor":null}';
  @override
  String? expandAiTreeNodeJson(
    Pointer<Void> engine,
    String snapshotId,
    String dirPath,
  ) {
    if (freed) throw StateError('native access after free');
    event('expand');
    return '{"nodes":[]}';
  }

  @override
  void freeEngine(Pointer<Void> engine) {
    freed = true;
    event('free');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
