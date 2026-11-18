import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_coverage_coordinator.dart';
import 'package:volward/ai/byok_ai_provider.dart';
import 'package:volward/ai/ai_coverage_service.dart';
import 'package:volward/ai/ai_coverage_job_controller.dart';
import 'package:volward/ai/ai_conclusion_synthesis.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/cancel_token.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/ai/coverage_engine.dart';
import 'package:volward/ai/coverage_client_logic.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_models.dart';
import 'package:volward/ai/coverage_verdict_store.dart';
import 'package:volward/directory_details_page.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/theme/volward_theme_settings.dart';
import 'package:volward/updater/app_updater.dart';
import 'package:volward/volward_session.dart';
import 'package:volward/snapshot_cache.dart';

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

class _RecordingService extends AiCoverageService {
  _RecordingService(Directory directory)
    : super(
        engine: FakeCoverageEngine(
          summary: const CoveragePlanSummary(
            snapshotId: 'snap-resume',
            planVersion: 1,
            rootPath: '/',
            totalUnclassified: 0,
            preClassifiedCount: 0,
            groupRows: 0,
            fileRows: 0,
            estimatedPages: 0,
          ),
          pages: const [],
        ),
        controller: CoverageJobController(
          engine: FakeCoverageEngine(
            summary: const CoveragePlanSummary(
              snapshotId: 'snap-resume',
              planVersion: 1,
              rootPath: '/',
              totalUnclassified: 0,
              preClassifiedCount: 0,
              groupRows: 0,
              fileRows: 0,
              estimatedPages: 0,
            ),
            pages: const [],
          ),
          verdictStore: CoverageVerdictStore(directory),
          stateStore: CoverageJobStateStore(directory),
          analyzeBatch: (_) async => const BatchOutcome(
            usage: BatchUsage(tokens: 0, credits: 0),
            verdicts: [],
          ),
        ),
      );

  int startCalls = 0;
  int resumeCalls = 0;
  int raiseCalls = 0;
  Completer<void>? retirementGate;
  final retirementStarted = Completer<void>();
  CoverageJobState? fakeState;
  bool matchesCatalog = true;
  @override
  bool isolateCatalogMatches(String snapshotId) => matchesCatalog;
  bool failQuit = false;
  bool failIdle = false;
  bool failDispose = false;
  bool failCancel = false;
  bool cancelCalled = false;
  StreamController<CoverageJobState>? _testStates;

  @override
  Stream<CoverageJobState> get states {
    _testStates ??= StreamController<CoverageJobState>(
      onCancel: () async {
        cancelCalled = true;
        if (failCancel) throw StateError('cancel failed');
      },
    );
    return _testStates!.stream;
  }

  bool idleWaited = false;
  bool disposed = false;

  @override
  Future<void> waitUntilIdle() async {
    idleWaited = true;
    if (failIdle) throw StateError('idle failed');
    await super.waitUntilIdle();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
    if (failDispose) throw StateError('dispose failed');
  }

  @override
  CoverageJobState? get state => fakeState;

  @override
  Future<CoverageJobState> start(
    String snapshotId, {
    required int budgetTokens,
    required int budgetCredits,
  }) async {
    startCalls++;
    return _state(snapshotId);
  }

  @override
  Future<CoverageJobState> resume(String snapshotId) async {
    resumeCalls++;
    return _state(snapshotId);
  }

  @override
  Future<CoverageJobState> raiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
  }) async {
    raiseCalls++;
    return _state(snapshotId);
  }

  @override
  Future<void> markAppQuit() async {
    if (failQuit) throw StateError("quit failed");
    final gate = retirementGate;
    if (gate != null) {
      if (!retirementStarted.isCompleted) retirementStarted.complete();
      await gate.future;
    }
    await super.markAppQuit();
  }

  CoverageJobState _state(String snapshotId) => CoverageJobState(
    snapshotId: snapshotId,
    rootPath: '/',
    planVersion: 1,
    cursor: 0,
    totalUnclassified: 0,
    analyzedFiles: 0,
    preClassifiedCount: 0,
    status: CoverageJobStatus.running,
    usedTokens: 0,
    usedCredits: 0,
    budgetTokens: 100,
    budgetCredits: 1,
    updatedAtMs: 1,
  );
}

