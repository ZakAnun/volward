import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:volward/ai/native_engine_lifetime.dart';
import 'package:volward/ai/ai_coverage_service.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/platform_ai_provider.dart';
import 'package:volward/ai/cancel_token.dart';
import 'package:volward/ai/ai_conclusion_synthesis.dart';
import 'package:volward/bridge/native_bridge.dart';
import 'package:volward/volward_session.dart';
import 'package:volward/snapshot_cache.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_models.dart';
import 'package:volward/ai/coverage_snapshot_reader.dart';
import 'package:volward/ai/coverage_engine.dart';
import 'package:volward/ai/coverage_job_isolate_host.dart';
import 'package:volward/infrastructure/bridge/engine_bridge.dart';
import 'package:volward/infrastructure/bridge/runtime/native_string.dart';

void main() {
  test('bridge facade preserves native engine lifecycle delegation', () {
    final bridge = _FacadeEngineBridge();
    final facade = VolwardNativeBridge.test(engine: bridge);
    final engine = facade.createEngine();

    facade.freeEngine(engine);

    expect(bridge.createdEngines, [engine]);
    expect(bridge.freedEngines, [engine]);
  });

  for (final operation in ['start', 'resume', 'budget']) {
    test('main controller close rejects queued B and C $operation', () async {
      final dir = await Directory.systemTemp.createTemp('coverage-close-');
      SnapshotCache.cacheDirForTest = dir;
      final bridge = _RunningBridge()..building = false;
      final provider = _BlockingProvider();
      final session = VolwardSession.test(
        nativeBridgeForTest: bridge,
        engineForTest: Pointer.fromAddress(143),
        offloadCoverageForTest: false,
      );
      final service = (await AiCoverageService.tryCreate(
        session: session,
        provider: provider,
        runJobOnMainIsolate: true,
      ))!;
      addTearDown(() async {
        if (!provider.release.isCompleted) provider.release.complete();
        service.dispose();
        await service.waitUntilIdle();
        SnapshotCache.cacheDirForTest = null;
        await dir.delete(recursive: true);
      });
      await service.start('snapshot', budgetTokens: 1000, budgetCredits: 0);
      await provider.entered.future;
      Future<Object> queue(String id) {
        final result = switch (operation) {
          'resume' => service.resume(id),
          'budget' => service.raiseBudgetAndResume(
            snapshotId: id,
            budgetTokens: 2000,
            budgetCredits: 0,
          ),
          _ => service.start(id, budgetTokens: 1000, budgetCredits: 0),
        };
        return result.then<Object>(
          (value) => value,
          onError: (Object error) => error,
        );
      }

      final b = queue('B');
      final c = queue('C');
      final idle = service.waitUntilIdle();
      await Future<void>.delayed(Duration.zero);
      var frees = 0;
      bridge.onFree = () => frees++;
      session.dispose();
      service.dispose();
      service.dispose();
      await Future<void>.delayed(Duration.zero);
      final stopped = provider.token!.isCancelled;
      expect(frees, 0);
      provider.release.complete();
      await service.waitUntilIdle().timeout(const Duration(seconds: 1));
      await idle;
      expect(await b, isA<StateError>());
      expect(await c, isA<StateError>());
      expect(stopped, isTrue);
      expect(provider.calls, 1);
      expect(service.state?.snapshotId, 'snapshot');
      expect(service.state?.pauseReason, CoveragePauseReason.appQuit);
      final persisted = await CoverageJobStateStore(dir).load('snapshot');
      expect(persisted?.pauseReason, CoveragePauseReason.appQuit);
      expect(frees, 1);
    });
  }

  test('close waits for guarded asynchronous work', () async {
    final lifetime = NativeEngineLifetime();
    final gate = Completer<void>();
    final work = lifetime.guard(() async => gate.future);
    var freed = false;
    lifetime.close(() => freed = true);
    expect(freed, isFalse);
    gate.complete();
    await work;
    expect(freed, isTrue);
    expect(() => lifetime.retain(), throwsStateError);
  });

  test('Session disposal waits for native plan polling', () async {
    final bridge = _NativeBridge();
    final session = VolwardSession.test(
      nativeBridgeForTest: bridge,
      engineForTest: Pointer.fromAddress(123),
      offloadCoverageForTest: false,
    );
    final plan = session.coverageEngine!.buildPlan('snapshot');
    session.dispose();
    expect(bridge.freed, isFalse);
    bridge.building = false;
    await plan;
    expect(bridge.freed, isTrue);
  });

  test('Session disposal waits for native verdict backfill', () async {
    final dir = await Directory.systemTemp.createTemp('coverage-backfill-');
    addTearDown(() => dir.delete(recursive: true));
    final bridge = _NativeBridge();
    final session = VolwardSession.test(
      nativeBridgeForTest: bridge,
      engineForTest: Pointer.fromAddress(124),
      offloadCoverageForTest: false,
    );
    final backfill = session.coverageEngine!.backfillLocalVerdictsToStore(
      'snapshot',
      dir.path,
    );
    expect(bridge.reads, 1);
    session.dispose();
    expect(bridge.freed, isFalse);
    expect(await backfill, 1);
    expect(bridge.freed, isTrue);
  });

  test(
    'Session engine remains alive until its coverage service retires',
    () async {
      final bridge = _NativeBridge();
      final session = VolwardSession.test(
        nativeBridgeForTest: bridge,
        engineForTest: Pointer.fromAddress(125),
        offloadCoverageForTest: false,
      );
      final service = await AiCoverageService.tryCreate(
        session: session,
        provider: _Provider(),
        runJobOnMainIsolate: true,
      );
      expect(service, isNotNull);
      session.dispose();
      expect(bridge.freed, isFalse);
      await service!.markAppQuit();
      await service.waitUntilIdle();
      service.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(bridge.freed, isTrue);
    },
  );

  test(
    'service disposal keeps engine until its running controller stops',
    () async {
      final dir = await Directory.systemTemp.createTemp('coverage-service-');
      SnapshotCache.cacheDirForTest = dir;
      addTearDown(() async {
        SnapshotCache.cacheDirForTest = null;
        await dir.delete(recursive: true);
      });
      final bridge = _NativeBridge();
      final session = VolwardSession.test(
        nativeBridgeForTest: bridge,
        engineForTest: Pointer.fromAddress(126),
        offloadCoverageForTest: false,
      );
      final service = (await AiCoverageService.tryCreate(
        session: session,
        provider: _Provider(),
        runJobOnMainIsolate: true,
      ))!;
      CoverageJobStatus? statusAtFree;
      bridge.onFree = () => statusAtFree = service.state?.status;
      await service.start('snapshot', budgetTokens: 1000, budgetCredits: 0);
      await bridge.polled.future;
      session.dispose();
      final stopping = service.markAppQuit();
      service.dispose();
      bridge.building = false;
      await stopping;
      for (var i = 0; i < 20 && !bridge.freed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(bridge.freed, isTrue);
      expect(statusAtFree, CoverageJobStatus.paused);
    },
  );

  test(
    'service disposal rejects a wallet-gated start and drains its lease',
    () async {
      final dir = await Directory.systemTemp.createTemp('coverage-start-');
      SnapshotCache.cacheDirForTest = dir;
      addTearDown(() async {
        SnapshotCache.cacheDirForTest = null;
        await dir.delete(recursive: true);
      });
      final bridge = _NativeBridge()..building = false;
      final provider = _DelayedProvider();
      final session = VolwardSession.test(
        nativeBridgeForTest: bridge,
        engineForTest: Pointer.fromAddress(127),
        offloadCoverageForTest: false,
      );
      final rootEngine = session.coverageEngine!;
      final service = (await AiCoverageService.tryCreate(
        session: session,
        provider: provider,
        resumePlanLoader: (snapshotId, job) async =>
            rootEngine.tryReadMaterializedPlanSummary(snapshotId, tree: false),
        runJobOnMainIsolate: true,
      ))!;
      final start = service.start(
        'snapshot',
        budgetTokens: 1000,
        budgetCredits: 1,
      );
      await provider.entered.future;
      session.dispose();
      Object? rootError;
      try {
        await rootEngine.buildPlan('snapshot');
      } catch (error) {
        rootError = error;
      }
      service.dispose();
      await Future<void>.delayed(Duration.zero);
      final freedDuringStart = bridge.freed;
      provider.release.complete();
      await expectLater(start, throwsStateError);
      await service.waitUntilIdle();
      for (var i = 0; i < 20 && !bridge.freed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(freedDuringStart, isFalse);
      expect(bridge.polled.isCompleted, isFalse);
      expect(bridge.freed, isTrue);
      expect(rootError, isA<StateError>());
      provider.dispose();
    },
  );

  for (final resume in [false, true]) {
    test(
      'background executing ${resume ? 'resume' : 'start'} drains before host disposal',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final host = _ControlledHost();
        AiCoverageService.debugHostFactory = (_, __) => host;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          AiCoverageService.debugHostFactory = null;
        });
        final bridge = _NativeBridge();
        final provider = _DelayedProvider();
        final session = VolwardSession.test(
          nativeBridgeForTest: bridge,
          engineForTest: Pointer.fromAddress(129),
          offloadCoverageForTest: false,
        );
        final service = (await AiCoverageService.tryCreate(
          session: _CatalogReader(session),
          provider: provider,
        ))!;
        final dispatch = resume
            ? service.resume('snapshot')
            : service.start('snapshot', budgetTokens: 1000, budgetCredits: 1);
        await provider.entered.future;
        provider.release.complete();
        await host.entered.future;
        session.dispose();
        service.dispose();
        await Future<void>.delayed(Duration.zero);
        final freedWhileWaiting = bridge.freed;
        expect(host.disposed, isFalse);
        expect(bridge.freed, isFalse);
        host.dispatchGate.complete();
        final result = await dispatch;
        expect(result.snapshotId, 'snapshot');
        expect(result.planVersion, 7);
        await host.idleEntered.future;
        expect(host.disposed, isFalse);
        expect(bridge.freed, isFalse);
        host.idleGate.complete();
        for (var i = 0; i < 20 && !bridge.freed; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(host.disposed, isTrue);
        expect(bridge.freed, isTrue);
        expect(freedWhileWaiting, isFalse);
        await expectLater(service.resume('snapshot'), throwsStateError);
        provider.dispose();
      },
    );
  }

  for (final cancel in [false, true]) {
    test(
      'disposed service rejects ${cancel ? 'cancel' : 'pause'} without host call',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final host = _ControlHost();
        AiCoverageService.debugHostFactory = (_, __) => host;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          AiCoverageService.debugHostFactory = null;
        });
        final bridge = _NativeBridge();
        final session = VolwardSession.test(
          nativeBridgeForTest: bridge,
          engineForTest: Pointer.fromAddress(140),
          offloadCoverageForTest: false,
        );
        final service = (await AiCoverageService.tryCreate(
          session: _CatalogReader(session),
          provider: _Provider(),
        ))!;
        session.dispose();
        service.dispose();
        final action = cancel ? service.cancel('snapshot') : service.pause();
        await expectLater(
          action.timeout(const Duration(milliseconds: 100)),
          throwsStateError,
        );
        expect(host.controls, 0);
        await expectLater(service.markAppQuit(), throwsStateError);
        await service.waitUntilIdle();
        expect(host.disposed, isTrue);
        expect(bridge.freed, isTrue);
      },
    );

    test(
      'wallet gated start and ${cancel ? 'cancel' : 'pause'} drain without overlapping host commands',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final host = _ControlHost();
        AiCoverageService.debugHostFactory = (_, __) => host;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          AiCoverageService.debugHostFactory = null;
        });
        final bridge = _NativeBridge();
        final provider = _DelayedProvider();
        final session = VolwardSession.test(
          nativeBridgeForTest: bridge,
          engineForTest: Pointer.fromAddress(141),
          offloadCoverageForTest: false,
        );
        var frees = 0;
        bridge.onFree = () => frees++;
        final service = (await AiCoverageService.tryCreate(
          session: _CatalogReader(session),
          provider: provider,
        ))!;
        final starting = service.start(
          'snapshot',
          budgetTokens: 1000,
          budgetCredits: 1,
        );
        await provider.entered.future;
        final control = cancel ? service.cancel('snapshot') : service.pause();
        await host.controlEntered.future;
        provider.release.complete();
        await Future<void>.delayed(Duration.zero);
        final overlapped = host.overlapped;
        session.dispose();
        service.dispose();
        expect(bridge.freed, isFalse);
        host.controlGate.complete();
        final controlResult = await control;
        await expectLater(starting, throwsStateError);
        expect(controlResult.planVersion, 8);
        await service.waitUntilIdle();
        expect(overlapped, isFalse);
        expect(host.disposed, isTrue);
        expect(frees, 1);
        provider.dispose();
      },
    );
  }

  test(
    'pause reaches running job while another snapshot waits to start',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final host = _BusyHost();
      AiCoverageService.debugHostFactory = (_, __) => host;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        AiCoverageService.debugHostFactory = null;
      });
      final session = VolwardSession.test(
        nativeBridgeForTest: _NativeBridge(),
        engineForTest: Pointer.fromAddress(142),
        offloadCoverageForTest: false,
      );
      final service = (await AiCoverageService.tryCreate(
        session: _CatalogReader(session),
        provider: _Provider(),
      ))!;
      final start = service.start('other', budgetTokens: 1, budgetCredits: 0);
      await Future<void>.delayed(Duration.zero);
      final pause = service.pause();
      var pauseReached = true;
      try {
        await host.paused.future.timeout(const Duration(milliseconds: 100));
      } on TimeoutException {
        pauseReached = false;
        host.release();
      }
      await pause;
      await start;
      expect(pauseReached, isTrue);
      session.dispose();
      service.dispose();
      await service.waitUntilIdle();
    },
  );

  test(
    'child capability outlives parent and repeated child release is safe',
    () {
      final lifetime = NativeEngineLifetime();
      final parent = lifetime.scope();
      final child = parent.child();
      var frees = 0;
      lifetime.close(() => frees++);
      parent.release();
      expect(() => parent.child(), throwsStateError);
      expect(frees, 0);
      final release = child.retain();
      release();
      child.release();
      child.release();
      expect(frees, 1);
    },
  );

  test('child capability releases after error exactly once', () async {
    final lifetime = NativeEngineLifetime();
    final parent = lifetime.scope();
    final child = parent.child();
    var frees = 0;
    lifetime.close(() => frees++);
    parent.release();
    await expectLater(
      child.guard(() async {
        throw StateError('child');
      }),
      throwsStateError,
    );
    expect(frees, 0);
    child.release();
    child.release();
    expect(frees, 1);
  });

  test('cached loader plan is preserved when dispatch crosses close', () async {
    final dir = await Directory.systemTemp.createTemp('coverage-cached-close-');
    SnapshotCache.cacheDirForTest = dir;
    addTearDown(() async {
      SnapshotCache.cacheDirForTest = null;
      await dir.delete(recursive: true);
    });
    final bridge = _NativeBridge()..building = false;
    final provider = _DelayedProvider();
    final session = VolwardSession.test(
      nativeBridgeForTest: bridge,
      engineForTest: Pointer.fromAddress(130),
      offloadCoverageForTest: false,
    );
    await CoverageJobStateStore(dir).save(
      CoverageJobState.fromJson({
        'snapshot_id': 'snapshot',
        'root_path': '',
        'plan_version': 1,
        'status': 'paused',
        'budget_tokens': 1000,
        'budget_credits': 1,
      }),
    );
    var loads = 0;
    final service = (await AiCoverageService.tryCreate(
      session: session,
      provider: provider,
      runJobOnMainIsolate: true,
      resumePlanLoader: (_, __) async {
        loads++;
        return const CoveragePlanSummary(
          snapshotId: 'snapshot',
          planVersion: 2,
          rootPath: '/cached',
          totalUnclassified: 0,
          preClassifiedCount: 0,
          groupRows: 0,
          fileRows: 0,
          estimatedPages: 0,
        );
      },
    ))!;
    final start = service.resume('snapshot');
    await provider.entered.future;
    session.dispose();
    provider.release.complete();
    await start;
    await service.waitUntilIdle();
    expect(loads, 1);
    expect(service.state!.planVersion, 2);
    expect(service.state!.rootPath, '/cached');
    service.dispose();
    provider.dispose();
  });

  test('asynchronous loader retains materialized read across close', () async {
    final dir = await Directory.systemTemp.createTemp('coverage-loader-close-');
    SnapshotCache.cacheDirForTest = dir;
    addTearDown(() async {
      SnapshotCache.cacheDirForTest = null;
      await dir.delete(recursive: true);
    });
    final bridge = _NativeBridge()..building = false;
    final session = VolwardSession.test(
      nativeBridgeForTest: bridge,
      engineForTest: Pointer.fromAddress(131),
      offloadCoverageForTest: false,
    );
    final root = session.coverageEngine!;
    final entered = Completer<void>();
    final gate = Completer<void>();
    final service = (await AiCoverageService.tryCreate(
      session: session,
      provider: _Provider(),
      runJobOnMainIsolate: true,
      resumePlanLoader: (id, job) async {
        entered.complete();
        await gate.future;
        return root.tryReadMaterializedPlanSummary(id, tree: false);
      },
    ))!;
    await service.start('snapshot', budgetTokens: 1000, budgetCredits: 0);
    await entered.future;
    session.dispose();
    expect(bridge.freed, isFalse);
    gate.complete();
    await service.waitUntilIdle();
    expect(service.state!.rootPath, '/');
    expect(service.state!.pauseMessage, isNull);
    service.dispose();
  });

  test('loader exception remains the job failure after close', () async {
    final dir = await Directory.systemTemp.createTemp('coverage-loader-error-');
    SnapshotCache.cacheDirForTest = dir;
    addTearDown(() async {
      SnapshotCache.cacheDirForTest = null;
      await dir.delete(recursive: true);
    });
    final bridge = _NativeBridge()..building = false;
    final session = VolwardSession.test(
      nativeBridgeForTest: bridge,
      engineForTest: Pointer.fromAddress(132),
      offloadCoverageForTest: false,
    );
    final entered = Completer<void>();
    final gate = Completer<void>();
    final service = (await AiCoverageService.tryCreate(
      session: session,
      provider: _Provider(),
      runJobOnMainIsolate: true,
      resumePlanLoader: (_, __) async {
        entered.complete();
        await gate.future;
        throw StateError('loader failure');
      },
    ))!;
    await service.start('snapshot', budgetTokens: 1000, budgetCredits: 0);
    await entered.future;
    session.dispose();
    gate.complete();
    await service.waitUntilIdle();
    expect(service.state!.pauseReason, CoveragePauseReason.failed);
    expect(service.state!.pauseMessage, 'Bad state: loader failure');
    service.dispose();
  });

  test('scoped child survives scope release and releases only once', () async {
    final lifetime = NativeEngineLifetime();
    final lease = lifetime.scope();
    final gate = Completer<void>();
    final child = lease.guard(() async {
      await gate.future;
      throw StateError('child failure');
    });
    var frees = 0;
    lifetime.close(() => frees++);
    lease.release();
    lease.release();
    expect(() => lease.retain(), throwsStateError);
    expect(frees, 0);
    gate.complete();
    await expectLater(child, throwsStateError);
    expect(frees, 1);
  });

  test('service rejects a new dispatch after session close', () async {
    final dir = await Directory.systemTemp.createTemp('coverage-closed-');
    SnapshotCache.cacheDirForTest = dir;
    addTearDown(() async {
      SnapshotCache.cacheDirForTest = null;
      await dir.delete(recursive: true);
    });
    final bridge = _NativeBridge()..building = false;
    final session = VolwardSession.test(
      nativeBridgeForTest: bridge,
      engineForTest: Pointer.fromAddress(128),
      offloadCoverageForTest: false,
    );
    final service = (await AiCoverageService.tryCreate(
      session: session,
      provider: _Provider(),
      runJobOnMainIsolate: true,
    ))!;
    session.dispose();
    Object? error;
    try {
      await service.start('snapshot', budgetTokens: 1000, budgetCredits: 0);
    } catch (caught) {
      error = caught;
    }
    await service.markAppQuit();
    service.dispose();
    expect(error, isA<StateError>());
  });

  test('close rejects new root work while an older borrower drains', () {
    final lifetime = NativeEngineLifetime();
    final release = lifetime.retain();
    var frees = 0;
    lifetime.close(() => frees++);
    expect(() => lifetime.retain(), throwsStateError);
    expect(frees, 0);
    release();
    release();
    expect(frees, 1);
  });

  test(
    'guard releases on error and repeated close cannot free twice',
    () async {
      final lifetime = NativeEngineLifetime();
      final gate = Completer<void>();
      final work = lifetime.guard(() async {
        await gate.future;
        throw StateError('failure');
      });
      var frees = 0;
      lifetime.close(() => frees++);
      expect(() => lifetime.close(() => frees++), throwsStateError);
      gate.complete();
      await expectLater(work, throwsStateError);
      expect(frees, 1);
    },
  );
}

