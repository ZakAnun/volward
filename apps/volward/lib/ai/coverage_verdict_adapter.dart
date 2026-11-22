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
) => verdicts
    // Tree coverage uses this internal directive to request child nodes.
    // Its size is an aggregate of those children, so displaying it alongside
    // their terminal verdicts would double-count the analyzed total.
    .where((verdict) => verdict.verdict != 'drill_down')
    .map(coverageVerdictToAiVerdict)
    .toList(growable: false);
