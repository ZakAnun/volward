import 'ai_coverage_job_controller.dart';
import 'ai_provider.dart';
import 'byok_ai_provider.dart';
import 'coverage_models.dart';
import 'coverage_verdict_store.dart';
import 'platform_ai_provider.dart';

List<AiCandidate> coverageRowsToCandidates(List<CoverageRow> rows) {
  return rows
      .map(
        (row) => AiCandidate(
          path: row.path,
          sizeBytes: row.sizeBytes,
          isDir: row.kind == CoverageRowKind.group,
          childCount: row.memberCount,
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
    );

BatchUsage batchUsageForProvider(AiProvider provider, int rowCount) {
  if (provider is ByokAiProvider) {
    final usage = provider.lastTokenUsage;
    if (usage != null) {
      return BatchUsage(tokens: usage.totalTokens, credits: 0);
    }
    final promptTokens = rowCount * 8 + 200;
    final completionTokens = rowCount * 40;
    return BatchUsage(tokens: promptTokens + completionTokens, credits: 0);
  }
  if (provider is PlatformAiProvider) {
    return BatchUsage(tokens: 0, credits: provider.lastCreditsUsed);
  }
  return const BatchUsage(tokens: 0, credits: 0);
}

AnalyzeBatch createCoverageAnalyzeBatch({required AiProvider provider}) {
  return (rows) async {
    final candidates = coverageRowsToCandidates(rows);
    final verdicts = await provider.analyze(candidates);
    final byPath = {for (final verdict in verdicts) verdict.path: verdict};
    final mapped = <CoverageVerdict>[];
    for (final row in rows) {
      final verdict = byPath[row.path];
      if (verdict == null) {
        throw CoverageAnalyzeException('missing verdict for ${row.path}');
      }
      mapped.add(coverageVerdictForRow(row, verdict));
    }
    return BatchOutcome(
      usage: batchUsageForProvider(provider, rows.length),
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