class _DisposableProvider extends ByokAiProvider {
  _DisposableProvider([String key = 'test']) : super(apiKey: key);
  bool disposed = false;
  bool failDispose = false;
  @override
  void dispose() {
    disposed = true;
    super.dispose();
    if (failDispose) throw StateError('provider failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory cacheDir;
  late AiCoverageCoordinator coordinator;

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('coverage-coord-');
    SnapshotCache.cacheDirForTest = cacheDir;
    coordinator = AiCoverageCoordinator.testing();
  });

  tearDown(() async {
    SnapshotCache.cacheDirForTest = null;
    await cacheDir.delete(recursive: true);
  });

  test(
    'same-snapshot reattach waits for retirement before resuming or raising',
    () async {
      const snapshotId = 'same-snapshot';
      AiCoverageCoordinator.debugTreatSnapshotReady = true;
      addTearDown(() => AiCoverageCoordinator.debugTreatSnapshotReady = false);
      final previous = VolwardSession.test();
      final replacement = VolwardSession.test();
      final retiring = _RecordingService(cacheDir)
        ..retirementGate = Completer<void>();
      retiring.fakeState = retiring._state(snapshotId);
      final next = _RecordingService(cacheDir);
      next.fakeState = next._state(snapshotId);
      final serviceSessions = <VolwardSession>[];
      final provider = _Provider();
      coordinator = AiCoverageCoordinator.testing(
        serviceFactory:
            ({
              required session,
              required provider,
              resumePlanLoader,
              catalogSnapshotId,
            }) async {
              serviceSessions.add(session);
              return identical(session, previous) ? retiring : next;
            },
        isCoverageApiReady: (_) => true,
        resolveProvider: () async =>
            coordinator.isAttachedTo(replacement) ? provider : null,
      );
      coordinator.attach(previous);
      await coordinator.prepareService(provider, catalogSnapshotId: snapshotId);

      coordinator.attach(replacement);
      await retiring.retirementStarted.future;
      final publishedDuringRetirement = coordinator.currentState;
      final resumed = coordinator.tryResumeCoverage(snapshotId);
      final raised = coordinator.tryRaiseBudgetAndResume(
        snapshotId: snapshotId,
        budgetTokens: 200,
        budgetCredits: 2,
      );
      await Future<void>.delayed(Duration.zero);
      final resumeCallsWhileRetiring = retiring.resumeCalls;
      final raiseCallsWhileRetiring = retiring.raiseCalls;
      final servicesWhileRetiring = List.of(serviceSessions);
      retiring.retirementGate!.complete();

      expect(await resumed, isTrue);
      expect(await raised, isTrue);
      expect(publishedDuringRetirement, isNull);
      expect(resumeCallsWhileRetiring, 0);
      expect(raiseCallsWhileRetiring, 0);
      expect(servicesWhileRetiring, [previous]);
      expect(serviceSessions, [previous, replacement]);
      expect(next.resumeCalls, 1);
      expect(next.raiseCalls, 1);
      await coordinator.detachAndDrain();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    },
  );

  test('failed retirement cleans up and a later owner can prepare', () async {
    final previous = VolwardSession.test();
    final replacement = VolwardSession.test();
    final retiring = _RecordingService(cacheDir)..failQuit = true;
    final next = _RecordingService(cacheDir);
    final provider = _Provider();
    coordinator = AiCoverageCoordinator.testing(
      isCoverageApiReady: (_) => true,
      resolveProvider: () async => null,
      serviceFactory:
          ({
            required session,
            required provider,
            resumePlanLoader,
            catalogSnapshotId,
          }) async => identical(session, previous) ? retiring : next,
    );
    coordinator.rebind(previous);
    await coordinator.prepareService(provider);
    await expectLater(coordinator.detachAndDrain(), throwsStateError);
    expect(retiring.idleWaited, isTrue);
    expect(retiring.disposed, isTrue);
    coordinator.rebind(replacement);
    expect(await coordinator.prepareService(provider), same(next));
    await coordinator.detachAndDrain();
  });

