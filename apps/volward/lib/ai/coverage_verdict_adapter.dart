import 'ai_provider.dart';
import 'coverage_verdict_store.dart';

AiVerdict coverageVerdictToAiVerdict(CoverageVerdict verdict) => AiVerdict(
  path: verdict.path,
  verdict: verdict.verdict,
  confidence: verdict.confidence,
  reason: verdict.reason,
);

List<AiVerdict> coverageVerdictsToAiVerdicts(
  Iterable<CoverageVerdict> verdicts,
) => verdicts.map(coverageVerdictToAiVerdict).toList(growable: false);
