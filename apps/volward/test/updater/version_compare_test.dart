import 'package:flutter_test/flutter_test.dart';
import 'package:volward/updater/version_compare.dart';

void main() {
  group('normalizeReleaseTag', () {
    test('strips leading v/V and trims', () {
      expect(normalizeReleaseTag('v0.0.2'), '0.0.2');
      expect(normalizeReleaseTag('V1.2.3'), '1.2.3');
      expect(normalizeReleaseTag(' 0.0.1 '), '0.0.1');
    });

    test('returns null for prerelease or non semver', () {
      expect(normalizeReleaseTag('v0.0.2-beta'), isNull);
      expect(normalizeReleaseTag('latest'), isNull);
      expect(normalizeReleaseTag(''), isNull);
      expect(normalizeReleaseTag('1.2'), isNull);
    });
  });

  group('compareSemver', () {
    test('orders major/minor/patch', () {
      expect(compareSemver('0.0.2', '0.0.1'), greaterThan(0));
      expect(compareSemver('0.0.1', '0.0.2'), lessThan(0));
      expect(compareSemver('1.0.0', '1.0.0'), 0);
      expect(compareSemver('1.10.0', '1.9.0'), greaterThan(0));
    });
  });

  group('isRemoteNewer', () {
    test('true only when remote > local', () {
      expect(isRemoteNewer(remoteTag: 'v0.0.2', localVersion: '0.0.1'), isTrue);
      expect(
          isRemoteNewer(remoteTag: 'v0.0.1', localVersion: '0.0.1'), isFalse);
      expect(
          isRemoteNewer(remoteTag: 'v0.0.1', localVersion: '0.0.2'), isFalse);
      expect(isRemoteNewer(remoteTag: 'v0.0.2-beta', localVersion: '0.0.1'),
          isFalse);
    });
  });
}
