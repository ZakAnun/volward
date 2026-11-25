import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_coverage_coordinator.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/ai/coverage_client_logic.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_models.dart';
import 'package:volward/ai/coverage_verdict_store.dart';
import 'package:volward/features/ai_coverage/controllers/ai_analysis_coverage_controller.dart';
import 'package:volward/features/ai_coverage/controllers/ai_analysis_workspace_controller.dart';
import 'package:volward/features/ai_coverage/ports/workspace_ports.dart';

void main() {
  test(
    'terminal full refresh overtakes an older incremental read without cursor rollback',
    () async {
      final store = _OverlappingVerdictStore();
      final coverage = AiAnalysisCoverageController(
        jobs: _FakeCoverageJobs(),
        settings: _FakeSettings(),
        owner: AiAnalysisWorkspaceController(ownerId: 'owner-a'),
        snapshotId: 'snapshot-a',
        coverageOwner: 'owner-a',
        verdictStoreFactory: () => store,
      );
      Future<List<CoverageVerdict>> refresh(bool incremental) =>
          coverage.refreshVerdictsFromStore(
            generation: 0,
            incremental: incremental,
            allowNativeLocalBackfill: false,
            preferReadAll: !incremental,
            lightweightAnalyzingUi: false,
            displayPreClassifiedCount: 0,
            heavyResultsLayoutThreshold: 200,
            backfillLocalVerdicts: (_, _) async => 0,
          );
      final old = refresh(true);
      final terminal = await refresh(false);
      coverage.verdictRows = terminal;
      store.appended.complete((appended: <CoverageVerdict>[], fileLength: 3));
      expect((await old).single.path, '/terminal');
      expect(coverage.verdictByteOffset, 25);
    },
  );
  test('hydrate precheck owns plan summary, budget and credits', () async {
    final jobs = _FakeCoverageJobs()
      ..planSummaryResult = _summary(planVersion: 3, apiCalls: 8);
    final settings = _FakeSettings(budgetCredits: 120);
    final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
    final coverage = AiAnalysisCoverageController(
      jobs: jobs,
      settings: settings,
      owner: owner,
      snapshotId: 'snapshot-a',
      coverageOwner: 'owner-a',
    );

    coverage.prepareHydration(
      mode: AiMode.platform,
      platformCredits: 500,
      planUnavailableMessage: 'unavailable',
    );
    await coverage.hydratePrecheck();

    expect(coverage.coverageState.planSummary?.planVersion, 3);
    expect(coverage.coverageState.runBudgetCredits, isNotNull);
    expect(coverage.budgetCredits, 120);
    expect(coverage.planLoadError, isNull);
  });

  test('late plan page after restart cannot replace the new plan', () async {
    final plan = Completer<CoveragePlanSummary?>();
    final jobs = _FakeCoverageJobs()..planSummaryFuture = plan.future;
    final settings = _FakeSettings(budgetCredits: 0);
    final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
    final coverage = AiAnalysisCoverageController(
      jobs: jobs,
      settings: settings,
      owner: owner,
      snapshotId: 'snapshot-a',
      coverageOwner: 'owner-a',
    );

    coverage.prepareHydration(
      mode: AiMode.byok,
      platformCredits: null,
      planUnavailableMessage: 'unavailable',
    );
    final pending = coverage.hydratePrecheck();
    coverage.beginRestart();
    plan.complete(_summary(planVersion: 3, apiCalls: 8));
    await pending;

    expect(coverage.planGeneration, greaterThan(0));
    expect(coverage.coverageState.planSummary, isNull);
  });

  test('pause and resume serialize behind active controls', () async {
    final jobs = _FakeCoverageJobs()..resumeResult = true;
    final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
    final coverage = AiAnalysisCoverageController(
      jobs: jobs,
      settings: _FakeSettings(),
      owner: owner,
      snapshotId: 'snapshot-a',
      coverageOwner: 'owner-a',
    );

    await Future.wait([coverage.pause(), coverage.resume()]);

    expect(coverage.controlQueueEmpty, isTrue);
    expect(jobs.pauseCalls, 1);
    expect(jobs.resumeCalls, 1);
  });

  test(
    'hydrate precheck records plan-load error when summary is null',
    () async {
      final jobs = _FakeCoverageJobs()..planSummaryResult = null;
      final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
      final coverage = AiAnalysisCoverageController(
        jobs: jobs,
        settings: _FakeSettings(budgetCredits: 0),
        owner: owner,
        snapshotId: 'snapshot-a',
        coverageOwner: 'owner-a',
      );

      coverage.prepareHydration(
        mode: AiMode.byok,
        platformCredits: null,
        planUnavailableMessage: 'unavailable',
      );
      await coverage.hydratePrecheck();

      expect(coverage.planLoadError, 'unavailable');
      expect(coverage.hydrated, isTrue);
      expect(coverage.hydrating, isFalse);
    },
  );

  test(
    'unavailable message is resolved eagerly and not retained as a callback',
    () async {
      final jobs = _FakeCoverageJobs()..planSummaryResult = null;
      final coverage = AiAnalysisCoverageController(
        jobs: jobs,
        settings: _FakeSettings(budgetCredits: 0),
        owner: AiAnalysisWorkspaceController(ownerId: 'owner-a'),
        snapshotId: 'snapshot-a',
        coverageOwner: 'owner-a',
      );

      var message = 'first';
      coverage.prepareHydration(
        mode: AiMode.byok,
        platformCredits: null,
        planUnavailableMessage: message,
      );
      message = 'second';
      await coverage.hydratePrecheck();

      expect(coverage.planLoadError, 'first');
    },
  );

  test('start full coverage passes the port result through', () async {
    final jobs = _FakeCoverageJobs()
      ..startResult = StartCoverageBlocked.reasonCapBelowEstimate;
    final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
    final coverage = AiAnalysisCoverageController(
      jobs: jobs,
      settings: _FakeSettings(),
      owner: owner,
      snapshotId: 'snapshot-a',
      coverageOwner: 'owner-a',
    );

    final result = await coverage.startFullCoverage(
      mode: AiMode.platform,
      provider: _FakeProvider(),
    );

    expect(result, isA<StartCoverageBlocked>());
  });

  test(
    'start full coverage exposes the workspace start result alias',
    () async {
      final jobs = _FakeCoverageJobs()
        ..startResult = StartCoverageBlocked.reasonCapBelowEstimate;
      final coverage = AiAnalysisCoverageController(
        jobs: jobs,
        settings: _FakeSettings(),
        owner: AiAnalysisWorkspaceController(ownerId: 'owner-a'),
        snapshotId: 'snapshot-a',
        coverageOwner: 'owner-a',
      );

      final AiWorkspaceCoverageStartResult result = await coverage
          .startFullCoverage(mode: AiMode.platform, provider: _FakeProvider());

      expect(result, isA<StartCoverageBlocked>());
    },
  );

  test('raiseBudget forwards typed credits to the port', () async {
    final jobs = _FakeCoverageJobs()..raiseBudgetResult = true;
    final coverage = AiAnalysisCoverageController(
      jobs: jobs,
      settings: _FakeSettings(),
      owner: AiAnalysisWorkspaceController(ownerId: 'owner-a'),
      snapshotId: 'snapshot-a',
      coverageOwner: 'owner-a',
    );

    await coverage.raiseBudget(77);

    expect(jobs.lastRaiseBudgetCredits, 77);
    expect(jobs.lastRaiseBudgetTokens, 0);
  });

  test(
    'loadMoreVerdicts advances page count and exposes loaded rows',
    () async {
      final temp = Directory.systemTemp.createTempSync('volward-verdicts-test');
      addTearDown(() => temp.deleteSync(recursive: true));
      final store = CoverageVerdictStore(temp);
      await store.appendAll('snapshot-a', [
        const CoverageVerdict(
          path: '/a',
          verdict: 'safe',
          confidence: 'high',
          reason: 'reason',
          coverageSource: 'ai',
          sizeBytes: 1,
        ),
        const CoverageVerdict(
          path: '/b',
          verdict: 'safe',
          confidence: 'high',
          reason: 'reason',
          coverageSource: 'ai',
          sizeBytes: 1,
        ),
      ]);
      expect(await store.readAll('snapshot-a'), hasLength(2));
      expect(
        await store.readPages('snapshot-a', pageCount: 3, pageSize: 500),
        hasLength(2),
      );
      final coverage = AiAnalysisCoverageController(
        jobs: _FakeCoverageJobs(),
        settings: _FakeSettings(),
        owner: AiAnalysisWorkspaceController(ownerId: 'owner-a'),
        snapshotId: 'snapshot-a',
        coverageOwner: 'owner-a',
        verdictStoreFactory: () => store,
      );

      await coverage.loadMoreVerdicts();

      expect(coverage.verdictPageCount, 3);
      expect(coverage.verdictRows.length, 2);
    },
  );

  test('syncActiveJobAfterPrecheck filters a different snapshot', () async {
    final jobs = _FakeCoverageJobs()
      ..loadJobStateResult = _jobState('snapshot-b', CoverageJobStatus.running);
    final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
    final coverage = AiAnalysisCoverageController(
      jobs: jobs,
      settings: _FakeSettings(),
      owner: owner,
      snapshotId: 'snapshot-a',
      coverageOwner: 'owner-a',
    );

    await coverage.syncActiveJobAfterPrecheck(owner.operationGeneration);

    expect(coverage.jobState, isNull);
  });

  test('configure on owner change resets transient hydration state', () async {
    final plan = Completer<CoveragePlanSummary?>();
    final jobs = _FakeCoverageJobs()..planSummaryFuture = plan.future;
    final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
    final coverage = AiAnalysisCoverageController(
      jobs: jobs,
      settings: _FakeSettings(budgetCredits: 0),
      owner: owner,
      snapshotId: 'snapshot-a',
      coverageOwner: 'owner-a',
    );

    coverage.prepareHydration(
      mode: AiMode.byok,
      platformCredits: null,
      planUnavailableMessage: 'unavailable',
    );
    final pending = coverage.hydratePrecheck();
    coverage.configure(
      jobs: jobs,
      settings: _FakeSettings(budgetCredits: 0),
      snapshotId: 'snapshot-b',
      coverageOwner: 'owner-b',
    );
    owner.rebindOwner('owner-b');
    plan.complete(_summary(planVersion: 3, apiCalls: 8));
    await pending;

    expect(coverage.coverageState.planSummary, isNull);
    expect(coverage.hydrating, isFalse);
    expect(coverage.hydrated, isFalse);
  });

  test('evaluateCapGate is the single cap authority', () {
    final coverage = AiAnalysisCoverageController(
      jobs: _FakeCoverageJobs(),
      settings: _FakeSettings(),
      owner: AiAnalysisWorkspaceController(ownerId: 'owner-a'),
      snapshotId: 'snapshot-a',
      coverageOwner: 'owner-a',
    );
    coverage.budgetCredits = 200;
    coverage.estimatedCredits = 100;

    expect(
      coverage.evaluateCapGate(mode: AiMode.platform, platformCredits: 50),
      CoverageCapGate.insufficientAccountBalance,
    );
    coverage.budgetCredits = 100;
    expect(
      coverage.evaluateCapGate(mode: AiMode.platform, platformCredits: 200),
      CoverageCapGate.capBelowBufferedEstimate,
    );
    coverage.budgetCredits = 200;
    expect(
      coverage.evaluateCapGate(mode: AiMode.platform, platformCredits: 200),
      CoverageCapGate.ok,
    );
  });

  test('jobStateShowsBanner filters a different snapshot', () {
    final coverage = AiAnalysisCoverageController(
      jobs: _FakeCoverageJobs(),
      settings: _FakeSettings(),
      owner: AiAnalysisWorkspaceController(ownerId: 'owner-a'),
      snapshotId: 'snapshot-a',
      coverageOwner: 'owner-a',
    );
    coverage.useFullCoverage = true;

    expect(
      coverage.jobStateShowsBanner(
        _jobState('snapshot-b', CoverageJobStatus.running),
      ),
      isFalse,
    );
    expect(
      coverage.jobStateShowsBanner(
        _jobState('snapshot-a', CoverageJobStatus.running),
      ),
      isTrue,
    );
  });
}

