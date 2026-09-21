import 'ai_settings_store.dart';
import 'ai_coverage_job_controller.dart';
import 'ai_provider.dart';
import 'byok_ai_provider.dart';
import 'cancel_token.dart';
import 'coverage_analyze_batch.dart';
import 'coverage_models.dart';
import 'coverage_verdict_store.dart';

typedef AnalyzeTreeBatch =
    Future<BatchOutcome> Function(List<CoverageTreeNode> nodes);

String coverageSourceForTreeNode(CoverageTreeNode node) => 'dir:${node.path}';

CoverageVerdict coverageVerdictForTreeNode(
  CoverageTreeNode node,
  AiVerdict verdict, {
  String? coverageSource,
}) => CoverageVerdict(
  path: node.path,
  verdict: verdict.verdict,
  confidence: verdict.confidence,
  reason: verdict.reason,
  coverageSource: coverageSource ?? coverageSourceForTreeNode(node),
  sizeBytes: node.sizeBytes,
);

/// Spec §6.2: never treat project dirs as high-confidence safe_to_remove.
AiVerdict coerceTreeVerdict(CoverageTreeNode node, AiVerdict verdict) {
  if (verdict.verdict == 'safe_to_remove' &&
      verdict.confidence == 'high' &&
      (node.role == 'project_root' || node.role == 'project_like')) {
    return AiVerdict(
      path: verdict.path,
      verdict: 'drill_down',
      confidence: verdict.confidence,
      reason:
          '${verdict.reason} (coerced safe_to_remove → drill_down for ${node.role})',
      cleanupSource: verdict.cleanupSource,
      cleanupHint: verdict.cleanupHint,
      retentionDays: verdict.retentionDays,
    );
  }
  return verdict;
}

AnalyzeTreeBatch createCoverageAnalyzeTreeBatch({
  required TreeAiProvider provider,
  CancelToken? cancelToken,
}) {
  return (nodes) async {
    final result = await provider.analyzeTreeNodes(
      nodes,
      cancelToken: cancelToken,
    );
    if (nodes.isNotEmpty && result.verdicts.isEmpty) {
      throw CoverageAnalyzeException(
        'empty verdict list for ${nodes.length} tree nodes',
        creditsCharged: result.credits,
      );
    }
    final byPath = {
      for (final verdict in result.verdicts) verdict.path: verdict,
    };
    final mapped = <CoverageVerdict>[];
    for (final node in nodes) {
      final verdict = byPath[node.path];
      if (verdict == null) {
        mapped.add(
          coverageVerdictForTreeNode(
            node,
            AiVerdict(
              path: node.path,
              verdict: 'review_needed',
              confidence: 'low',
              reason: kIncompleteVerdictReason,
            ),
            coverageSource: kIncompleteCoverageSource,
          ),
        );
        continue;
      }
      mapped.add(
        coverageVerdictForTreeNode(node, coerceTreeVerdict(node, verdict)),
      );
    }
    if (provider is ByokAiProvider) {
      await AiSettingsStore.instance.addByokTokenUsage(
        inputTokens: result.inputTokens,
        outputTokens: result.outputTokens,
        totalTokens: result.tokens,
        estimated: result.estimated,
        partial: false,
      );
    }
    return BatchOutcome(
      usage: BatchUsage(tokens: result.tokens, credits: result.credits),
      verdicts: mapped,
    );
  };
}