class _NativeBridge implements VolwardNativeBridge {
  bool building = true;
  bool freed = false;
  final polled = Completer<void>();
  void Function()? onFree;
  int reads = 0;
  @override
  bool get hasAiCoverageApi => true;
  @override
  bool get hasAiTreeCoverageApi => false;
  @override
  bool get hasAsyncAiCoveragePlanApi => true;
  @override
  String? startBuildAiCoveragePlanAsync(
    Pointer<Void> engine,
    String snapshotId, {
    required bool tree,
  }) => 'ok';
  @override
  bool isAiCoveragePlanBuilding(Pointer<Void> engine) {
    if (!polled.isCompleted) polled.complete();
    return building;
  }

  @override
  String? getAiCoveragePlanJson(Pointer<Void> engine) =>
      '{"snapshot_id":"snapshot","root_path":"/"}';
  @override
  String? nextAiCoveragePageJson(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 40,
  }) =>
      '{"snapshot_id":"$snapshotId","plan_version":$planVersion,"rows":[],"next_cursor":null}';
  @override
  String? listLocalCoverageVerdictsJson(
    Pointer<Void> engine,
    String snapshotId,
    int cursor, {
    int limit = 5000,
  }) {
    reads++;
    return '{"verdicts":[{"path":"/a","verdict":"keep","confidence":"high","reason":"test","coverage_source":"local","size_bytes":1}]}';
  }

  @override
  void freeEngine(Pointer<Void> engine) {
    freed = true;
    onFree?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FacadeEngineBridge implements EngineBridge {
  final List<Pointer<Void>> createdEngines = [];
  final List<Pointer<Void>> freedEngines = [];

  @override
  NativeStringCodec get codec => throw UnsupportedError('codec not used');

  @override
  Pointer<Void> createEngine() {
    final engine = Pointer<Void>.fromAddress(901);
    createdEngines.add(engine);
    return engine;
  }

  @override
  void freeEngine(Pointer<Void> engine) => freedEngines.add(engine);

  @override
  void freeString(Pointer<Utf8> value) {}
}

class _Provider implements AiProvider {
  @override
  Future<AnalyzeResult> analyze(
    List<AiCandidate> candidates, {
    CancelToken? cancelToken,
  }) async => const AnalyzeResult(verdicts: []);
  @override
  Future<AiQuotaInfo?> queryQuota() async => null;
  @override
  Future<AiConclusionSynthesisResponse> synthesizeConclusion(
    AiConclusionSynthesisRequest request, {
    CancelToken? cancelToken,
  }) async => const AiConclusionSynthesisResponse(text: '');
}

class _DelayedProvider extends PlatformAiProvider {
  _DelayedProvider() : super(token: 'test');
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<AiQuotaInfo?> queryQuota() async {
    entered.complete();
    await release.future;
    return null;
  }
}

class _CatalogReader implements CoverageSnapshotReader {
  _CatalogReader(this.session);
  final VolwardSession session;
  @override
  CoverageEngine? get coverageEngine => session.coverageEngine;
  @override
  bool get hasAiTreeCoverageApi => false;
  @override
  bool get hasIndexApi => false;
  @override
  String? get currentCoverageSnapshotId => 'snapshot';
  @override
  Future<String?> catalogIndexPathForAiCoverage(String snapshotId) async =>
      '/missing-test-catalog';
}

class _ControlledHost extends CoverageJobIsolateHost {
  _ControlledHost() : super(catalogPath: 'test', workerConfig: {});
  final entered = Completer<void>();
  final dispatchGate = Completer<void>();
  final idleEntered = Completer<void>();
  final idleGate = Completer<void>();
  bool disposed = false;
  bool active = false;
  @override
  bool get started => active;
  Future<CoverageJobState> dispatch(String snapshotId) async {
    active = true;
    entered.complete();
    await dispatchGate.future;
    if (disposed) throw StateError('host already disposed');
    return CoverageJobState.fromJson({
      'snapshot_id': snapshotId,
      'root_path': '/worker',
      'plan_version': 7,
      'status': 'running',
    });
  }

  @override
  Future<CoverageJobState> start(
    String snapshotId, {
    required int budgetTokens,
    required int budgetCredits,
    bool detachRun = true,
  }) => dispatch(snapshotId);
  @override
  Future<CoverageJobState> resume(
    String snapshotId, {
    bool detachRun = true,
    CoveragePlanSummary? preloadedPlan,
  }) => dispatch(snapshotId);
  @override
  Future<void> markAppQuit() async {
    if (disposed) throw StateError('host already disposed');
  }

  @override
  Future<void> beginShutdown() => waitUntilIdle();

  @override
  Future<void> waitUntilIdle() async {
    idleEntered.complete();
    await idleGate.future;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _ControlHost extends CoverageJobIsolateHost {
  _ControlHost() : super(catalogPath: 'test', workerConfig: {});
  final controlEntered = Completer<void>();
  final controlGate = Completer<void>();
  bool disposed = false;
  bool active = false;
  bool busy = false;
  bool overlapped = false;
  int controls = 0;
  @override
  bool get started => active;
  CoverageJobState stateFor(int version) => CoverageJobState.fromJson({
    'snapshot_id': 'snapshot',
    'root_path': '/worker',
    'plan_version': version,
    'status': 'paused',
  });
  Future<CoverageJobState> control() async {
    controls++;
    active = true;
    busy = true;
    controlEntered.complete();
    await controlGate.future;
    busy = false;
    return stateFor(8);
  }

  @override
  Future<CoverageJobState> pause() => control();
  @override
  Future<CoverageJobState> cancel(String snapshotId) => control();
  @override
  Future<CoverageJobState> start(
    String snapshotId, {
    required int budgetTokens,
    required int budgetCredits,
    bool detachRun = true,
  }) async {
    active = true;
    if (busy) overlapped = true;
    return stateFor(9);
  }

  @override
  Future<void> markAppQuit() async {}
  @override
  Future<void> waitUntilIdle() async {}
  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _BusyHost extends CoverageJobIsolateHost {
  _BusyHost() : super(catalogPath: 'test', workerConfig: {});
  final paused = Completer<void>();
  final idle = Completer<void>();
  bool running = true;
  void release() {
    running = false;
    if (!idle.isCompleted) idle.complete();
  }

  CoverageJobState makeState(String id) => CoverageJobState.fromJson({
    'snapshot_id': id,
    'root_path': '/',
    'plan_version': 1,
    'status': running ? 'running' : 'paused',
  });
  @override
  bool get started => true;
  @override
  CoverageJobState? get state => makeState('active');
  @override
  Future<CoverageJobState> start(
    String snapshotId, {
    required int budgetTokens,
    required int budgetCredits,
    bool detachRun = true,
  }) async {
    if (running) await idle.future;
    return makeState(snapshotId);
  }

  @override
  Future<CoverageJobState> pause() async {
    if (!paused.isCompleted) paused.complete();
    release();
    return makeState('active');
  }

  @override
  Future<void> waitUntilIdle() => idle.future;
  @override
  Future<void> markAppQuit() async {}
  @override
  Future<void> dispose() async {}
}

class _RunningBridge extends _NativeBridge {
  @override
  String? getAiCoveragePlanJson(Pointer<Void> engine) =>
      '{"snapshot_id":"snapshot","root_path":"/","plan_version":1,"total_unclassified":1,"file_rows":1}';
  @override
  String? nextAiCoveragePageJson(
    Pointer<Void> engine,
    String snapshotId,
    int planVersion,
    int cursor, {
    int pageSize = 40,
  }) =>
      '{"snapshot_id":"$snapshotId","plan_version":1,"rows":[{"row_index":0,"kind":"file","path":"/file","size_bytes":1}],"next_cursor":null}';
}

class _BlockingProvider extends _Provider {
  final entered = Completer<void>();
  final release = Completer<void>();
  CancelToken? token;
  int calls = 0;
  @override
  Future<AnalyzeResult> analyze(
    List<AiCandidate> candidates, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    token = cancelToken;
    if (!entered.isCompleted) entered.complete();
    await release.future;
    if (cancelToken?.isCancelled == true) {
      throw const CoverageCancelledException();
    }
    return AnalyzeResult(
      verdicts: candidates
          .map(
            (candidate) => AiVerdict(
              path: candidate.path,
              verdict: 'keep',
              confidence: 'high',
              reason: 'test',
            ),
          )
          .toList(),
    );
  }
}
