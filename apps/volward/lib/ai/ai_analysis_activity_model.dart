import 'coverage_job_state.dart';

enum AiActivitySubstage { session, candidates, plan, tree, tail, finalize }

enum AiActivityMacroPhase { loading, analyzing, resultsBusy }

class AiActivityMetric {
  const AiActivityMetric({required this.label, required this.value});

  final String label;
  final String value;
}

class AiAnalysisActivityInput {
  const AiAnalysisActivityInput({
    required this.macroPhase,
    required this.useFullCoverage,
    required this.candidatesBootstrapPending,
    required this.coverageHydrating,
    required this.coverageHydrated,
    required this.analyzingQuick,
    required this.resultsLayoutPending,
    required this.resumingJob,
    required this.candidateCount,
    required this.modeLabel,
    this.job,
  });

  final AiActivityMacroPhase macroPhase;
  final bool useFullCoverage;
  final bool candidatesBootstrapPending;
  final bool coverageHydrating;
  final bool coverageHydrated;
  final bool analyzingQuick;
  final bool resultsLayoutPending;
  final bool resumingJob;
  final int candidateCount;
  final String modeLabel;
  final CoverageJobState? job;
}

abstract class AiAnalysisActivityL10n {
  String substageLabel(AiActivitySubstage stage);

  String subtitleFor({
    required AiActivitySubstage active,
    required AiAnalysisActivityInput input,
  });

  String progressLabel({required int analyzed, required int total});

  String updatedAgo(int seconds);

  String metricAnalyzed(String value);

  String metricCredits(String value);

  String metricLocalResolved(String value);

  String resumingJob();
}

class AiAnalysisActivityModel {
  const AiAnalysisActivityModel({
    required this.visibleSubstages,
    required this.activeSubstage,
    required this.completedSubstages,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.progressLabel,
    required this.metrics,
    required this.lastUpdated,
  });

  final List<AiActivitySubstage> visibleSubstages;
  final AiActivitySubstage activeSubstage;
  final Set<AiActivitySubstage> completedSubstages;
  final String title;
  final String subtitle;
  final double? progress;
  final String? progressLabel;
  final List<AiActivityMetric> metrics;
  final DateTime? lastUpdated;
}

AiAnalysisActivityModel buildAiAnalysisActivityModel(
  AiAnalysisActivityInput input,
  AiAnalysisActivityL10n l10n,
) {
  final visibleSubstages = _visibleSubstages(input);
  final activeSubstage = _resolveActiveSubstage(input);
  final completedSubstages = _completedSubstages(
    visibleSubstages,
    activeSubstage,
  );

  final job = input.job;
  final double? progress;
  final String? progressLabel;
  if (job != null && job.totalUnclassified > 0) {
    final ratio = job.analyzedFiles / job.totalUnclassified;
    progress = ratio.clamp(0.0, 1.0);
    progressLabel = l10n.progressLabel(
      analyzed: job.analyzedFiles,
      total: job.totalUnclassified,
    );
  } else {
    progress = null;
    progressLabel = null;
  }

  var subtitle = l10n.subtitleFor(active: activeSubstage, input: input);
  if (input.resumingJob) {
    subtitle = '$subtitle · ${l10n.resumingJob()}';
  }

  final metrics = _buildMetrics(input, l10n, job);
  final lastUpdated = job == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(job.updatedAtMs);

  return AiAnalysisActivityModel(
    visibleSubstages: visibleSubstages,
    activeSubstage: activeSubstage,
    completedSubstages: completedSubstages,
    title: l10n.substageLabel(activeSubstage),
    subtitle: subtitle,
    progress: progress,
    progressLabel: progressLabel,
    metrics: metrics,
    lastUpdated: lastUpdated,
  );
}

