import '../../../ai/ai_provider.dart';
import '../../../ai/ai_result_groups.dart';
import '../../../ai/ai_settings_store.dart';
import '../../../ai/coverage_job_state.dart';
import '../../../ai/coverage_verdict_store.dart';
import '../../../scan_tree.dart';
import '../views/ai_analysis_workspace_view_state.dart';
import 'ai_analysis_workspace_page_surface.dart';

bool workspaceShouldShowCompactActivityCard(
  AiAnalysisWorkspacePageSurface surface,
) {
  if (surface.analyzing || surface.isLightweightAnalyzingUi()) return true;
  final job =
      surface.coverageController.jobState ?? surface.page.debugCoverageJobState;
  return job != null &&
      job.snapshotId == surface.page.snapshotId &&
      job.status == CoverageJobStatus.running;
}

bool workspaceCanStartCoverage(AiAnalysisWorkspacePageSurface surface) {
  return surface.coverageController.canStartCoverage(
    mode: surface.mode,
    platformCredits: surface.platformCredits,
    useFullCoverage: surface.useFullCoverage,
  );
}

bool workspaceCanStartWorkspaceAnalysis(
  AiAnalysisWorkspacePageSurface surface,
) {
  return surface.hasProvider &&
      !surface.candidatesBootstrapPending &&
      workspaceCanStartCoverage(surface) &&
      !(surface.mode == AiMode.platform && surface.platformCredits == 0) &&
      !surface.coveragePlanIsLocalOnly;
}

String formatBytesValue(num? bytes) {
  if (bytes == null) return '-';
  final value = bytes.toInt();
  if (value < 1024) return '$value B';
  if (value < 1048576) return '${(value / 1024).toStringAsFixed(1)} KB';
  if (value < 1073741824) {
    return '${(value / 1048576).toStringAsFixed(1)} MB';
  }
  return '${(value / 1073741824).toStringAsFixed(2)} GB';
}

List<AiVerdict> preClassifiedVerdicts(
  List<Map<String, dynamic>> preClassified, {
  required bool deletable,
}) {
  final items = <AiVerdict>[];
  for (final entry in preClassified) {
    final isDeletable = entry['deletable'] == true;
    if (isDeletable != deletable) continue;
    final path = entry['path'] as String? ?? '';
    if (path.isEmpty) continue;
    items.add(
      AiVerdict(
        path: path,
        verdict: deletable ? 'safe_to_remove' : 'keep',
        confidence: entry['confidence']?.toString() ?? 'high',
        reason: entry['reason']?.toString() ?? '',
      ),
    );
  }
  return items;
}

Set<String> scanRootFirstLevelDirectoryPaths({
  required String rootPath,
  required List<AiCandidate> unknown,
  required List<Map<String, dynamic>> preClassified,
  required List<CoverageVerdict> coverageVerdictRows,
  required List<AiVerdict> verdicts,
}) {
  final root = normalizeFsPath(rootPath);
  if (root.isEmpty) return const {};
  final dirs = <String>{};
  void consider(String path) {
    if (path.isEmpty) return;
    final bucket = firstLevelDirectoryUnderRoot(path, root);
    if (bucket == null || bucket == root) return;
    dirs.add(bucket);
  }

  for (final candidate in unknown) {
    consider(candidate.path);
  }
  for (final entry in preClassified) {
    consider(entry['path']?.toString() ?? '');
  }
  for (final row in coverageVerdictRows) {
    consider(row.path);
  }
  for (final verdict in verdicts) {
    consider(verdict.path);
  }
  return dirs;
}

bool isPendingReview(
  AiVerdict item,
  Map<String, WorkspaceReviewDecision> reviewDecisions,
) {
  return item.verdict == 'review_needed' &&
      (reviewDecisions[item.path] ?? WorkspaceReviewDecision.pending) ==
          WorkspaceReviewDecision.pending;
}

