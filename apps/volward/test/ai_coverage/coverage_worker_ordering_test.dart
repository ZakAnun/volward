import 'dart:async';
import 'dart:isolate';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:volward/ai/ai_coverage_service.dart';
import 'package:volward/ai/ai_coverage_coordinator.dart';
import 'package:volward/volward_session.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/coverage_engine.dart';
import 'package:volward/ai/coverage_snapshot_reader.dart';
import 'package:volward/ai/native_coverage_engine.dart';
import 'package:volward/ai/native_engine_lifetime.dart';
import 'package:volward/bridge/native_bridge.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_coverage_job_controller.dart';
import 'package:volward/ai/coverage_job_isolate_host.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_job_worker.dart';
import 'package:volward/core/session/engine_host.dart';

void _worker(List<dynamic> args) {
  final main = args[0] as SendPort;
  final config = args[1] as Map;
  final outside = config['outside'] as SendPort;
  final rescue = ReceivePort();
  final commands = ReceivePort();
  final controller = _FakeController(
    main,
    config['events'] as SendPort?,
    failQuit: config['failQuit'] == true,
    gateQuit: config['gateQuit'] == true,
  );
  rescue.listen((message) {
    if (message == 'releaseQuit') {
      controller.releaseQuit();
      return;
    }
    if (message == 'exit') Isolate.exit();
    if (message == 'fatal') {
      main.send({'type': 'error', 'message': 'worker crashed'});
    } else {
      controller.stop();
    }
  });
  outside.send(rescue.sendPort);
  main.send({'type': 'ready', 'controlPort': commands.sendPort});
  controller.emit();
  unawaited(
    runCoverageWorkerCommands(
      controlPort: commands,
      mainPort: main,
      controller: controller,
      setResumePlanCache: (_) {},
      onDispose: () {
        config['events']?.send('dispose');
        rescue.close();
        if (config['failDispose'] == true) {
          throw StateError('native free failed');
        }
      },
    ),
  );
}

class _FakeController implements CoverageJobController {
  _FakeController(
    this.main,
    this.events, {
    this.failQuit = false,
    this.gateQuit = false,
  });
  @override
  bool get isRunning => running;
  final bool failQuit;
  final bool gateQuit;
  final quitGate = Completer<void>();
  void releaseQuit() {
    if (!quitGate.isCompleted) quitGate.complete();
  }

  final SendPort main;
  final SendPort? events;
  Completer<void> idle = Completer<void>();
  bool running = true;
  String snapshot = 'active';
  @override
  CoverageJobState? get state => stateFor(snapshot);
  CoverageJobState stateFor(String id, {String? status}) =>
      CoverageJobState.fromJson({
        'snapshot_id': id,
        'root_path': '/',
        'plan_version': 1,
        'status': status ?? (running ? 'running' : 'paused'),
      });
  void emit() =>
      main.send({'type': 'state', 'state': stateFor(snapshot).toJson()});
  void stop() {
    events?.send('stop:$snapshot');
    running = false;
    if (!idle.isCompleted) idle.complete();
    emit();
  }

  @override
  Future<void> waitUntilIdle() {
    events?.send('wait:$snapshot');
    return running ? idle.future : Future.value();
  }

  @override
  Future<CoverageJobState> pause() async {
    stop();
    return stateFor(snapshot);
  }

  @override
  Future<void> markAppQuit() async {
    if (failQuit) throw StateError('quit failed');
    if (gateQuit) {
      events?.send('quit-gated');
      await quitGate.future;
    }
    stop();
  }

  @override
  Future<CoverageJobState> cancel(String id) async {
    if (running && snapshot != id) await idle.future;
    events?.send('cancel:$id');
    if (snapshot == id) stop();
    return stateFor(id, status: 'cancelled');
  }

  @override
  Future<CoverageJobState> start(
    String id, {
    required int budgetTokens,
    required int budgetCredits,
    bool detachRun = false,
  }) async {
    if (running && snapshot != id) await idle.future;
    if (id == 'throws') throw StateError('start failed');
    events?.send('start:$id');
    snapshot = id;
    running = true;
    idle = Completer<void>();
    emit();
    return stateFor(id);
  }

  @override
  Future<CoverageJobState> resume(String id, {bool detachRun = false}) =>
      start(id, budgetTokens: 1, budgetCredits: 0, detachRun: detachRun);

