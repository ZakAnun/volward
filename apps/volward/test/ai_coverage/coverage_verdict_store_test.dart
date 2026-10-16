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

  test(
    'separate store instances on the same directory serialize appends',
    () async {
      final other = CoverageVerdictStore(dir);
      CoverageVerdict row(String path) => CoverageVerdict(
        path: path,
        verdict: 'keep',
        confidence: 'high',
        reason: 'r',
        coverageSource: 'test',
        sizeBytes: 1,
      );
      await Future.wait([
        store.appendAll('s', [row('/a/1')]),
        other.appendAll('s', [row('/b/1')]),
        store.appendWith('s', (path) async {
          File(path).writeAsStringSync(
            '${jsonEncode(row('/c/1').toJson())}\n',
            mode: FileMode.append,
          );
        }),
      ]);
      final lines = File(
        '${dir.path}/ai_coverage_verdicts_s.jsonl',
      ).readAsLinesSync();
      expect(lines, hasLength(3));
      for (final line in lines) {
        expect(() => jsonDecode(line), returnsNormally);
      }
    },
  );

  test('concurrent appendAll and appendWith never interleave lines', () async {
    CoverageVerdict row(String path) => CoverageVerdict(
      path: path,
      verdict: 'keep',
      confidence: 'high',
      reason: 'r' * 200,
      coverageSource: 'test',
      sizeBytes: 1,
    );
    final writes = <Future<void>>[];
    for (var b = 0; b < 4; b++) {
      writes.add(
        store.appendAll('s', [for (var i = 0; i < 3000; i++) row('/a$b/$i')]),
      );
      writes.add(
        store.appendWith('s', (filePath) async {
          final sink = File(filePath).openWrite(mode: FileMode.append);
          for (var i = 0; i < 3000; i++) {
            sink.writeln(jsonEncode(row('/w$b/$i').toJson()));
          }
          await sink.close();
        }),
      );
    }
    await Future.wait(writes);

    final lines = File(
      '${dir.path}/ai_coverage_verdicts_s.jsonl',
    ).readAsLinesSync();
    expect(lines, hasLength(24000));
    for (final line in lines) {
      expect(() => jsonDecode(line), returnsNormally);
    }
    expect(await store.readAll('s'), hasLength(24000));
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

  test('large files decode off-isolate with same merge and paging', () async {
    final reason = 'r' * 200;
    List<CoverageVerdict> batch(int start, int count, String verdict) => [
      for (var i = start; i < start + count; i++)
        CoverageVerdict(
          path: '/f/${i.toString().padLeft(6, '0')}',
          verdict: verdict,
          confidence: 'high',
          reason: reason,
          coverageSource: 'file',
          sizeBytes: i,
        ),
    ];
    await store.appendAll('big', batch(0, 6000, 'keep'));
    final offset = await store.fileByteLength('big');
    expect(offset, greaterThan(1024 * 1024));

    await store.appendAll('big', batch(5990, 6000, 'safe_to_remove'));

    final all = await store.readAll('big');
    expect(all, hasLength(11990));

    final pages = await store.readPages('big', pageCount: 2, pageSize: 5);
    expect(pages.map((v) => v.path), [
      for (var i = 0; i < 10; i++) '/f/${i.toString().padLeft(6, '0')}',
    ]);

    final appended = await store.readAppendedSince('big', offset);
    expect(appended.fileLength, await store.fileByteLength('big'));
    expect(appended.appended, hasLength(6000));
    expect(
      appended.appended.every((v) => v.verdict == 'safe_to_remove'),
      isTrue,
    );
    final overwritten = all.firstWhere((v) => v.path == '/f/005995');
    expect(overwritten.verdict, 'safe_to_remove');
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
