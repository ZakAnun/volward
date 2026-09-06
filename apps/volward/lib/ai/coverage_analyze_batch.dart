import 'ai_settings_store.dart';
import 'ai_coverage_job_controller.dart';
import 'ai_provider.dart';
import 'byok_ai_provider.dart';
import 'cancel_token.dart';
import 'coverage_models.dart';
import 'coverage_verdict_store.dart';

List<AiCandidate> coverageRowsToCandidates(List<CoverageRow> rows) {
  return rows
      .map(
        (row) => AiCandidate(
          path: row.path,
          sizeBytes: row.sizeBytes,
          isDir: row.kind == CoverageRowKind.group,
          childCount: row.memberCount,
          cleanupSource: row.cleanupSource,
          cleanupHint: row.cleanupHint,
          retentionDays: row.retentionDays,
        ),
      )
      .toList(growable: false);
}

String coverageSourceForRow(CoverageRow row) =>
    row.kind == CoverageRowKind.group ? 'group:${row.path}' : 'file';

CoverageVerdict coverageVerdictForRow(CoverageRow row, AiVerdict verdict) =>
    CoverageVerdict(
      path: row.path,
      verdict: verdict.verdict,
      confidence: verdict.confidence,
      reason: verdict.reason,
      coverageSource: coverageSourceForRow(row),
      sizeBytes: row.sizeBytes,
      groupMemberCount: row.memberCount,
    );

AnalyzeBatch createCoverageAnalyzeBatch({
  required AiProvider provider,
  CancelToken? cancelToken,
}) {
  return (rows) async {
    final candidates = coverageRowsToCandidates(rows);
    final result = await provider.analyze(candidates, cancelToken: cancelToken);
    final byPath = {
      for (final verdict in result.verdicts) verdict.path: verdict,
    };
    final mapped = <CoverageVerdict>[];
    for (final row in rows) {
      final verdict = byPath[row.path];
      if (verdict == null) {
        throw CoverageAnalyzeException('missing verdict for ${row.path}');
      }
      mapped.add(coverageVerdictForRow(row, verdict));
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

class CoverageAnalyzeException implements Exception {
  CoverageAnalyzeException(this.message);

  final String message;

  @override
  String toString() => message;
}