  for (final phase in ['quit', 'idle', 'dispose', 'provider', 'cancel']) {
    test('retirement continues after $phase failure', () async {
      final service = _RecordingService(cacheDir)
        ..failQuit = phase == 'quit'
        ..failIdle = phase == 'idle'
        ..failDispose = phase == 'dispose'
        ..failCancel = phase == 'cancel';
      final provider = _DisposableProvider()..failDispose = phase == 'provider';
      final replacement = _RecordingService(cacheDir);
      var created = 0;
      coordinator = AiCoverageCoordinator.testing(
        isCoverageApiReady: (_) => true,
        resolveProvider: () async => null,
        serviceFactory:
            ({
              required session,
              required provider,
              resumePlanLoader,
              catalogSnapshotId,
            }) async => created++ == 0 ? service : replacement,
      );
      coordinator.rebind(VolwardSession.test());
      await coordinator.prepareService(provider);
      await expectLater(
        coordinator.detachAndDrain(),
        throwsA(isA<StateError>()),
      );
      expect(service.idleWaited, isTrue);
      expect(service.disposed, isTrue);
      expect(provider.disposed, isTrue);
      expect(service.cancelCalled, isTrue);
      coordinator.rebind(VolwardSession.test());
      expect(await coordinator.prepareService(_Provider()), same(replacement));
      await coordinator.detachAndDrain();
    });
  }

