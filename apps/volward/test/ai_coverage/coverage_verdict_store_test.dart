import 'dart:convert';
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

  test('readAll tolerates a trailing truncated UTF-8 sequence', () async {
    final file = File('${dir.path}/ai_coverage_verdicts_s.jsonl');
    final line = jsonEncode(const {
      'path': '/a',
      'verdict': 'keep',
      'confidence': 'high',
      'reason': 'test',
      'coverage_source': 'file',
      'size_bytes': 1,
    });
    final bytes = <int>[
      ...utf8.encode(line),
      0x0a, // newline
      0xE4, // lead byte of a 3-byte UTF-8 char, truncated (no continuation)
    ];
    await file.writeAsBytes(bytes, flush: true);
    final verdicts = await store.readAll('s');
    expect(verdicts, hasLength(1));
    expect(verdicts.single.path, '/a');
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

  test('readPage returns stable path-ordered slices', () async {
    await store.appendAll('s1', [
      for (var i = 0; i < 5; i++)
        CoverageVerdict(
          path: '/f$i',
          verdict: 'keep',
          confidence: 'high',
          reason: 'x',
          coverageSource: 'file',
          sizeBytes: i,
        ),
    ]);

    final page0 = await store.readPage('s1', pageIndex: 0, pageSize: 2);
    final page2 = await store.readPage('s1', pageIndex: 2, pageSize: 2);

    expect(page0, hasLength(2));
    expect(page0.first.path, '/f0');
    expect(page2.single.path, '/f4');
  });

  test('readMergedSorted caches until append invalidates', () async {
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
    final first = await store.readMergedSorted('s1');
    await store.appendAll('s1', const [
      CoverageVerdict(
        path: '/b',
        verdict: 'keep',
        confidence: 'high',
        reason: 'x',
        coverageSource: 'file',
        sizeBytes: 2,
      ),
    ]);
    final second = await store.readMergedSorted('s1');
    expect(first, hasLength(1));
    expect(second, hasLength(2));
    expect(second.first.path, '/a');
  });

  test('readPages returns prefix without rescanning per page', () async {
    await store.appendAll('s1', [
      for (var i = 0; i < 5; i++)
        CoverageVerdict(
          path: '/f$i',
          verdict: 'keep',
          confidence: 'high',
          reason: 'x',
          coverageSource: 'file',
          sizeBytes: i,
        ),
    ]);
    final pages = await store.readPages('s1', pageCount: 2, pageSize: 2);
    expect(pages, hasLength(4));
    expect(pages.first.path, '/f0');
    expect(pages.last.path, '/f3');
  });

  test('readAppendedSince returns only new lines', () async {
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
    final offset = await store.fileByteLength('s1');
    await store.appendAll('s1', const [
      CoverageVerdict(
        path: '/b',
        verdict: 'keep',
        confidence: 'high',
        reason: 'x',
        coverageSource: 'file',
        sizeBytes: 2,
      ),
    ]);

    final chunk = await store.readAppendedSince('s1', offset);

    expect(chunk.appended, hasLength(1));
    expect(chunk.appended.single.path, '/b');
    expect(chunk.fileLength, greaterThan(offset));
  });
}
