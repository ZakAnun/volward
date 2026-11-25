import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:volward/snapshot_cache.dart';
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
import 'package:volward/ai/coverage_verdict_store.dart';
import 'package:volward/capabilities/capability_models.dart';
import 'package:volward/features/ai_coverage/ai_analysis_workspace_config.dart';
import 'package:volward/features/ai_coverage/controllers/ai_analysis_workspace_controller.dart';
import 'package:volward/features/ai_coverage/controllers/ai_analysis_workspace_page_controller.dart';
import 'package:volward/features/ai_coverage/ports/workspace_ports.dart';

import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_presenter.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_state.dart';

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

  testWidgets(
    'coverage verdict completion merges its size into immutable bootstrap state',
    (tester) async {
      final gateway = _FakeGateway()
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
                ),
              )..initialize(bootstrap: false);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.runAsync(controller.bootstrapForTest);

      await controller.applyCoverageVerdictRowsAsync(const [
        CoverageVerdict(
          path: '/tmp/completed-result',
          verdict: 'review_needed',
          confidence: 'high',
          reason: 'large cache',
          coverageSource: 'ai',
          sizeBytes: 42,
        ),
      ]);

      expect(controller.sizeByPath['/tmp/completed-result'], 42);
      expect(controller.verdicts.single.path, '/tmp/completed-result');
      controller.dispose();
    },
  );

  testWidgets(
    'view state bounds pending preview, reuses it across progress, and hands off terminal results after scrolling',
    (tester) async {
      final presenter = _FramePresenter();
      final jobs = _FakeRaiseCoverageJobs();
      final gateway = _FakeGateway()
        ..mode = AiMode.platform
        ..provider = _FakePlatformProvider()
        ..candidatesJson = jsonEncode({
          'pre_classified': [],
          'unknown_candidates': List.generate(
            180,
            (i) => {'path': '/tmp/$i', 'size_bytes': 1, 'is_dir': false},
          ),
          'estimated_input_tokens': 0,
        });
      final controller = AiAnalysisWorkspacePageController(
        AiAnalysisWorkspaceConfig(
          snapshotId: 'snapshot-1',
          targetLabel: 'Downloads',
          onExit: () {},
          onOpenSettings: () {},
          onDeletingChanged: (_) {},
          onDeleteCompleted: () {},
          gateway: gateway,
          presenter: presenter,
          ports: AiWorkspacePorts.fromCoverageJobs(coverageJobs: jobs),
        ),
      )..initialize(bootstrap: false);
      await tester.runAsync(controller.bootstrapForTest);
      controller.useFullCoverage = true;
      controller.coverageUserEngagedFullRun = true;
      const running = CoverageJobState(
        snapshotId: 'snapshot-1',
        rootPath: '/tmp',
        planVersion: 3,
        cursor: 0,
        totalUnclassified: 3000000,
        analyzedFiles: 0,
        preClassifiedCount: 0,
        status: CoverageJobStatus.running,
        usedTokens: 0,
        usedCredits: 0,
        budgetTokens: 0,
        budgetCredits: 100,
        updatedAtMs: 1,
      );
      controller.coverageController.jobState = running;
      final first = controller.buildViewState().results;
      List<AiVerdict> pending(AiWorkspaceResultsState state) => state.groups
          .expand((g) => g.items)
          .where((v) => v.verdict == 'unanalyzed')
          .toList();
      expect(pending(first), hasLength(129));
      final paths = controller.resultsController.verdictPaths;
      controller.coverageController.jobState = running.copyWith(updatedAtMs: 2);
      final unchanged = controller.buildViewState().results;
      expect(identical(first.groups.first, unchanged.groups.first), isTrue);
      controller.coverageController.jobState = running.copyWith(
        analyzedFiles: 1,
      );
      expect(
        pending(controller.buildViewState().results).map((v) => v.path),
        contains('coverage://pending/2999871'),
      );
      expect(
        identical(paths, controller.resultsController.verdictPaths),
        isTrue,
      );
      controller.resultsController.replaceVerdicts(const [
        AiVerdict(
          path: '/tmp/0',
          verdict: 'keep',
          confidence: 'high',
          reason: '',
        ),
      ]);
      final updated = pending(
        controller.buildViewState().results,
      ).map((v) => v.path);
      expect(updated, isNot(contains('/tmp/0')));
      expect(updated, contains('coverage://pending/2999872'));
      await tester.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp(
          'terminal-scroll-',
        );
        final previous = SnapshotCache.cacheDirForTest;
        SnapshotCache.cacheDirForTest = directory;
        try {
          await CoverageVerdictStore(directory).appendAll('snapshot-1', const [
            CoverageVerdict(
              path: '/tmp/terminal',
              verdict: 'keep',
              confidence: 'high',
              reason: 'done',
              coverageSource: 'file',
              sizeBytes: 10,
            ),
          ]);
          controller.phase = AiWorkspaceDisplayState.analyzing;
          controller.analyzing = true;
          controller.onResultsScrollStart();
          jobs.emit(
            running.copyWith(
              status: CoverageJobStatus.completed,
              analyzedFiles: 3000000,
            ),
          );
          await Future<void>.delayed(Duration.zero);
          final terminal = controller.buildViewState();
          expect(terminal.activity.job?.status, CoverageJobStatus.completed);
          expect(terminal.results.verdicts.single.path, '/tmp/0');
          final finished = Completer<void>();
          controller.addListener(() {
            if (!finished.isCompleted &&
                controller.verdicts.any((v) => v.path == '/tmp/terminal')) {
              finished.complete();
            }
          });
          controller.onResultsScrollEnd();
          presenter.flush();
          await finished.future.timeout(const Duration(seconds: 5));
          final settled = controller.buildViewState().results;
          expect(settled.verdicts.single.path, '/tmp/terminal');
          expect(pending(settled), isEmpty);
        } finally {
          SnapshotCache.cacheDirForTest = previous;
          await directory.delete(recursive: true);
        }
      });
      controller.dispose();
    },
  );

  testWidgets('scrolling defers asynchronously refreshed coverage verdicts', (
    tester,
  ) async {
    final gateway = _FakeGateway()
      ..candidatesJson =
          '{"pre_classified":[],"unknown_candidates":[],'
          '"estimated_input_tokens":0}';
    final presenter = _FramePresenter();
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
                presenter: presenter,
              ),
            )..initialize(bootstrap: false);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.runAsync(controller.bootstrapForTest);

    await tester.runAsync(() async {
      controller.resultsController.setSelectedPaths(['/tmp/prepared']);
      final preparing = controller.applyHeavyResultsPresentation(
        verdicts: const [
          AiVerdict(
            path: '/tmp/prepared',
            verdict: 'review_needed',
            confidence: 'high',
            reason: 'test',
          ),
        ],
        preserveUiState: true,
      );
      controller.onResultsScrollStart();
      controller.resultsController.toggleSelection('/tmp/prepared', false);
      controller.resultsController.setReviewDecision(
        '/tmp/prepared',
        WorkspaceReviewDecision.keep,
      );
      await preparing;
    });
    expect(controller.verdicts, isEmpty);
    controller.onResultsScrollEnd();
    presenter.flush();
    expect(controller.verdicts.single.path, '/tmp/prepared');
    expect(controller.selected, isEmpty);
    expect(
      controller.reviewDecisions['/tmp/prepared'],
      WorkspaceReviewDecision.keep,
    );
    final preparedCache = controller.resultsController.normalizedGroupsCache;
    expect(
      identical(controller.resultsProjection.normalizedGroups, preparedCache),
      isTrue,
    );
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'coverage-scroll-',
      );
      final previous = SnapshotCache.cacheDirForTest;
      SnapshotCache.cacheDirForTest = directory;
      try {
        await CoverageVerdictStore(directory).appendAll('snapshot-1', const [
          CoverageVerdict(
            path: '/tmp/deferred-during-scroll',
            verdict: 'safe_to_remove',
            confidence: 'high',
            reason: 'cache',
            coverageSource: 'local_rule',
            sizeBytes: 42,
          ),
        ]);
        final reading = controller.refreshVerdictsInternal();
        controller.onResultsScrollStart();
        await reading;
        expect(
          controller.pendingVerdictRowsAfterScroll!.single.path,
          '/tmp/deferred-during-scroll',
        );
      } finally {
        SnapshotCache.cacheDirForTest = previous;
        await directory.delete(recursive: true);
      }
    });
    expect(controller.verdicts.single.path, '/tmp/prepared');
    expect(
      controller.sizeByPath,
      isNot(contains('/tmp/deferred-during-scroll')),
    );

    controller.onResultsScrollEnd();
    controller.onResultsScrollStart();
    presenter.flush();
    expect(controller.verdicts.single.path, '/tmp/prepared');
    await controller.applyCoverageVerdictRowsAsync(const [
      CoverageVerdict(
        path: '/tmp/latest',
        verdict: 'keep',
        confidence: 'high',
        reason: 'keep',
        coverageSource: 'local_rule',
        sizeBytes: 84,
      ),
    ]);
    controller.onResultsScrollEnd();
    presenter.flush();
    expect(controller.verdicts.single.path, '/tmp/latest');
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

class _FramePresenter extends Fake implements AiAnalysisWorkspacePresenter {
  final callbacks = <void Function()>[];
  @override
  void schedulePostFrame(void Function() callback) => callbacks.add(callback);
  void flush() {
    final current = callbacks.toList();
    callbacks.clear();
    for (final callback in current) {
      callback();
    }
  }
}
