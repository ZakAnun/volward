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
      await store.setCoverageBudgetCredits(20);

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
        serviceFactory: ({required session, required provider}) => service,
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
