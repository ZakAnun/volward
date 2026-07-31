import 'package:flutter_test/flutter_test.dart';
import 'package:volward/volward_session.dart';

void main() {
  group('VolwardSession catalog-backed refresh flow', () {
    test('refreshTargetPath stays on focused subdirectory', () {
      final session = VolwardSession.test();
      session.setScanRoots(['/root']);
      session.setCurrentPathForTest('/root/Documents');
      expect(session.refreshTargetPath, '/root/Documents');
    });

    test('refreshTargetPath falls back to root when no directory focused', () {
      final session = VolwardSession.test();
      session.setScanRoots(['/root']);
      expect(session.refreshTargetPath, '/root');
    });

    test('didAttemptHydration is false before any call', () {
      final session = VolwardSession.test();
      expect(session.didAttemptHydration, isFalse);
    });

    test('setCurrentDirectory updates refreshTargetPath', () {
      final session = VolwardSession.test();
      session.setScanRoots(['/root']);
      session.setCurrentDirectory('/root/Downloads');
      expect(session.refreshTargetPath, '/root/Downloads');
    });

    test('setCurrentDirectory(null) reverts to scan root', () {
      final session = VolwardSession.test();
      session.setScanRoots(['/root']);
      session.setCurrentDirectory('/root/Downloads');
      session.setCurrentDirectory(null);
      expect(session.refreshTargetPath, '/root');
    });

    test('setScanRoots clears any previously focused directory', () {
      final session = VolwardSession.test();
      session.setScanRoots(['/root']);
      session.setCurrentDirectory('/root/Downloads');
      expect(session.refreshTargetPath, '/root/Downloads');

      session.setScanRoots(['/other-root']);
      expect(session.refreshTargetPath, '/other-root');
    });

    test('hasIndexApi is a bool', () {
      final session = VolwardSession.test();
      expect(session.hasIndexApi, isA<bool>());
    });

    test('catalogVersion returns an int', () {
      final session = VolwardSession.test();
      expect(session.catalogVersion, isA<int>());
    });
  });
}
