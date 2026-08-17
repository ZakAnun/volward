import 'dart:convert';
import 'dart:io';

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

    test('rememberCustomRoot keeps recent roots as an MRU list', () async {
      final session = VolwardSession.test();
      final file = File(
        '${Directory.systemTemp.path}/volward-session-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      session.sessionStateFileForTest = file;

      session.rememberCustomRoot('/Users/test/Projects');
      session.rememberCustomRoot('/Users/test/Archives');
      session.rememberCustomRoot('/Users/test/Projects');
      for (var i = 0; i < 10 && !await file.exists(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(session.lastCustomRoot, '/Users/test/Projects');
      expect(session.recentCustomRoots, [
        '/Users/test/Projects',
        '/Users/test/Archives',
      ]);

      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(raw['last_custom_root'], '/Users/test/Projects');
      expect(raw['last_custom_roots'], [
        '/Users/test/Projects',
        '/Users/test/Archives',
      ]);
      await file.delete();
    });

    test('hasIndexApi is a bool', () {
      final session = VolwardSession.test();
      expect(session.hasIndexApi, isA<bool>());
    });

    test('catalogVersion returns an int', () {
      final session = VolwardSession.test();
      expect(session.catalogVersion, isA<int>());
    });

    test('loadSessionStateIfNeeded restores persisted scan roots', () async {
      final session = VolwardSession.test();
      final file = File(
        '${Directory.systemTemp.path}/volward-session-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      session.sessionStateFileForTest = file;
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'scan_roots': ['/Users/test/Downloads'],
        }),
      );

      await session.loadSessionStateIfNeeded();

      expect(session.scanRoots, ['/Users/test/Downloads']);
      await file.delete();
    });

    test('loadSessionStateIfNeeded ignores empty session state files',
        () async {
      final session = VolwardSession.test();
      final file = File(
        '${Directory.systemTemp.path}/volward-session-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      session.sessionStateFileForTest = file;
      await file.parent.create(recursive: true);
      await file.writeAsString('');

      await session.loadSessionStateIfNeeded();

      expect(session.scanRoots, isEmpty);
      await file.delete();
    });

    test('switchScanRoot persists the selected root', () async {
      final session = VolwardSession.test();
      final file = File(
        '${Directory.systemTemp.path}/volward-session-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      session.sessionStateFileForTest = file;

      await session.switchScanRoot('/Users/test/Downloads');

      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(raw['scan_roots'], ['/Users/test/Downloads']);
      await file.delete();
    });

    test('switchScanRoot to a default root keeps the last custom root',
        () async {
      final session = VolwardSession.test();
      final file = File(
        '${Directory.systemTemp.path}/volward-session-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      session.sessionStateFileForTest = file;

      session.setLastCustomRoot('/Users/test/Projects');
      await session.switchScanRoot('/Users/test');

      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(raw['scan_roots'], ['/Users/test']);
      expect(raw['last_custom_root'], '/Users/test/Projects');
      await file.delete();
    });

    test('loadSessionStateIfNeeded restores the last custom root', () async {
      final session = VolwardSession.test();
      final file = File(
        '${Directory.systemTemp.path}/volward-session-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      session.sessionStateFileForTest = file;
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'scan_roots': ['/Users/test'],
          'last_custom_root': '/Users/test/Projects',
          'last_custom_roots': [
            '/Users/test/Archives',
            '/Users/test/Projects',
          ],
        }),
      );

      await session.loadSessionStateIfNeeded();

      expect(session.scanRoots, ['/Users/test']);
      expect(session.lastCustomRoot, '/Users/test/Archives');
      expect(session.recentCustomRoots, [
        '/Users/test/Archives',
        '/Users/test/Projects',
      ]);
      await file.delete();
    });
  });
}
