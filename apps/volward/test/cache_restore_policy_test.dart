import 'package:flutter_test/flutter_test.dart';
import 'package:volward/cache_restore_policy.dart';

void main() {
  group('cacheRestoreTimeoutForByteSize', () {
    test('uses 8s for small or unknown sizes', () {
      expect(cacheRestoreTimeoutForByteSize(null), const Duration(seconds: 8));
      expect(cacheRestoreTimeoutForByteSize(0), const Duration(seconds: 8));
      expect(cacheRestoreTimeoutForByteSize(786), const Duration(seconds: 8));
      expect(
        cacheRestoreTimeoutForByteSize(1024 * 1024),
        const Duration(seconds: 8),
      );
    });

    test('uses tier boundaries from file size', () {
      const mb = 1024 * 1024;
      expect(cacheRestoreTimeoutForByteSize(mb), const Duration(seconds: 8));
      expect(
        cacheRestoreTimeoutForByteSize(mb + 1),
        const Duration(seconds: 30),
      );
      expect(
        cacheRestoreTimeoutForByteSize(32 * mb),
        const Duration(seconds: 30),
      );
      expect(
        cacheRestoreTimeoutForByteSize(32 * mb + 1),
        const Duration(seconds: 60),
      );
      expect(
        cacheRestoreTimeoutForByteSize(128 * mb),
        const Duration(seconds: 60),
      );
      expect(
        cacheRestoreTimeoutForByteSize(128 * mb + 1),
        const Duration(seconds: 180),
      );
      expect(
        cacheRestoreTimeoutForByteSize(512 * mb + 1),
        const Duration(seconds: 300),
      );
      expect(
        cacheRestoreTimeoutForByteSize(1024 * mb + 1),
        const Duration(seconds: 600),
      );
    });

    test('uses 30s for multi-megabyte indexes', () {
      expect(
        cacheRestoreTimeoutForByteSize(18 * 1024 * 1024),
        const Duration(seconds: 30),
      );
    });

    test('uses 60s for ~91MB Applications-sized indexes', () {
      expect(
        cacheRestoreTimeoutForByteSize(91 * 1024 * 1024),
        const Duration(seconds: 60),
      );
    });

    test('uses 180s for indexes between 128MB and 512MB', () {
      expect(
        cacheRestoreTimeoutForByteSize(200 * 1024 * 1024),
        const Duration(seconds: 180),
      );
    });

    test('uses 600s for gigabyte-class indexes', () {
      expect(
        cacheRestoreTimeoutForByteSize(1223 * 1024 * 1024),
        const Duration(seconds: 600),
      );
    });
  });

  group('indexSummaryMatchesRoot', () {
    test('matches normalized root paths', () {
      expect(
        indexSummaryMatchesRoot({
          'root_path': '/Users/test/Downloads/',
        }, '/Users/test/Downloads'),
        isTrue,
      );
    });

    test('rejects error summaries and other roots', () {
      expect(
        indexSummaryMatchesRoot({'error': 'no index'}, '/Users/test'),
        isFalse,
      );
      expect(
        indexSummaryMatchesRoot({
          'root_path': '/Users/test/Desktop',
        }, '/Users/test/Downloads'),
        isFalse,
      );
      expect(indexSummaryMatchesRoot(null, '/Users/test'), isFalse);
    });
  });
}