  test(
    'failed close still waits for rejected predecessor and later handoff recovers',
    () async {
      final previous = VolwardSession.test();
      final replacement = VolwardSession.test();
      final finalOwner = VolwardSession.test();
      final service = _RecordingService(cacheDir)..failQuit = true;
      final next = _RecordingService(cacheDir);
      final last = _RecordingService(cacheDir);
      final provider = _Provider();
      final predecessor = Completer<void>();
      coordinator = AiCoverageCoordinator.testing(
        isCoverageApiReady: (_) => true,
        resolveProvider: () async => null,
        serviceFactory:
            ({
              required session,
              required provider,
              resumePlanLoader,
              catalogSnapshotId,
            }) async => identical(session, previous)
            ? service
            : identical(session, replacement)
            ? next
            : last,
      );
      coordinator.rebind(previous);
      await coordinator.prepareService(provider);
      coordinator.attachAfter(replacement, predecessor.future);
      var finished = false;
      final pending = coordinator.prepareService(provider).then((value) {
        finished = true;
        return value;
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(finished, isFalse);
      predecessor.completeError(StateError('predecessor failed'));
      expect(await pending, same(next));
      coordinator.rebind(finalOwner);
      expect(await coordinator.prepareService(provider), same(last));
      await coordinator.detachAndDrain();
    },
  );

  test(
    'predecessor rejection is observed while service retirement is pending',
    () async {
      final gate = Completer<void>();
      final predecessor = Completer<void>();
      final service = _RecordingService(cacheDir)..retirementGate = gate;
      final provider = _Provider();
      coordinator = AiCoverageCoordinator.testing(
        isCoverageApiReady: (_) => true,
        resolveProvider: () async => null,
        serviceFactory:
            ({
              required session,
              required provider,
              resumePlanLoader,
              catalogSnapshotId,
            }) async => service,
      );
      coordinator.rebind(VolwardSession.test());
      await coordinator.prepareService(provider);
      coordinator.attachAfter(VolwardSession.test(), predecessor.future);
      await service.retirementStarted.future;
      predecessor.completeError(StateError('predecessor failed'));
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await coordinator.detachAndDrain();
    },
  );

  for (final action in ['pause', 'cancel', 'quit', 'retire']) {
    test('second start does not block $action of running snapshot', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final token = CancelToken();
      final engine = FakeCoverageEngine(
        summary: const CoveragePlanSummary(
          snapshotId: 'a',
          planVersion: 1,
          rootPath: '/',
          totalUnclassified: 1,
          preClassifiedCount: 0,
          groupRows: 0,
          fileRows: 1,
          estimatedPages: 1,
        ),
        pages: const [
          CoveragePage(
            snapshotId: 'a',
            planVersion: 1,
            nextCursor: null,
            rows: [
              CoverageRow(
                rowIndex: 0,
                kind: CoverageRowKind.file,
                path: '/a',
                sizeBytes: 1,
              ),
            ],
          ),
        ],
      );
      final controller = CoverageJobController(
        engine: engine,
        verdictStore: CoverageVerdictStore(cacheDir),
        stateStore: CoverageJobStateStore(cacheDir),
        cancelToken: token,
        analyzeBatch: (_) async {
          if (!entered.isCompleted) {
            entered.complete();
            await release.future;
          }
          return const BatchOutcome(
            usage: BatchUsage(tokens: 0, credits: 0),
            verdicts: [],
          );
        },
      );
      final service = AiCoverageService(engine: engine, controller: controller);
      final provider = _Provider();
      coordinator = AiCoverageCoordinator.testing(
        isCoverageApiReady: (_) => true,
        resolveProvider: () async => null,
        serviceFactory:
            ({
              required session,
              required provider,
              resumePlanLoader,
              catalogSnapshotId,
            }) async => service,
      );
      coordinator.rebind(VolwardSession.test());
      await coordinator.startFullCoverage(
        snapshotId: 'a',
        mode: AiMode.byok,
        provider: provider,
      );
      await entered.future;
      final second = coordinator.startFullCoverage(
        snapshotId: 'b',
        mode: AiMode.byok,
        provider: provider,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final control = switch (action) {
        'pause' => coordinator.pauseCoverage(),
        'cancel' => coordinator.cancelCoverage('a'),
        'quit' => coordinator.markAppQuit(),
        _ => coordinator.detachAndDrain(),
      };
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final reached = token.isCancelled;
      release.complete();
      await control.timeout(const Duration(seconds: 3));
      await second.timeout(const Duration(seconds: 3));
      if (action != 'retire') await coordinator.detachAndDrain();
      expect(
        reached,
        isTrue,
        reason: '$action must reach the running job before it finishes',
      );
    });
  }

  test('retiring service cannot read replacement owner plan cache', () async {
    const snapshot = 'same';
    const replacementPlan = CoveragePlanSummary(
      snapshotId: snapshot,
      planVersion: 3,
      rootPath: '/replacement',
      totalUnclassified: 1,
      preClassifiedCount: 0,
      groupRows: 0,
      fileRows: 1,
      estimatedPages: 1,
    );
    final old = VolwardSession.test();
    final replacement = VolwardSession.test();
    final service = _RecordingService(cacheDir)
      ..retirementGate = Completer<void>();
    CoverageResumePlanLoader? loader;
    final provider = _Provider();
    coordinator = AiCoverageCoordinator.testing(
      isCoverageApiReady: (_) => true,
      resolveProvider: () async => null,
      serviceFactory:
          ({
            required session,
            required provider,
            resumePlanLoader,
            catalogSnapshotId,
          }) async {
            loader = resumePlanLoader;
            return service;
          },
    );
    coordinator.rebind(old);
    await coordinator.prepareService(provider);
    coordinator.rebind(replacement);
    await service.retirementStarted.future;
    coordinator.debugSetPlanSummaryCache(snapshot, replacementPlan);
    final result = await loader!(snapshot, service._state(snapshot));
    service.retirementGate!.complete();
    await coordinator.detachAndDrain();
    expect(result, isNull);
  });

  test('provider is disposed when service creation returns null', () async {
    final provider = _DisposableProvider();
    coordinator = AiCoverageCoordinator.testing(
      isCoverageApiReady: (_) => true,
      resolveProvider: () async => null,
      serviceFactory:
          ({
            required session,
            required provider,
            resumePlanLoader,
            catalogSnapshotId,
          }) async => null,
    );
    coordinator.rebind(VolwardSession.test());
    expect(await coordinator.prepareService(provider), isNull);
    expect(provider.disposed, isTrue);
    await coordinator.detachAndDrain();
  });

  test(
    'stale prepare never disposes provider still owned by retiring service',
    () async {
      final provider = _DisposableProvider();
      final service = _RecordingService(cacheDir)
        ..retirementGate = Completer<void>();
      coordinator = AiCoverageCoordinator.testing(
        isCoverageApiReady: (_) => true,
        resolveProvider: () async => null,
        serviceFactory:
            ({
              required session,
              required provider,
              resumePlanLoader,
              catalogSnapshotId,
            }) async => service,
      );
      coordinator.rebind(VolwardSession.test());
      await coordinator.prepareService(provider);
      coordinator.rebind(VolwardSession.test());
      await service.retirementStarted.future;
      final stale = coordinator.prepareService(provider);
      coordinator.rebind(VolwardSession.test());
      await Future<void>.delayed(Duration.zero);
      expect(provider.disposed, isFalse);
      service.retirementGate!.complete();
      await stale;
      await coordinator.detachAndDrain();
      expect(provider.disposed, isTrue);
    },
  );

  test('auto-resume disposes resolved provider when no jobs exist', () async {
    final resolved = Completer<_DisposableProvider>();
    coordinator = AiCoverageCoordinator.testing(
      isCoverageApiReady: (_) => true,
      resolveProvider: () async {
        final provider = _DisposableProvider();
        resolved.complete(provider);
        return provider;
      },
    );
    coordinator.rebind(VolwardSession.test());
    final provider = await resolved.future;
    for (var i = 0; i < 30 && !provider.disposed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(provider.disposed, isTrue);
    await coordinator.detachAndDrain();
  });

  test('failed release disposes incoming provider', () async {
    final oldProvider = _DisposableProvider();
    final incoming = _DisposableProvider('another');
    final service = _RecordingService(cacheDir)..failQuit = true;
    coordinator = AiCoverageCoordinator.testing(
      isCoverageApiReady: (_) => true,
      resolveProvider: () async => null,
      serviceFactory:
          ({
            required session,
            required provider,
            resumePlanLoader,
            catalogSnapshotId,
          }) async => service,
    );
    coordinator.rebind(VolwardSession.test());
    await coordinator.prepareService(oldProvider);
    await expectLater(coordinator.prepareService(incoming), throwsStateError);
    expect(incoming.disposed, isTrue);
    await coordinator.detachAndDrain();
  });

  test(
    'recreating service transfers rather than disposes the active provider',
    () async {
      final provider = _DisposableProvider();
      final first = _RecordingService(cacheDir)..matchesCatalog = false;
      final next = _RecordingService(cacheDir);
      var calls = 0;
      coordinator = AiCoverageCoordinator.testing(
        isCoverageApiReady: (_) => true,
        resolveProvider: () async => null,
        serviceFactory:
            ({
              required session,
              required provider,
              resumePlanLoader,
              catalogSnapshotId,
            }) async {
              expect((provider as _DisposableProvider).disposed, isFalse);
              return calls++ == 0 ? first : next;
            },
      );
      coordinator.rebind(VolwardSession.test());
      await coordinator.prepareService(provider);
      expect(
        await coordinator.prepareService(provider, catalogSnapshotId: 'next'),
        same(next),
      );
      expect(provider.disposed, isFalse);
      await coordinator.detachAndDrain();
      expect(provider.disposed, isTrue);
    },
  );

  for (final replaceCoordinator in [false, true]) {
    final coordinatorMode = replaceCoordinator ? 'new owner' : 'same owner';
    testWidgets(
      'page Session handoff drains the previous owner before auto-resume ($coordinatorMode)',
      (tester) async {
        const snapshotId = 'same-snapshot';
        AiCoverageCoordinator.debugTreatSnapshotReady = true;
        addTearDown(
          () => AiCoverageCoordinator.debugTreatSnapshotReady = false,
        );
        final previous = VolwardSession.test()
          ..rootExistsForTest = (_) => false;
        final replacement = VolwardSession.test()
          ..rootExistsForTest = (_) => false;
        final theme = VolwardThemeSettings();
        final updater = AppUpdater.test();
        final retiring = _RecordingService(cacheDir)
          ..retirementGate = Completer<void>();
        final next = _RecordingService(cacheDir);
        final provider = _Provider();
        final serviceSessions = <VolwardSession>[];
        AiCoverageCoordinator newCoordinator() => AiCoverageCoordinator.testing(
          serviceFactory:
              ({
                required session,
                required provider,
                resumePlanLoader,
                catalogSnapshotId,
              }) async {
                serviceSessions.add(session);
                return identical(session, previous) ? retiring : next;
              },
          isCoverageApiReady: (_) => true,
          resolveProvider: () async => provider,
        );
        final owner = newCoordinator();
        final nextOwner = replaceCoordinator ? newCoordinator() : owner;
        addTearDown(() {
          if (!retiring.retirementGate!.isCompleted) {
            retiring.retirementGate!.complete();
          }
          owner.detach();
          if (replaceCoordinator) nextOwner.detach();
          previous.dispose();
          replacement.dispose();
          theme.dispose();
          updater.dispose();
        });
        await tester.runAsync(() async {
          owner.attach(previous);
          await owner.prepareService(provider, catalogSnapshotId: snapshotId);
          final running = CoverageJobState.fromJson({
            ...retiring._state(snapshotId).toJson(),
            'plan_version': 3,
            'client_logic_version': kCoverageClientLogicVersion,
          });
          retiring.fakeState = running;
          await CoverageJobStateStore(cacheDir).save(running);
        });

        Widget page(VolwardSession session) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DirectoryDetailsPage(
            session: session,
            coverageCoordinator: identical(session, previous)
                ? owner
                : nextOwner,
            themeSettings: theme,
            updater: updater,
          ),
        );

        await tester.pumpWidget(page(previous));
        await tester.pumpWidget(page(replacement));
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        final retiredDuringHandoff = retiring.retirementStarted.isCompleted;
        expect(retiredDuringHandoff, isTrue);
        expect(nextOwner.isAttachedTo(replacement), isTrue);
        expect(owner.isAttachedTo(previous), isFalse);
        expect(serviceSessions, [previous]);
        expect(next.resumeCalls, 0);

        retiring.retirementGate!.complete();
        for (
          var attempt = 0;
          attempt < 20 && next.resumeCalls == 0;
          attempt++
        ) {
          await tester.pump(const Duration(milliseconds: 10));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(retiring.resumeCalls, 0);
        expect(next.resumeCalls, 1);
        expect(serviceSessions, [previous, replacement]);
        await tester.pumpWidget(const SizedBox.shrink());
        var drained = false;
        Object? drainError;
        final drain = nextOwner.detachAndDrain().then<void>(
          (_) => drained = true,
          onError: (Object error) {
            drainError = error;
            drained = true;
          },
        );
        for (var attempt = 0; attempt < 20 && !drained; attempt++) {
          await tester.pump(const Duration(milliseconds: 10));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(drained, isTrue);
        expect(drainError, isNull);
        await drain;
      },
    );
  }

  test(
    'cancelCoverage persists cancelled when service is not prepared',
    () async {
      const snapshotId = 'snap-cancel';
      await CoverageJobStateStore(cacheDir).save(
        const CoverageJobState(
          snapshotId: snapshotId,
          rootPath: '/',
          planVersion: 1,
          cursor: 10,
          totalUnclassified: 100,
          analyzedFiles: 10,
          preClassifiedCount: 0,
          status: CoverageJobStatus.paused,
          pauseReason: CoveragePauseReason.manual,
          usedTokens: 0,
          usedCredits: 0,
          budgetTokens: 100000,
          budgetCredits: 0,
          updatedAtMs: 1,
        ),
      );

      await coordinator.cancelCoverage(snapshotId);

      final loaded = await CoverageJobStateStore(cacheDir).load(snapshotId);
      expect(loaded?.status, CoverageJobStatus.cancelled);
    },
  );

  test('auto resume skips v2 plan jobs at current client logic', () async {
    final service = _RecordingService(cacheDir);
    final provider = _Provider();
    await CoverageJobStateStore(cacheDir).save(
      const CoverageJobState(
        snapshotId: 'snap-v2-plan',
        rootPath: '/',
        planVersion: 2,
        cursor: 4,
        totalUnclassified: 10,
        analyzedFiles: 4,
        preClassifiedCount: 0,
        status: CoverageJobStatus.paused,
        pauseReason: CoveragePauseReason.appQuit,
        usedTokens: 0,
        usedCredits: 1,
        budgetTokens: 100,
        budgetCredits: 1,
        updatedAtMs: 1,
        clientLogicVersion: kCoverageClientLogicVersion,
      ),
    );
    coordinator = AiCoverageCoordinator.testing(
      serviceFactory:
          ({
            required session,
            required provider,
            resumePlanLoader,
            catalogSnapshotId,
          }) async => service,
      isCoverageApiReady: (_) => true,
      resolveProvider: () async => provider,
    );

    coordinator.attach(VolwardSession.test());
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(service.resumeCalls, 0);
  });

  test('auto resume skips jobs saved under legacy client logic', () async {
    final service = _RecordingService(cacheDir);
    final provider = _Provider();
    await CoverageJobStateStore(cacheDir).save(
      const CoverageJobState(
        snapshotId: 'snap-legacy',
        rootPath: '/',
        planVersion: 1,
        cursor: 4,
        totalUnclassified: 10,
        analyzedFiles: 4,
        preClassifiedCount: 0,
        status: CoverageJobStatus.paused,
        pauseReason: CoveragePauseReason.appQuit,
        usedTokens: 0,
        usedCredits: 1,
        budgetTokens: 100,
        budgetCredits: 1,
        updatedAtMs: 1,
        clientLogicVersion: 1,
      ),
    );
    coordinator = AiCoverageCoordinator.testing(
      serviceFactory:
          ({
            required session,
            required provider,
            resumePlanLoader,
            catalogSnapshotId,
          }) async => service,
      isCoverageApiReady: (_) => true,
      resolveProvider: () async => provider,
    );

    coordinator.attach(VolwardSession.test());
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(service.resumeCalls, 0);
  });

  test('auto resume calls resume, while explicit start stays fresh', () async {
    AiCoverageCoordinator.debugTreatSnapshotReady = true;
    addTearDown(() => AiCoverageCoordinator.debugTreatSnapshotReady = false);
    AiCoverageCoordinator.debugPlanSummary = (_) async =>
        const CoveragePlanSummary(
          snapshotId: 'snap-resume',
          planVersion: 3,
          rootPath: '/',
          totalUnclassified: 10,
          preClassifiedCount: 0,
          groupRows: 0,
          fileRows: 0,
          estimatedPages: 0,
          estimatedTreeCredits: 1,
          estimatedTailCredits: 0,
        );
    addTearDown(() => AiCoverageCoordinator.debugPlanSummary = null);

    final service = _RecordingService(cacheDir);
    final provider = _Provider();
    await CoverageJobStateStore(cacheDir).save(
      const CoverageJobState(
        snapshotId: 'snap-resume',
        rootPath: '/',
        planVersion: 3,
        cursor: 4,
        totalUnclassified: 10,
        analyzedFiles: 4,
        preClassifiedCount: 0,
        status: CoverageJobStatus.paused,
        pauseReason: CoveragePauseReason.appQuit,
        usedTokens: 20,
        usedCredits: 1,
        budgetTokens: 100,
        budgetCredits: 1,
        updatedAtMs: 1,
        clientLogicVersion: kCoverageClientLogicVersion,
      ),
    );
    coordinator = AiCoverageCoordinator.testing(
      serviceFactory:
          ({
            required session,
            required provider,
            resumePlanLoader,
            catalogSnapshotId,
          }) async => service,
      isCoverageApiReady: (_) => true,
      resolveProvider: () async => provider,
    );

    coordinator.attach(VolwardSession.test());
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(service.resumeCalls, 1);
    expect(service.startCalls, 0);

    await coordinator.startFullCoverage(
      snapshotId: 'snap-resume',
      mode: AiMode.platform,
      provider: provider,
    );
    expect(service.startCalls, 1);
  });

  test(
    'startFullCoverage returns false when coverage api unavailable',
    () async {
      coordinator = AiCoverageCoordinator.testing(
        isCoverageApiReady: (_) => false,
        resolveProvider: () async => _Provider(),
      );
      coordinator.attach(VolwardSession.test());

      final result = await coordinator.startFullCoverage(
        snapshotId: 'snap-missing',
        mode: AiMode.platform,
        provider: _Provider(),
      );

      expect(result, isA<StartFullCoverageUnavailable>());
    },
  );

  test('ensureJobRunning skips when another snapshot is active', () async {
    final service = _RecordingService(cacheDir);
    final provider = _Provider();
    coordinator = AiCoverageCoordinator.testing(
      serviceFactory:
          ({
            required session,
            required provider,
            resumePlanLoader,
            catalogSnapshotId,
          }) async => service,
      isCoverageApiReady: (_) => true,
      resolveProvider: () async => provider,
    );
    coordinator.attach(VolwardSession.test());
    await coordinator.prepareService(provider);
    service.fakeState = const CoverageJobState(
      snapshotId: 'snap-a',
      rootPath: '/',
      planVersion: 1,
      cursor: 1,
      totalUnclassified: 10,
      analyzedFiles: 1,
      preClassifiedCount: 0,
      status: CoverageJobStatus.running,
      usedTokens: 0,
      usedCredits: 0,
      budgetTokens: 100,
      budgetCredits: 1,
      updatedAtMs: 2,
    );

    await CoverageJobStateStore(cacheDir).save(
      const CoverageJobState(
        snapshotId: 'snap-b',
        rootPath: '/',
        planVersion: 1,
        cursor: 0,
        totalUnclassified: 10,
        analyzedFiles: 0,
        preClassifiedCount: 0,
        status: CoverageJobStatus.running,
        usedTokens: 0,
        usedCredits: 0,
        budgetTokens: 100,
        budgetCredits: 1,
        updatedAtMs: 1,
      ),
    );

    await coordinator.ensureJobRunning('snap-b');

    expect(service.resumeCalls, 0);
  });

  test('prepareService recreates service when BYOK key changes', () async {
    var factoryCalls = 0;
    coordinator = AiCoverageCoordinator.testing(
      serviceFactory:
          ({
            required session,
            required provider,
            resumePlanLoader,
            catalogSnapshotId,
          }) async {
            factoryCalls++;
            return _RecordingService(cacheDir);
          },
      isCoverageApiReady: (_) => true,
      resolveProvider: () async => _Provider(),
    );
    coordinator.attach(VolwardSession.test());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    factoryCalls = 0;

    final firstKey = ByokAiProvider(apiKey: 'key-a');
    final secondKey = ByokAiProvider(apiKey: 'key-b');
    await coordinator.prepareService(firstKey);
    await coordinator.prepareService(secondKey);

    expect(factoryCalls, 2);
  });

  test('prepareService reuses service for same provider type', () async {
    var factoryCalls = 0;
    final provider = _Provider();
    final service = _RecordingService(cacheDir);
    coordinator = AiCoverageCoordinator.testing(
      serviceFactory:
          ({
            required session,
            required provider,
            resumePlanLoader,
            catalogSnapshotId,
          }) async {
            factoryCalls++;
            return service;
          },
      isCoverageApiReady: (_) => true,
      resolveProvider: () async => provider,
    );
    coordinator.attach(VolwardSession.test());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    factoryCalls = 0;

    final first = await coordinator.prepareService(provider);
    final second = await coordinator.prepareService(provider);

    expect(first, same(service));
    expect(second, same(service));
    expect(factoryCalls, 1);
  });
}