  @override
  Future<CoverageJobState> raiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
    bool detachRun = false,
  }) => start(
    snapshotId,
    budgetTokens: budgetTokens,
    budgetCredits: budgetCredits,
    detachRun: detachRun,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'worker ownership helper disposes the engine after attach failure',
    () async {
      var freed = false;
      final host = EngineHost.forTest(
        engine: Pointer<Void>.fromAddress(1),
        freeEngine: () => freed = true,
      );

      await expectLater(
        runCoverageWorkerWithOwnedHost(
          engineHost: host,
          provider: () => null,
          body: () async => throw StateError('attach failed'),
        ),
        throwsStateError,
      );

      expect(freed, isTrue);
    },
  );

  for (final failQuit in [true, false]) {
    for (final servicePath in [false, true]) {
      test(
        '${servicePath ? 'service' : 'host'} disposal reports ${failQuit ? 'shutdown' : 'native free'} failure and cleans up',
        () async {
          final harness = await _ClosingHarness.create(
            failQuit: failQuit,
            failDispose: !failQuit,
          );
          harness.lifetime.close(() => harness.frees++);
          final Future<void> result;
          if (servicePath) {
            harness.service.dispose();
            result = harness.service.waitUntilIdle();
            expect(identical(result, harness.service.waitUntilIdle()), isTrue);
          } else {
            result = harness.host.dispose();
            expect(identical(result, harness.host.dispose()), isTrue);
          }
          final matcher = throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains(failQuit ? 'quit failed' : 'native free failed'),
            ),
          );
          await expectLater(result, matcher);
          await expectLater(result, matcher);
          expect(harness.host.started, isFalse);
          if (servicePath) expect(harness.frees, 1);
          await expectLater(harness.host.pause(), throwsStateError);
        },
      );
    }
  }

  test('service preserves shutdown error when release also fails', () async {
    final harness = await _ClosingHarness.create(failQuit: true);
    harness.lifetime.close(() {
      harness.frees++;
      throw StateError('release failed');
    });
    harness.service.dispose();
    // The synchronous dispose caller may attach a waiter later.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await expectLater(
      harness.service.waitUntilIdle(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('quit failed'),
        ),
      ),
    );
    expect(harness.frees, 1);
    expect(harness.host.started, isFalse);
  });

  test(
    'coordinator detach reports worker cleanup failure after teardown',
    () async {
      final harness = await _ClosingHarness.create(failDispose: true);
      final coordinator = AiCoverageCoordinator.testing(
        isCoverageApiReady: (_) => true,
        resolveProvider: () async => null,
        serviceFactory:
            ({
              required session,
              required provider,
              resumePlanLoader,
              catalogSnapshotId,
            }) async => harness.service,
      );
      final session = VolwardSession.test();
      addTearDown(session.dispose);
      coordinator.rebind(session);
      expect(
        await coordinator.prepareService(_Provider()),
        same(harness.service),
      );
      harness.lifetime.close(() => harness.frees++);
      await expectLater(
        coordinator.detachAndDrain(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('native free failed'),
          ),
        ),
      );
      expect(harness.host.started, isFalse);
      expect(harness.frees, 1);
      expect(harness.seen.where((e) => e == 'dispose'), hasLength(1));
    },
  );

  for (final event in ['fatal', 'exit']) {
    test('host reports worker $event after shutdown and cleans up', () async {
      final outside = ReceivePort();
      final rescueFuture = outside.first;
      final events = ReceivePort();
      final seen = <String>[];
      final sub = events.listen((event) => seen.add(event as String));
      final host = CoverageJobIsolateHost(
        catalogPath: 'test',
        workerConfig: {'outside': outside.sendPort, 'events': events.sendPort},
        workerEntryPoint: _worker,
      );
      await host.ensureStarted();
      final rescue = await rescueFuture as SendPort;
      await host.beginShutdown();
      rescue.send(event);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final disposal = host.dispose();
      expect(identical(disposal, host.dispose()), isTrue);
      final result = await disposal
          .timeout(const Duration(milliseconds: 300))
          .then<Object?>((_) => null, onError: (Object error) => error);
      expect(
        result,
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains(event == 'fatal' ? 'worker crashed' : 'worker exited'),
        ),
      );
      expect(host.started, isFalse);
      expect(seen.where((e) => e == 'dispose'), isEmpty);
      await expectLater(disposal, throwsStateError);
      await sub.cancel();
      events.close();
      outside.close();
    });
  }

  for (final fireAndForget in [false, true]) {
    for (final fail in [true, false]) {
      test(
        'repeated coordinator detach shares ${fail ? 'failure' : 'success'} (${fireAndForget ? 'detach first' : 'two drains'})',
        () async {
          final harness = await _ClosingHarness.create(
            failDispose: fail,
            gateQuit: true,
          );
          final owner = AiCoverageCoordinator.testing(
            isCoverageApiReady: (_) => true,
            resolveProvider: () async => null,
            serviceFactory:
                ({
                  required session,
                  required provider,
                  resumePlanLoader,
                  catalogSnapshotId,
                }) async => harness.service,
          );
          final session = VolwardSession.test();
          addTearDown(session.dispose);
          owner.rebind(session);
          await owner.prepareService(_Provider());
          harness.lifetime.close(() => harness.frees++);
          Future<void>? first;
          if (fireAndForget) {
            owner.detach();
          } else {
            first = owner.detachAndDrain();
          }
          final firstResult = first?.then<Object?>(
            (_) => null,
            onError: (Object error) => error,
          );
          await (() async {
            while (!harness.seen.contains('quit-gated')) {
              await Future<void>.delayed(const Duration(milliseconds: 1));
            }
          })().timeout(const Duration(seconds: 2));
          final second = owner.detachAndDrain();
          final secondResult = second.then<Object?>(
            (_) => null,
            onError: (Object error) => error,
          );
          await Future<void>.delayed(Duration.zero);
          harness.rescue.send('releaseQuit');
          final results = [
            if (firstResult != null) await firstResult,
            await secondResult,
          ];
          if (fail) {
            expect(
              results,
              everyElement(
                isA<StateError>().having(
                  (e) => e.message,
                  'message',
                  contains('native free failed'),
                ),
              ),
            );
          } else {
            expect(results, everyElement(isNull));
          }
          expect(identical(second, owner.detachAndDrain()), isTrue);
          if (first != null) expect(identical(first, second), isTrue);
          expect(harness.host.started, isFalse);
          expect(harness.frees, 1);
          expect(harness.seen.where((e) => e == 'dispose'), hasLength(1));
        },
      );
    }
  }

  test(
    'new coordinator generation recovers while failed retirement is pending',
    () async {
      final old = await _ClosingHarness.create(
        failDispose: true,
        gateQuit: true,
      );
      final next = await _ClosingHarness.create();
      final previous = VolwardSession.test();
      final replacement = VolwardSession.test();
      addTearDown(previous.dispose);
      addTearDown(replacement.dispose);
      final owner = AiCoverageCoordinator.testing(
        isCoverageApiReady: (_) => true,
        resolveProvider: () async => null,
        serviceFactory:
            ({
              required session,
              required provider,
              resumePlanLoader,
              catalogSnapshotId,
            }) async =>
                identical(session, previous) ? old.service : next.service,
      );
      owner.rebind(previous);
      await owner.prepareService(_Provider());
      final retired = owner.detachAndDrain().then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      await (() async {
        while (!old.seen.contains('quit-gated')) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      })().timeout(const Duration(seconds: 2));
      owner.rebind(replacement);
      var prepared = false;
      final incoming = owner.prepareService(_Provider()).then((value) {
        prepared = true;
        return value;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(prepared, isFalse);
      old.rescue.send('releaseQuit');
      expect(
        await retired,
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('native free failed'),
        ),
      );
      expect(await incoming, same(next.service));
      await owner.detachAndDrain();
    },
  );

  test('normal quit error is correlated and leaves the host usable', () async {
    final harness = await _ClosingHarness.create(failQuit: true);
    await expectLater(
      harness.host.markAppQuit(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('quit failed'),
        ),
      ),
    );
    // A quit failure must not become a fatal worker error or consume this ACK.
    expect((await harness.host.pause()).snapshotId, 'active');
    expect(
      (await harness.host.cancel('active')).status,
      CoverageJobStatus.cancelled,
    );
  });

  test(
    'failed shutdown settles admitted waits before releasing the lease',
    () async {
      final harness = await _ClosingHarness.create(failQuit: true);
      final b = harness.run('start', 'B');
      final idle = harness.service.waitUntilIdle().then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      await harness.waitForWaits(2);
      harness.lifetime.close(() => harness.frees++);
      harness.service.dispose();
      await expectLater(
        harness.service.waitUntilIdle().timeout(const Duration(seconds: 1)),
        throwsStateError,
      );
      expect(await b, isA<StateError>());
      expect(await idle, isA<StateError>());
      expect(harness.frees, 1);
      expect(harness.host.started, isFalse);
    },
  );

  test(
    'correlated worker error preserves other requests and host usability',
    () async {
      final harness = await _ClosingHarness.create();
      final failed = harness.run('start', 'throws', direct: true);
      final queued = harness.run('resume', 'B', direct: true);
      await harness.waitForWaits(2);
      await harness.host.pause();
      expect(await failed, isA<StateError>());
      expect((await queued as CoverageJobState).snapshotId, 'B');
      final idle = harness.host.waitUntilIdle();
      await harness.host.cancel('B');
      await idle;
      expect(harness.seen.where((event) => event == 'start:B').length, 1);
      harness.service.dispose();
      await harness.service.waitUntilIdle();
    },
  );

  // The real host and worker loop must close admission before waking queued
  // work. Removing either service recheck or the worker close barrier restarts B.
  for (final operation in ['start', 'resume', 'budget']) {
    for (final direct in [false, true]) {
      test(
        'close rejects queued B and C $operation (${direct ? 'worker' : 'service'})',
        () async {
          final harness = await _ClosingHarness.create();
          final b = harness.run(operation, 'B', direct: direct);
          final c = harness.run(operation, 'C', direct: direct);
          await harness.waitForWaits(2);
          harness.lifetime.close(() => harness.frees++);
          harness.service.dispose();
          harness.service.dispose();
          await harness.service.waitUntilIdle().timeout(
            const Duration(seconds: 1),
          );
          expect(await b, isA<StateError>());
          expect(await c, isA<StateError>());
          expect(
            harness.seen.where((event) => event.startsWith('start:')),
            isEmpty,
          );
          expect(harness.seen, contains('stop:active'));
          expect(harness.frees, 1);
          expect(harness.host.started, isFalse);
          await expectLater(harness.service.resume('late'), throwsStateError);
        },
      );
    }
  }

  test('close drains an admitted idle waiter racing a fresh start', () async {
    final harness = await _ClosingHarness.create();
    final idle = harness.service.waitUntilIdle();
    await harness.waitForWaits(1);
    final b = harness.run('start', 'B');
    harness.lifetime.close(() => harness.frees++);
    harness.service.dispose();
    await harness.service.waitUntilIdle().timeout(const Duration(seconds: 1));
    await idle;
    expect(await b, isA<StateError>());
    expect(harness.seen.where((event) => event.startsWith('start:')), isEmpty);
    expect(harness.frees, 1);
  });

  test(
    'worker fatal settles queued work and repeated service disposal',
    () async {
      final harness = await _ClosingHarness.create();
      final b = harness.run('start', 'B', direct: true);
      final c = harness.run('resume', 'C');
      final idle = harness.service.waitUntilIdle().then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      await harness.waitForWaits(3);
      harness.rescue.send('fatal');
      expect(await b, isA<StateError>());
      expect(await c, isA<StateError>());
      expect(await idle, isA<StateError>());
      harness.lifetime.close(() => harness.frees++);
      harness.service.dispose();
      harness.service.dispose();
      await expectLater(
        harness.service.waitUntilIdle().timeout(const Duration(seconds: 1)),
        throwsStateError,
      );
      expect(harness.frees, 1);
      expect(harness.host.started, isFalse);
    },
  );

  for (final command in ['pause', 'cancel', 'quit']) {
    test('worker processes $command while idle wait is pending', () async {
      final outside = ReceivePort();
      final rescueFuture = outside.first;
      final host = CoverageJobIsolateHost(
        catalogPath: 'test',
        workerConfig: {'outside': outside.sendPort},
        workerEntryPoint: _worker,
      );
      final ready = host.states.firstWhere(
        (state) => state.status == CoverageJobStatus.running,
      );
      await host.ensureStarted();
      final rescue = await rescueFuture as SendPort;
      await ready;
      final waiting = host.waitUntilIdle();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final Future<dynamic> action = switch (command) {
        'quit' => host.markAppQuit(),
        'cancel' => host.cancel('active'),
        _ => host.pause(),
      };
      var progressed = true;
      try {
        await waiting.timeout(const Duration(milliseconds: 200));
      } on TimeoutException {
        progressed = false;
        rescue.send(null);
      }
      await action;
      await waiting;
      await host.dispose();
      outside.close();
      expect(progressed, isTrue);
    });
  }
  for (final cancel in [false, true]) {
    test(
      'direct host defers different-snapshot ${cancel ? 'cancel' : 'start'} without blocking pause',
      () async {
        final outside = ReceivePort();
        final rescueFuture = outside.first;
        final host = CoverageJobIsolateHost(
          catalogPath: 'test',
          workerConfig: {'outside': outside.sendPort},
          workerEntryPoint: _worker,
        );
        final ready = host.states.firstWhere(
          (state) => state.status == CoverageJobStatus.running,
        );
        await host.ensureStarted();
        final rescue = await rescueFuture as SendPort;
        await ready;
        final pending = cancel
            ? host.cancel('other')
            : host.start('other', budgetTokens: 1, budgetCredits: 0);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final pause = host.pause();
        var progressed = true;
        try {
          await pause.timeout(const Duration(milliseconds: 200));
        } on TimeoutException {
          progressed = false;
          rescue.send(null);
        }
        await pause;
        final result = await pending;
        expect(result.snapshotId, 'other');
        await host.dispose();
        outside.close();
        expect(progressed, isTrue);
      },
    );
  }

  test('uncorrelated worker failure completes pending idle wait', () async {
    final outside = ReceivePort();
    final rescueFuture = outside.first;
    final host = CoverageJobIsolateHost(
      catalogPath: 'test',
      workerConfig: {'outside': outside.sendPort},
      workerEntryPoint: _worker,
    );
    final ready = host.states.firstWhere(
      (state) => state.status == CoverageJobStatus.running,
    );
    await host.ensureStarted();
    final rescue = await rescueFuture as SendPort;
    await ready;
    final waiting = host.waitUntilIdle();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    rescue.send('fatal');
    await expectLater(
      waiting.timeout(const Duration(milliseconds: 200)),
      throwsStateError,
    );
    rescue.send(null);
    await expectLater(host.dispose(), throwsStateError);
    outside.close();
  });

  test('host correlates concurrent command and idle completions', () async {
    final outside = ReceivePort();
    final rescueFuture = outside.first;
    final host = CoverageJobIsolateHost(
      catalogPath: 'test',
      workerConfig: {'outside': outside.sendPort},
      workerEntryPoint: _worker,
    );
    final ready = host.states.firstWhere(
      (state) => state.status == CoverageJobStatus.running,
    );
    await host.ensureStarted();
    await rescueFuture;
    await ready;
    final idleA = host.waitUntilIdle();
    final idleB = host.waitUntilIdle();
    final pause = host.pause();
    final cancel = host.cancel('active');
    expect((await pause).status, CoverageJobStatus.paused);
    expect((await cancel).status, CoverageJobStatus.cancelled);
    await Future.wait([idleA, idleB]);
    await host.dispose();
    outside.close();
    await expectLater(host.pause(), throwsStateError);
  });

  for (final disposeEarly in [false, true]) {
    test(
      'real worker defers ${disposeEarly ? 'start and drains on dispose' : 'different-snapshot cancel while pause remains responsive'}',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final outside = ReceivePort();
        final events = ReceivePort();
        final seen = <String>[];
        final subscription = events.listen(
          (event) => seen.add(event as String),
        );
        final rescueFuture = outside.first;
        final host = CoverageJobIsolateHost(
          catalogPath: 'test',
          workerConfig: {
            'outside': outside.sendPort,
            'events': events.sendPort,
          },
          workerEntryPoint: _worker,
        );
        AiCoverageService.debugHostFactory = (_, __) => host;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          AiCoverageService.debugHostFactory = null;
        });
        final ready = host.states.firstWhere(
          (state) => state.status == CoverageJobStatus.running,
        );
        await host.ensureStarted();
        final rescue = await rescueFuture as SendPort;
        await ready;
        final lifetime = NativeEngineLifetime();
        var frees = 0;
        final reader = _Reader(
          NativeCoverageEngine(
            bridge: _Bridge(),
            engine: Pointer.fromAddress(1234),
            lifetime: lifetime,
          ),
        );
        final service = (await AiCoverageService.tryCreate(
          session: reader,
          provider: _Provider(),
        ))!;
        final pending =
            (disposeEarly
                    ? service.start('other', budgetTokens: 1, budgetCredits: 0)
                    : service.cancel('other'))
                .then<Object>(
                  (value) => value,
                  onError: (Object error) => error,
                );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (disposeEarly) {
          lifetime.close(() => frees++);
          service.dispose();
        }
        final control = disposeEarly
            ? service.waitUntilIdle()
            : service.pause();
        var progressed = true;
        try {
          await control.timeout(const Duration(milliseconds: 500));
        } on TimeoutException {
          progressed = false;
          rescue.send(null);
        }
        final result = await pending;
        if (!disposeEarly) {
          expect((result as CoverageJobState).snapshotId, 'other');
          expect(result.status, CoverageJobStatus.cancelled);
          lifetime.close(() => frees++);
          service.dispose();
          await service.waitUntilIdle();
        }
        await Future<void>.delayed(Duration.zero);
        expect(progressed, isTrue);
        expect(frees, 1);
        if (disposeEarly) {
          expect(result, isA<StateError>());
          expect(seen.where((event) => event == 'start:other'), isEmpty);
        } else {
          expect(seen, contains('cancel:other'));
        }
        await expectLater(service.pause(), throwsStateError);
        await subscription.cancel();
        events.close();
        outside.close();
      },
    );
  }
}

