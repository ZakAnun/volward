import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/coverage_verdict_store.dart';

void main() {
  late Directory dir;
  late CoverageVerdictStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('coverage-verdict-');
    store = CoverageVerdictStore(dir);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('appendAll then readAll round trips and overwrites by path', () async {
    await store.appendAll('s1', const [
      CoverageVerdict(
        path: '/a',
        verdict: 'keep',
        confidence: 'high',
        reason: 'x',
        coverageSource: 'file',
        sizeBytes: 1,
      ),
    ]);
    await store.appendAll('s1', const [
      CoverageVerdict(
        path: '/a',
        verdict: 'review_needed',
        confidence: 'low',
        reason: 'y',
        coverageSource: 'file',
        sizeBytes: 1,
      ),
    ]);
    final all = await store.readAll('s1');
    expect(all, hasLength(1));
    expect(all.single.verdict, 'review_needed');
    expect(all.single.reason, 'y');
  });
}
