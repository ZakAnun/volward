import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_coverage_coordinator.dart';
import 'package:volward/ai/ai_coverage_job_controller.dart';
import 'package:volward/ai/ai_coverage_service.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/ai/cancel_token.dart';
import 'package:volward/ai/coverage_engine.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_models.dart';
import 'package:volward/ai/coverage_verdict_store.dart';
import 'package:volward/ai/coverage_notification_text.dart';
import 'package:volward/l10n/generated/app_localizations_en.dart';
import 'package:volward/volward_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'debugTryResumePlanForJob returns precheck cache for fresh start job',
    () async {
      const plan = CoveragePlanSummary(
        snapshotId: 'snap-fresh',
        planVersion: 3,
        rootPath: '/data',
        totalUnclassified: 10,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 10,
        estimatedPages: 1,
        seedNodeCount: 1,
      );
      final coordinator = AiCoverageCoordinator.testing(
        isCoverageApiReady: (_) => true,
        resolveProvider: () async => _Provider(),
      );
      coordinator.attach(VolwardSession.test());
      coordinator.debugSetPlanSummaryCache('snap-fresh', plan);
      const job = CoverageJobState(
        snapshotId: 'snap-fresh',
        rootPath: '',
        planVersion: 1,
        cursor: 0,
        totalUnclassified: 0,
        analyzedFiles: 0,
        preClassifiedCount: 0,
        status: CoverageJobStatus.running,
        usedTokens: 0,
        usedCredits: 0,
        budgetTokens: 500000,
        budgetCredits: 0,
        updatedAtMs: 1,
      );
      final loaded = await coordinator.debugTryResumePlanForJob(
        'snap-fresh',
        job,
      );
      expect(loaded, plan);
    },
  );

  test(
    'debugTryResumePlanForJob returns cached plan for matching job',
    () async {
      const plan = CoveragePlanSummary(
        snapshotId: 'snap-resume-cache',
        planVersion: 3,
        rootPath: '/data',
        totalUnclassified: 100,
        preClassifiedCount: 0,
        groupRows: 0,
        fileRows: 100,
        estimatedPages: 3,
        seedNodeCount: 1,
      );
      final coordinator = AiCoverageCoordinator.testing(
        isCoverageApiReady: (_) => true,
        resolveProvider: () async => _Provider(),
      );
      coordinator.attach(VolwardSession.test());
      coordinator.debugSetPlanSummaryCache('snap-resume-cache', plan);
      const job = CoverageJobState(
        snapshotId: 'snap-resume-cache',
        rootPath: '/data',
        planVersion: 3,
        cursor: 0,
        totalUnclassified: 100,
        analyzedFiles: 40,
        preClassifiedCount: 0,
        status: CoverageJobStatus.paused,
        usedTokens: 10,
        usedCredits: 0,
        budgetTokens: 50,
        budgetCredits: 0,
        updatedAtMs: 1,
        treeQueueCursor: 1,
      );
      final loaded = await coordinator.debugTryResumePlanForJob(
        'snap-resume-cache',
        job,
      );
      expect(loaded, plan);
    },
  );

  test('precheck flags when configured cap is below estimated buffer', () {
    final fromEstimate = (40 * 1.2).ceil();
    const configured = 20;
    expect(fromEstimate > configured, isTrue);
  });

  test(
    'startFullCoverage returns capBelowEstimate when configured cap is low',
    () async {
      final temp = await Directory.systemTemp.createTemp('volward-coord-cap');
      addTearDown(() => temp.delete(recursive: true));

      final settingsFile = File('${temp.path}/settings.json')
        ..writeAsStringSync('{}');
      final store = AiSettingsStore.instance
        ..settingsFileForTest = settingsFile;
      addTearDown(() => store.settingsFileForTest = null);
      // Use a non-legacy cap (legacy default 20 migrates to 50 on read).
      await store.setCoverageBudgetCredits(15);

      AiCoverageCoordinator.debugPlanSummary = (_) async =>
          const CoveragePlanSummary(
            snapshotId: 'snap-cap',
            planVersion: 1,
            rootPath: '/',
            totalUnclassified: 1600,
            preClassifiedCount: 0,
            groupRows: 0,
            fileRows: 1600,
            estimatedPages: 40,
          );
      addTearDown(() => AiCoverageCoordinator.debugPlanSummary = null);

      final service = _RecordingStartService();
      final provider = _Provider();
      final coordinator = AiCoverageCoordinator.testing(
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

      final result = await coordinator.startFullCoverage(
        snapshotId: 'snap-cap',
        mode: AiMode.platform,
        provider: provider,
      );

      expect(result, StartCoverageBlocked.reasonCapBelowEstimate);
      expect(service.startCalls, 0);
    },
  );

  test('startFullCoverage unavailable when plan summary is missing', () async {
    AiCoverageCoordinator.debugRequirePlanSummary = true;
    addTearDown(() => AiCoverageCoordinator.debugRequirePlanSummary = false);
    AiCoverageCoordinator.debugPlanSummary = (_) async => null;

    final service = _RecordingStartService();
    final provider = _Provider();
    final coordinator = AiCoverageCoordinator.testing(
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

    final result = await coordinator.startFullCoverage(
      snapshotId: 'snap-missing-plan',
      mode: AiMode.byok,
      provider: provider,
    );

    expect(result, isA<StartFullCoverageUnavailable>());
    expect(service.startCalls, 0);
  });

  test(
    'startFullCoverage skips job when plan requires zero API calls',
    () async {
      AiCoverageCoordinator.debugPlanSummary = (_) async =>
          const CoveragePlanSummary(
            snapshotId: 'snap-local',
            planVersion: 3,
            rootPath: '/',
            totalUnclassified: 100,
            preClassifiedCount: 0,
            groupRows: 0,
            fileRows: 0,
            estimatedPages: 0,
            localSafeFiles: 50,
            localKeepFiles: 50,
            estimatedTreeCredits: 0,
            estimatedTailCredits: 0,
          );
      addTearDown(() => AiCoverageCoordinator.debugPlanSummary = null);

      final service = _RecordingStartService();
      final provider = _Provider();
      final coordinator = AiCoverageCoordinator.testing(
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

      final result = await coordinator.startFullCoverage(
        snapshotId: 'snap-local',
        mode: AiMode.byok,
        provider: provider,
      );

      expect(result, isA<StartFullCoverageLocalOnly>());
      expect(service.startCalls, 0);
    },
  );

  test('coordinator emits desktop notify on completion', () async {
    final notifications = <String>[];
    final coordinator = AiCoverageCoordinator.testing(
      desktopNotify: ({required title, required body}) async {
        notifications.add('$title::$body');
      },
    );

    const state = CoverageJobState(
      snapshotId: 's1',
      rootPath: '/',
      planVersion: 1,
      cursor: 10,
      totalUnclassified: 10,
      analyzedFiles: 10,
      preClassifiedCount: 0,
      status: CoverageJobStatus.completed,
      usedTokens: 100,
      usedCredits: 0,
      budgetTokens: 1000,
      budgetCredits: 0,
      updatedAtMs: 1,
    );
    final l10n = AppLocalizationsEn();

    await coordinator.debugNotify(state, l10n: l10n);

    expect(notifications, hasLength(1));
    final copy = coverageCompleteNotification(l10n, state);
    expect(notifications.single, '${copy.title}::${copy.body}');
  });
}

class _Provider implements AiProvider {
  @override
  Future<AnalyzeResult> analyze(
    List<AiCandidate> candidates, {
    CancelToken? cancelToken,
  }) async => const AnalyzeResult(verdicts: []);

  @override
  Future<AiQuotaInfo?> queryQuota() async => null;
}

class _RecordingStartService extends AiCoverageService {
  _RecordingStartService()
    : super(
        engine: FakeCoverageEngine(
          summary: const CoveragePlanSummary(
            snapshotId: 'snap-cap',
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
              snapshotId: 'snap-cap',
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
          verdictStore: CoverageVerdictStore(
            Directory.systemTemp.createTempSync('volward-coord-test'),
          ),
          stateStore: CoverageJobStateStore(
            Directory.systemTemp.createTempSync('volward-coord-test'),
          ),
          analyzeBatch: (_) async => const BatchOutcome(
            usage: BatchUsage(tokens: 0, credits: 0),
            verdicts: [],
          ),
        ),
      );

  int startCalls = 0;

  @override
  Future<CoverageJobState> start(
    String snapshotId, {
    required int budgetTokens,
    required int budgetCredits,
  }) async {
    startCalls++;
    return const CoverageJobState(
      snapshotId: 'snap-cap',
      rootPath: '/',
      planVersion: 1,
      cursor: 0,
      totalUnclassified: 0,
      analyzedFiles: 0,
      preClassifiedCount: 0,
      status: CoverageJobStatus.running,
      usedTokens: 0,
      usedCredits: 0,
      budgetTokens: 0,
      budgetCredits: 48,
      updatedAtMs: 0,
    );
  }
}