class _Reader implements CoverageSnapshotReader {
  _Reader(this.coverageEngine);
  @override
  final CoverageEngine coverageEngine;
  @override
  bool get hasAiTreeCoverageApi => false;
  @override
  bool get hasIndexApi => false;
  @override
  String? get currentCoverageSnapshotId => 'active';
  @override
  Future<String?> catalogIndexPathForAiCoverage(String snapshotId) async =>
      '/test';
}

class _Bridge implements VolwardNativeBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Provider implements AiProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ClosingHarness {
  _ClosingHarness(
    this.host,
    this.service,
    this.lifetime,
    this.rescue,
    this.seen,
  );
  final CoverageJobIsolateHost host;
  final AiCoverageService service;
  final NativeEngineLifetime lifetime;
  final SendPort rescue;
  final List<String> seen;
  int frees = 0;

  static Future<_ClosingHarness> create({
    bool failQuit = false,
    bool failDispose = false,
    bool gateQuit = false,
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final outside = ReceivePort();
    final rescueFuture = outside.first;
    final events = ReceivePort();
    final seen = <String>[];
    final subscription = events.listen((event) => seen.add(event as String));
    final host = CoverageJobIsolateHost(
      catalogPath: 'test',
      workerConfig: {
        'outside': outside.sendPort,
        'events': events.sendPort,
        'failQuit': failQuit,
        'failDispose': failDispose,
        'gateQuit': gateQuit,
      },
      workerEntryPoint: _worker,
    );
    AiCoverageService.debugHostFactory = (_, __) => host;
    final ready = host.states.firstWhere(
      (state) => state.status == CoverageJobStatus.running,
    );
    await host.ensureStarted();
    final rescue = await rescueFuture as SendPort;
    await ready;
    final lifetime = NativeEngineLifetime();
    final service = (await AiCoverageService.tryCreate(
      session: _Reader(
        NativeCoverageEngine(
          bridge: _Bridge(),
          engine: Pointer.fromAddress(1234),
          lifetime: lifetime,
        ),
      ),
      provider: _Provider(),
    ))!;
    addTearDown(() async {
      rescue.send('releaseQuit');
      rescue.send(null);
      try {
        await host.dispose();
      } catch (_) {}
      service.dispose();
      try {
        await service.waitUntilIdle();
      } catch (_) {}
      await subscription.cancel();
      events.close();
      outside.close();
      debugDefaultTargetPlatformOverride = null;
      AiCoverageService.debugHostFactory = null;
    });
    return _ClosingHarness(host, service, lifetime, rescue, seen);
  }

  Future<Object> run(String operation, String id, {bool direct = false}) {
    final Future<CoverageJobState> result;
    if (direct) {
      result = switch (operation) {
        'resume' => host.resume(id),
        'budget' => host.raiseBudgetAndResume(
          snapshotId: id,
          budgetTokens: 2,
          budgetCredits: 1,
        ),
        _ => host.start(id, budgetTokens: 1, budgetCredits: 0),
      };
    } else {
      result = switch (operation) {
        'resume' => service.resume(id),
        'budget' => service.raiseBudgetAndResume(
          snapshotId: id,
          budgetTokens: 2,
          budgetCredits: 1,
        ),
        _ => service.start(id, budgetTokens: 1, budgetCredits: 0),
      };
    }
    return result.then<Object>(
      (value) => value,
      onError: (Object error) => error,
    );
  }

  Future<void> waitForWaits(int count) async {
    await (() async {
      while (seen.where((event) => event == 'wait:active').length < count) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    })().timeout(const Duration(seconds: 1));
  }
}
