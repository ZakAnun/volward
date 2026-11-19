import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/ai/ai_analysis_gateway.dart';
import 'package:volward/ai/ai_coverage_coordinator.dart';
import 'package:volward/ai/ai_coverage_service.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/ai/ai_conclusion_synthesis.dart';
import 'package:volward/ai/cancel_token.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_models.dart';
import 'package:volward/capabilities/capability_models.dart';
import 'package:volward/features/ai_coverage/ai_analysis_workspace_config.dart';
import 'package:volward/features/ai_coverage/controllers/ai_analysis_workspace_controller.dart';
import 'package:volward/features/ai_coverage/controllers/ai_analysis_workspace_page_controller.dart';
import 'package:volward/features/ai_coverage/ports/workspace_ports.dart';

void main() {
  testWidgets('page controller owns candidate bootstrap and display state', (
    tester,
  ) async {
    final gateway = _FakeGateway()
      ..candidatesJson =
          '{"pre_classified":[],"unknown_candidates":['
          '{"path":"/tmp/a","size_bytes":1,"is_dir":false,'
          '"deletable":true}],"estimated_input_tokens":10}';
    late AiAnalysisWorkspacePageController controller;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            controller = AiAnalysisWorkspacePageController(
              AiAnalysisWorkspaceConfig(
                snapshotId: 'snapshot-1',
                targetLabel: 'Downloads',
                onExit: () {},
                onOpenSettings: () {},
                onDeletingChanged: (_) {},
                onDeleteCompleted: () {},
                gateway: gateway,
              ),
            )..initialize(bootstrap: false);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.runAsync(controller.bootstrapForTest);
    await tester.pump();

    expect(controller.initialized, isTrue);
    expect(controller.displayState, AiWorkspaceDisplayState.results);
    expect(controller.candidateCount, 1);
    expect(controller.candidatesPending, isFalse);
    expect(gateway.candidateRequests, ['snapshot-1']);

    controller.dispose();
  });

  testWidgets('page raise action routes typed credits through coverage owner', (
    tester,
  ) async {
    final jobs = _FakeRaiseCoverageJobs();
    final gateway = _FakeGateway()
      ..mode = AiMode.platform
      ..provider = _FakePlatformProvider()
      ..candidatesJson =
          '{"pre_classified":[],"unknown_candidates":[],'
          '"estimated_input_tokens":0}';
    late AiAnalysisWorkspacePageController controller;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            controller = AiAnalysisWorkspacePageController(
              AiAnalysisWorkspaceConfig(
                snapshotId: 'snapshot-1',
                targetLabel: 'Downloads',
                onExit: () {},
                onOpenSettings: () {},
                onDeletingChanged: (_) {},
                onDeleteCompleted: () {},
                gateway: gateway,
                ports: AiWorkspacePorts.fromCoverageJobs(coverageJobs: jobs),
              ),
            )..initialize(bootstrap: false);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.runAsync(controller.bootstrapForTest);
    await tester.pump();

    jobs.emit(
      const CoverageJobState(
        snapshotId: 'snapshot-1',
        rootPath: '/tmp',
        planVersion: 3,
        cursor: 0,
        totalUnclassified: 0,
        analyzedFiles: 0,
        preClassifiedCount: 0,
        status: CoverageJobStatus.paused,
        pauseReason: CoveragePauseReason.budget,
        usedTokens: 0,
        usedCredits: 0,
        budgetTokens: 0,
        budgetCredits: 100,
        updatedAtMs: 1,
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      await controller.viewActions.raiseCoverageBudget(150);
    });
    await tester.pump();

    expect(jobs.lastRaiseBudgetCredits, 150);
    expect(jobs.lastRaiseBudgetTokens, 0);

    controller.dispose();
  });

  testWidgets('page delete action routes through delete owner', (tester) async {
    final gateway = _FakeGateway()
      ..candidatesJson =
          '{"pre_classified":[{"path":"/tmp/a","size_bytes":10,'
          '"is_dir":false,"deletable":true,"confidence":"high"}],'
          '"unknown_candidates":[],"estimated_input_tokens":0}'
      ..deleteReports.add({
        'deleted_count': 1,
        'freed_bytes': 10,
        'failed_paths': const <String>[],
      })
      ..deleteReports.add({
        'deleted_count': 1,
        'freed_bytes': 10,
        'failed_paths': const <String>[],
      });
    var completed = 0;
    late AiAnalysisWorkspacePageController controller;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            controller = AiAnalysisWorkspacePageController(
              AiAnalysisWorkspaceConfig(
                snapshotId: 'snapshot-1',
                targetLabel: 'Downloads',
                onExit: () {},
                onOpenSettings: () {},
                onDeletingChanged: (_) {},
                onDeleteCompleted: () => completed++,
                gateway: gateway,
              ),
            )..initialize(bootstrap: false);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.runAsync(controller.bootstrapForTest);
    await tester.pump();

    controller.viewActions.toggleSelection('/tmp/a');
    expect(
      controller.buildViewState().results.selectedPaths,
      contains('/tmp/a'),
    );
    await tester.runAsync(() => controller.viewActions.deleteSelected());
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(gateway.deleteCalls, hasLength(2));
    expect(gateway.deleteCalls.first.dryRun, isTrue);
    expect(gateway.deleteCalls.last.dryRun, isFalse);
    expect(gateway.deleteCalls.last.rescanAfterDelete, isTrue);
    expect(completed, 1);

    controller.dispose();
  });
}

