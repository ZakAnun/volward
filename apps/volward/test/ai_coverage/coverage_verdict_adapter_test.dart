import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_verdict_adapter.dart';
import 'package:volward/ai/coverage_verdict_store.dart';

void main() {
  test('coverageVerdictToAiVerdict maps fields', () {
    const verdict = CoverageVerdict(
      path: '/tmp/cache.bin',
      verdict: 'safe_to_remove',
      confidence: 'high',
      reason: 'tool cache',
      coverageSource: 'file',
      sizeBytes: 4096,
    );

    final ai = coverageVerdictToAiVerdict(verdict);

    expect(ai.path, verdict.path);
    expect(ai.verdict, verdict.verdict);
    expect(ai.confidence, verdict.confidence);
    expect(ai.reason, verdict.reason);
  });

  test('coverageVerdictsToAiVerdicts preserves order', () {
    const verdicts = [
      CoverageVerdict(
        path: '/a',
        verdict: 'keep',
        confidence: 'medium',
        reason: 'r1',
        coverageSource: 'file',
        sizeBytes: 1,
      ),
      CoverageVerdict(
        path: '/b',
        verdict: 'review_needed',
        confidence: 'low',
        reason: 'r2',
        coverageSource: 'group:/b',
        sizeBytes: 2,
      ),
    ];

    final mapped = coverageVerdictsToAiVerdicts(verdicts);

    expect(mapped, hasLength(2));
    expect(mapped.first.path, '/a');
    expect(mapped.last.path, '/b');
  });
}