int priorityRank(
  AiVerdict item,
  Map<String, WorkspaceReviewDecision> reviewDecisions,
) {
  return switch (item.verdict) {
    'review_needed' => switch (reviewDecisions[item.path] ??
        WorkspaceReviewDecision.pending) {
      WorkspaceReviewDecision.pending => 0,
      WorkspaceReviewDecision.include => 1,
      WorkspaceReviewDecision.keep => 2,
    },
    'safe_to_remove' => 3,
    'keep' => 4,
    'unanalyzed' => 5,
    _ => 6,
  };
}

int compareVisibleItems({
  required AiVerdict left,
  required AiVerdict right,
  required WorkspaceResultSort sort,
  required Map<String, int> sizeByPath,
  required Map<String, WorkspaceReviewDecision> reviewDecisions,
}) {
  if (sort == WorkspaceResultSort.priority) {
    final priorityOrder = priorityRank(
      left,
      reviewDecisions,
    ).compareTo(priorityRank(right, reviewDecisions));
    if (priorityOrder != 0) return priorityOrder;
  }
  final sizeOrder = (sizeByPath[right.path] ?? 0).compareTo(
    sizeByPath[left.path] ?? 0,
  );
  if (sizeOrder != 0) return sizeOrder;
  return left.path.compareTo(right.path);
}

List<AiVerdict> pendingReviewVerdicts({
  required List<AiVerdict> verdicts,
  required Map<String, WorkspaceReviewDecision> reviewDecisions,
  required WorkspaceResultSort sort,
  required Map<String, int> sizeByPath,
  String? directoryPath,
}) {
  var list = verdicts
      .where((item) => isPendingReview(item, reviewDecisions))
      .toList(growable: false);
  if (directoryPath != null && directoryPath.isNotEmpty) {
    final dir = normalizeFsPath(directoryPath);
    list = list
        .where((item) => isUnderFsRoot(normalizeFsPath(item.path), dir))
        .toList(growable: false);
  }
  return [...list]..sort(
    (left, right) => compareVisibleItems(
      left: left,
      right: right,
      sort: sort,
      sizeByPath: sizeByPath,
      reviewDecisions: reviewDecisions,
    ),
  );
}

List<String> directoryPathsForGrouping({
  required List<AiCandidate> unknown,
  required List<Map<String, dynamic>> preClassified,
}) {
  return [
    ...unknown.where((candidate) => candidate.isDir).map((c) => c.path),
    ...preClassified
        .where((entry) => entry['is_dir'] == true)
        .map((entry) => entry['path']?.toString() ?? '')
        .where((path) => path.isNotEmpty),
  ];
}

Set<String> selectedPathsForResults({
  required Iterable<AiVerdict> verdicts,
  required List<Map<String, dynamic>> preClassified,
  required Map<String, WorkspaceReviewDecision> reviewDecisions,
}) {
  final aiPaths = verdicts.map((verdict) => verdict.path).toSet();
  final selected = <String>{
    ...preClassifiedVerdicts(preClassified, deletable: true)
        .where((verdict) => !aiPaths.contains(verdict.path))
        .map((verdict) => verdict.path),
  };
  for (final verdict in verdicts) {
    switch (verdict.verdict) {
      case 'safe_to_remove':
        selected.add(verdict.path);
        break;
      case 'review_needed':
        if ((reviewDecisions[verdict.path] ??
                WorkspaceReviewDecision.pending) ==
            WorkspaceReviewDecision.include) {
          selected.add(verdict.path);
        }
        break;
      case 'keep':
        break;
    }
  }
  return selected;
}

AiVerdict withCandidateMeta(
  AiVerdict verdict,
  Map<String, AiCandidate> unknownByPath,
) {
  final candidate = unknownByPath[verdict.path];
  if (candidate == null) return verdict;
  return AiVerdict(
    path: verdict.path,
    verdict: verdict.verdict,
    confidence: verdict.confidence,
    reason: verdict.reason,
    cleanupSource: verdict.cleanupSource ?? candidate.cleanupSource,
    cleanupHint: verdict.cleanupHint ?? candidate.cleanupHint,
    retentionDays: verdict.retentionDays ?? candidate.retentionDays,
  );
}