CoveragePlanSummary _summary({
  required int planVersion,
  required int apiCalls,
}) {
  return CoveragePlanSummary(
    snapshotId: 'snapshot-a',
    rootPath: '/tmp',
    planVersion: planVersion,
    totalUnclassified: 0,
    preClassifiedCount: 0,
    groupRows: 0,
    fileRows: 0,
    estimatedPages: apiCalls,
    estimatedTreeCredits: apiCalls,
    estimatedTailCredits: 0,
    seedNodeCount: null,
  );
}

CoverageJobState _jobState(String snapshotId, CoverageJobStatus status) {
  return CoverageJobState(
    snapshotId: snapshotId,
    rootPath: '/tmp',
    planVersion: 1,
    cursor: 0,
    totalUnclassified: 1,
    analyzedFiles: 1,
    preClassifiedCount: 0,
    status: status,
    usedTokens: 0,
    usedCredits: 0,
    budgetTokens: 0,
    budgetCredits: 0,
    updatedAtMs: 0,
  );
}

class _FakeCoverageJobs implements WorkspaceCoverageJobsPort {
  CoveragePlanSummary? planSummaryResult;
  Future<CoveragePlanSummary?>? planSummaryFuture;
  StartFullCoverageResult? startResult;
  bool resumeResult = false;
  bool raiseBudgetResult = false;
  int lastRaiseBudgetTokens = -1;
  int lastRaiseBudgetCredits = -1;
  CoverageJobState? loadJobStateResult;
  int pauseCalls = 0;
  int resumeCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<CoveragePlanSummary?> planSummary(String snapshotId) {
    return planSummaryFuture ??
        Future<CoveragePlanSummary?>.value(planSummaryResult);
  }

