import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_analysis_activity_model.dart';
import 'package:volward/ai/coverage_job_state.dart';

class _FakeL10n implements AiAnalysisActivityL10n {
  @override
  String substageLabel(AiActivitySubstage stage) => stage.name;

  @override
  String subtitleFor({
    required AiActivitySubstage active,
    required AiAnalysisActivityInput input,
  }) => 'sub-${active.name}';

  @override
  String progressLabel({required int analyzed, required int total}) =>
      '$analyzed/$total';

  @override
  String updatedAgo(int seconds) => '${seconds}s';

  @override
  String metricAnalyzed(String value) => 'analyzed $value';

  @override
  String metricCredits(String value) => 'credits $value';

  @override
  String metricLocalResolved(String value) => 'local $value';

  @override
  String resumingJob() => 'resuming';
}

CoverageJobState _job({
  int analyzed = 5,
  int total = 10,
  int tailCursor = 0,
  int treeDone = 0,
  CoverageJobStatus status = CoverageJobStatus.running,
}) {
  return CoverageJobState(
    snapshotId: 's',
    rootPath: '/home',
    planVersion: 1,
    cursor: 0,
    totalUnclassified: total,
    analyzedFiles: analyzed,
    preClassifiedCount: 0,
    status: status,
    usedTokens: 0,
    usedCredits: 3,
    budgetTokens: 0,
    budgetCredits: 100,
    updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    tailQueueCursor: tailCursor,
    treeNodesCompleted: treeDone,
    localResolvedFiles: 2,
  );
}

AiAnalysisActivityInput _input({
  AiActivityMacroPhase macroPhase = AiActivityMacroPhase.loading,
  bool useFullCoverage = true,
  bool candidatesBootstrapPending = false,
  bool coverageHydrating = false,
  bool coverageHydrated = false,
  bool analyzingQuick = false,
  bool resultsLayoutPending = false,
  bool resumingJob = false,
  int candidateCount = 0,
  String modeLabel = 'Platform',
  CoverageJobState? job,
}) {
  return AiAnalysisActivityInput(
    macroPhase: macroPhase,
    useFullCoverage: useFullCoverage,
    candidatesBootstrapPending: candidatesBootstrapPending,
    coverageHydrating: coverageHydrating,
    coverageHydrated: coverageHydrated,
    analyzingQuick: analyzingQuick,
    resultsLayoutPending: resultsLayoutPending,
    resumingJob: resumingJob,
    candidateCount: candidateCount,
    modeLabel: modeLabel,
    job: job,
  );
}

void main() {
  test('loading with bootstrap pending activates candidates', () {
    final model = buildAiAnalysisActivityModel(
      _input(candidatesBootstrapPending: true, candidateCount: 42),
      _FakeL10n(),
    );
    expect(model.activeSubstage, AiActivitySubstage.candidates);
    expect(model.progress, isNull);
    expect(model.visibleSubstages, [
      AiActivitySubstage.session,
      AiActivitySubstage.candidates,
      AiActivitySubstage.plan,
    ]);
    expect(model.completedSubstages, {AiActivitySubstage.session});
  });

  test('full coverage running with tail cursor active tail', () {
    final model = buildAiAnalysisActivityModel(
      _input(
        macroPhase: AiActivityMacroPhase.analyzing,
        coverageHydrated: true,
        job: _job(tailCursor: 2, treeDone: 1),
      ),
      _FakeL10n(),
    );
    expect(model.activeSubstage, AiActivitySubstage.tail);
    expect(model.progress, closeTo(0.5, 0.01));
    expect(model.progressLabel, '5/10');
    expect(model.completedSubstages, {
      AiActivitySubstage.candidates,
      AiActivitySubstage.plan,
      AiActivitySubstage.tree,
    });
  });

  test('loading full coverage hydrating activates plan', () {
    final model = buildAiAnalysisActivityModel(
      _input(coverageHydrating: true, coverageHydrated: false),
      _FakeL10n(),
    );
    expect(model.activeSubstage, AiActivitySubstage.plan);
    expect(model.completedSubstages, {
      AiActivitySubstage.session,
      AiActivitySubstage.candidates,
    });
  });

  test('loading quick path activates session when bootstrap done', () {
    final model = buildAiAnalysisActivityModel(
      _input(
        useFullCoverage: false,
        analyzingQuick: true,
        coverageHydrated: true,
      ),
      _FakeL10n(),
    );
    expect(model.activeSubstage, AiActivitySubstage.session);
    expect(model.visibleSubstages, [
      AiActivitySubstage.session,
      AiActivitySubstage.candidates,
    ]);
  });

  test('quick analyzing maps to tail with slim visible substages', () {
    final model = buildAiAnalysisActivityModel(
      _input(
        macroPhase: AiActivityMacroPhase.analyzing,
        useFullCoverage: false,
        analyzingQuick: true,
        coverageHydrated: true,
        candidateCount: 8,
      ),
      _FakeL10n(),
    );
    expect(model.activeSubstage, AiActivitySubstage.tail);
    expect(model.visibleSubstages, [
      AiActivitySubstage.tail,
      AiActivitySubstage.finalize,
    ]);
    expect(model.progress, isNull);
  });

  test('quick analyzing bootstrap pending shows candidates chip', () {
    final model = buildAiAnalysisActivityModel(
      _input(
        macroPhase: AiActivityMacroPhase.analyzing,
        useFullCoverage: false,
        analyzingQuick: true,
        candidatesBootstrapPending: true,
      ),
      _FakeL10n(),
    );
    expect(model.activeSubstage, AiActivitySubstage.candidates);
    expect(model.visibleSubstages, [
      AiActivitySubstage.candidates,
      AiActivitySubstage.tail,
      AiActivitySubstage.finalize,
    ]);
  });

  test('full analyzing running without tail cursor activates tree', () {
    final model = buildAiAnalysisActivityModel(
      _input(
        macroPhase: AiActivityMacroPhase.analyzing,
        coverageHydrated: true,
        job: _job(tailCursor: 0, treeDone: 0),
      ),
      _FakeL10n(),
    );
    expect(model.activeSubstage, AiActivitySubstage.tree);
    expect(model.completedSubstages, {
      AiActivitySubstage.candidates,
      AiActivitySubstage.plan,
    });
  });

  test('results layout pending activates finalize', () {
    final model = buildAiAnalysisActivityModel(
      _input(
        macroPhase: AiActivityMacroPhase.resultsBusy,
        coverageHydrated: true,
        resultsLayoutPending: true,
        job: _job(analyzed: 10, total: 10),
      ),
      _FakeL10n(),
    );
    expect(model.activeSubstage, AiActivitySubstage.finalize);
    expect(model.progress, closeTo(1.0, 0.01));
  });

  test('metrics derive from coverage job', () {
    final model = buildAiAnalysisActivityModel(
      _input(
        macroPhase: AiActivityMacroPhase.analyzing,
        coverageHydrated: true,
        job: _job(analyzed: 7, total: 20),
      ),
      _FakeL10n(),
    );
    expect(
      model.metrics.map((m) => m.label),
      containsAll(['analyzed 7', 'credits 3', 'local 2']),
    );
    expect(model.lastUpdated, isNotNull);
  });

  test('resuming job augments subtitle', () {
    final model = buildAiAnalysisActivityModel(
      _input(
        macroPhase: AiActivityMacroPhase.loading,
        resumingJob: true,
        coverageHydrated: true,
      ),
      _FakeL10n(),
    );
    expect(model.subtitle, contains('resuming'));
    expect(model.subtitle, contains('sub-session'));
  });
}
