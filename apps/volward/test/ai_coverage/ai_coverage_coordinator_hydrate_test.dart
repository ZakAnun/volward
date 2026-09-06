import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_coverage_coordinator.dart';
import 'package:volward/ai/byok_ai_provider.dart';
import 'package:volward/ai/ai_coverage_service.dart';
import 'package:volward/ai/ai_coverage_job_controller.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/cancel_token.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/ai/coverage_engine.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_models.dart';
import 'package:volward/ai/coverage_verdict_store.dart';
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
  CoverageJobState? fakeState;

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

  test('auto resume calls resume, while explicit start stays fresh', () async {
    final service = _RecordingService(cacheDir);
    final provider = _Provider();
    await CoverageJobStateStore(cacheDir).save(
      const CoverageJobState(
        snapshotId: 'snap-resume',
        rootPath: '/',
        planVersion: 1,
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
      ),
    );
    coordinator = AiCoverageCoordinator.testing(
      serviceFactory: ({required session, required provider}) => service,
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

      final started = await coordinator.startFullCoverage(
        snapshotId: 'snap-missing',
        mode: AiMode.platform,
        provider: _Provider(),
      );

      expect(started, isFalse);
    },
  );

  test('ensureJobRunning skips when another snapshot is active', () async {
    final service = _RecordingService(cacheDir);
    final provider = _Provider();
    coordinator = AiCoverageCoordinator.testing(
      serviceFactory: ({required session, required provider}) => service,
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
      serviceFactory: ({required session, required provider}) {
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
      serviceFactory: ({required session, required provider}) {
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