class _FakeGateway implements AiAnalysisGateway {
  String? candidatesJson;
  AiMode mode = AiMode.byok;
  AiProvider? provider;
  final candidateRequests = <String>[];
  final deleteCalls =
      <({List<String> targets, bool dryRun, bool rescanAfterDelete})>[];
  final deleteReports = <Map<String, dynamic>>[];

  @override
  Future<String?> buildCandidates(String snapshotId) async {
    candidateRequests.add(snapshotId);
    return candidatesJson;
  }

  @override
  Future<AiMode> getMode() async => mode;

  @override
  Future<AiProvider?> resolveProvider() async => provider;

  @override
  Future<bool> isPrivacyAccepted() async => true;

  @override
  Future<void> setPrivacyAccepted(bool value) async {}

  @override
  String? loadResult(String key) => null;

  @override
  bool saveResult(String snapshotId, String resultJson) => true;

  @override
  Future<ByokTokenUsageTotals> recordByokTokenUsage({
    required int inputTokens,
    required int outputTokens,
    required int totalTokens,
    required bool estimated,
    required bool partial,
  }) async => ByokTokenUsageTotals.empty;

  @override
  Future<Map<String, dynamic>> deleteEntries(
    List<String> targets, {
    String? snapshotId,
    bool dryRun = false,
    bool rescanAfterDelete = false,
  }) async {
    deleteCalls.add((
      targets: targets,
      dryRun: dryRun,
      rescanAfterDelete: rescanAfterDelete,
    ));
    if (deleteReports.isNotEmpty) return deleteReports.removeAt(0);
    return const {'deleted_count': 0, 'freed_bytes': 0, 'failed_paths': []};
  }

  @override
  Future<CapabilityAnalysisResult> analyzeCapability({
    required String snapshotId,
    required Capability capability,
    AnalysisOptions? options,
  }) => throw UnimplementedError();
}

class _FakePlatformProvider implements AiProvider {
  @override
  Future<AnalyzeResult> analyze(
    List<AiCandidate> candidates, {
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<AiQuotaInfo?> queryQuota() async =>
      const AiQuotaInfo(creditsRemaining: 500, creditsTotal: 1000);

  @override
  Future<AiConclusionSynthesisResponse> synthesizeConclusion(
    AiConclusionSynthesisRequest request, {
    CancelToken? cancelToken,
  }) => throw UnimplementedError();
}

class _FakeRaiseCoverageJobs implements AiCoverageJobs {
  void Function(CoverageJobState)? _listener;
  int? lastRaiseBudgetCredits;
  int? lastRaiseBudgetTokens;

  void emit(CoverageJobState state) => _listener?.call(state);

  @override
  bool get isAvailable => true;

  @override
  void addJobStateListener(void Function(CoverageJobState) listener) {
    _listener = listener;
  }

  @override
  void removeJobStateListener(void Function(CoverageJobState) listener) {
    if (identical(_listener, listener)) _listener = null;
  }

  @override
  Future<CoverageJobState?> loadJobState(String snapshotId) async => null;

  @override
  Future<CoveragePlanSummary?> planSummary(String snapshotId) async => null;

  @override
  void invalidatePlanSummaryCache() {}

  @override
  Future<AiCoverageService?> prepareService(AiProvider provider) async => null;

  @override
  Future<StartFullCoverageResult> startFullCoverage({
    required String snapshotId,
    required AiMode mode,
    required AiProvider provider,
    int? budgetCredits,
    CoveragePlanSummary? preloadedPlanSummary,
  }) async => const StartFullCoverageLocalOnly();

  @override
  Future<void> pauseCoverage() async {}

  @override
  Future<void> cancelCoverage(String snapshotId) async {}

  @override
  Future<bool> tryResumeCoverage(String snapshotId) async => true;

  @override
  Future<bool> tryRaiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
  }) async {
    lastRaiseBudgetCredits = budgetCredits;
    lastRaiseBudgetTokens = budgetTokens;
    return true;
  }
}