List<AiActivitySubstage> _visibleSubstages(AiAnalysisActivityInput input) {
  switch (input.macroPhase) {
    case AiActivityMacroPhase.loading:
      if (input.useFullCoverage) {
        return const [
          AiActivitySubstage.session,
          AiActivitySubstage.candidates,
          AiActivitySubstage.plan,
        ];
      }
      return const [AiActivitySubstage.session, AiActivitySubstage.candidates];
    case AiActivityMacroPhase.analyzing:
    case AiActivityMacroPhase.resultsBusy:
      if (input.analyzingQuick || !input.useFullCoverage) {
        final stages = <AiActivitySubstage>[];
        if (input.candidatesBootstrapPending) {
          stages.add(AiActivitySubstage.candidates);
        }
        stages.addAll(const [
          AiActivitySubstage.tail,
          AiActivitySubstage.finalize,
        ]);
        return stages;
      }
      return const [
        AiActivitySubstage.candidates,
        AiActivitySubstage.plan,
        AiActivitySubstage.tree,
        AiActivitySubstage.tail,
        AiActivitySubstage.finalize,
      ];
  }
}

AiActivitySubstage _resolveActiveSubstage(AiAnalysisActivityInput input) {
  switch (input.macroPhase) {
    case AiActivityMacroPhase.loading:
      return _resolveLoadingActive(input);
    case AiActivityMacroPhase.analyzing:
    case AiActivityMacroPhase.resultsBusy:
      if (input.analyzingQuick || !input.useFullCoverage) {
        return _resolveQuickActive(input);
      }
      return _resolveFullActive(input);
  }
}

AiActivitySubstage _resolveLoadingActive(AiAnalysisActivityInput input) {
  if (input.candidatesBootstrapPending) {
    return AiActivitySubstage.candidates;
  }
  if (input.useFullCoverage &&
      (!input.coverageHydrated || input.coverageHydrating)) {
    return AiActivitySubstage.plan;
  }
  return AiActivitySubstage.session;
}

AiActivitySubstage _resolveQuickActive(AiAnalysisActivityInput input) {
  if (input.resultsLayoutPending) {
    return AiActivitySubstage.finalize;
  }
  if (input.candidatesBootstrapPending) {
    return AiActivitySubstage.candidates;
  }
  return AiActivitySubstage.tail;
}

AiActivitySubstage _resolveFullActive(AiAnalysisActivityInput input) {
  if (input.resultsLayoutPending) {
    return AiActivitySubstage.finalize;
  }
  if (input.candidatesBootstrapPending) {
    return AiActivitySubstage.candidates;
  }
  if (!input.coverageHydrated || input.coverageHydrating) {
    return AiActivitySubstage.plan;
  }
  final job = input.job;
  if (job != null && job.status == CoverageJobStatus.running) {
    if (job.tailQueueCursor > 0 && job.treeNodesCompleted > 0) {
      return AiActivitySubstage.tail;
    }
    return AiActivitySubstage.tree;
  }
  return AiActivitySubstage.tail;
}

Set<AiActivitySubstage> _completedSubstages(
  List<AiActivitySubstage> visible,
  AiActivitySubstage active,
) {
  final activeIndex = visible.indexOf(active);
  if (activeIndex <= 0) {
    return {};
  }
  return visible.sublist(0, activeIndex).toSet();
}

List<AiActivityMetric> _buildMetrics(
  AiAnalysisActivityInput input,
  AiAnalysisActivityL10n l10n,
  CoverageJobState? job,
) {
  if (job == null) {
    return const [];
  }

  final metrics = <AiActivityMetric>[
    AiActivityMetric(
      label: l10n.metricAnalyzed('${job.analyzedFiles}'),
      value: '',
    ),
    AiActivityMetric(
      label: l10n.metricCredits('${job.usedCredits}'),
      value: '',
    ),
  ];

  if (input.useFullCoverage) {
    metrics.add(
      AiActivityMetric(
        label: l10n.metricLocalResolved('${job.localResolvedFiles}'),
        value: '',
      ),
    );
  }

  final secondsAgo =
      (DateTime.now().millisecondsSinceEpoch - job.updatedAtMs) ~/ 1000;
  if (secondsAgo >= 0) {
    metrics.add(
      AiActivityMetric(label: l10n.updatedAgo(secondsAgo), value: ''),
    );
  }

  return metrics;
}