  @override
  Future<void> pauseCoverage() async {
    pauseCalls++;
  }

  @override
  Future<StartFullCoverageResult> startFullCoverage({
    required String snapshotId,
    required AiMode mode,
    required AiProvider provider,
    int? budgetCredits,
    CoveragePlanSummary? preloadedPlanSummary,
  }) async {
    return startResult ?? const StartFullCoverageUnavailable();
  }

  @override
  Future<bool> tryRaiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
  }) async {
    lastRaiseBudgetTokens = budgetTokens;
    lastRaiseBudgetCredits = budgetCredits;
    return raiseBudgetResult;
  }

  @override
  Future<CoverageJobState?> loadJobState(String snapshotId) async {
    return loadJobStateResult;
  }

  @override
  Future<bool> tryResumeCoverage(String snapshotId) async {
    resumeCalls++;
    return resumeResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettings implements WorkspaceSettingsPort {
  _FakeSettings({this.budgetCredits = 0});

  final int budgetCredits;

  @override
  Future<({int tokens, int credits})> coverageBudgetForMode(AiMode mode) async {
    return (tokens: 0, credits: budgetCredits);
  }

  @override
  Future<int> resolveRunBudgetCredits({
    required int estimatedCredits,
    required int accountBalance,
  }) async {
    return estimatedCredits;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProvider implements AiProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OverlappingVerdictStore extends Fake implements CoverageVerdictStore {
  final appended =
      Completer<({List<CoverageVerdict> appended, int fileLength})>();
  @override
  Future<({List<CoverageVerdict> appended, int fileLength})> readAppendedSince(
    String snapshotId,
    int offset,
  ) => appended.future;
  @override
  Future<({List<CoverageVerdict> rows, int end})> readSnapshot(
    String snapshotId, {
    required int pageCount,
    required int pageSize,
    required bool preferAll,
  }) async => (
    rows: const [
      CoverageVerdict(
        path: '/terminal',
        verdict: 'keep',
        confidence: 'high',
        reason: '',
        coverageSource: 'file',
        sizeBytes: 1,
      ),
    ],
    end: 25,
  );
}
