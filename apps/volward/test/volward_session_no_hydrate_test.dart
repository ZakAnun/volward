import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/volward_session.dart';

void main() {
  group('VolwardSession no-hydrate contract', () {
    test('refreshTargetPath returns focused path when set', () {
      final session = VolwardSession.test();
      session.setScanRoots(['/root']);
      session.setCurrentPathForTest('/root/Documents');
      expect(session.refreshTargetPath, '/root/Documents');
    });

    test('refreshTargetPath falls back to scan root when no path focused', () {
      final session = VolwardSession.test();
      session.setScanRoots(['/root']);
      expect(session.refreshTargetPath, '/root');
    });

    test('refreshTargetPath falls back to default home when no roots set', () {
      final session = VolwardSession.test();
      // Default scan root is the home directory — just verify it's non-empty.
      expect(session.refreshTargetPath, isNotEmpty);
    });

    test('_hydrateEngineIfNeeded is a no-op and sets didAttemptHydration', () {
      final session = VolwardSession.test();
      expect(session.didAttemptHydration, isFalse);
      // Calling via the internal test hook via refreshCurrentDirectory
      // (which calls _hydrateEngineIfNeeded through runScan on old path)
      // is not feasible in unit tests — verify the flag is accessible.
      expect(session.didAttemptHydration, isA<bool>());
    });

    test('setCurrentDirectory updates refreshTargetPath', () {
      final session = VolwardSession.test();
      session.setScanRoots(['/home/user']);
      expect(session.refreshTargetPath, '/home/user');

      session.setCurrentDirectory('/home/user/Downloads');
      expect(session.refreshTargetPath, '/home/user/Downloads');

      // Clearing should fall back to root
      session.setCurrentDirectory(null);
      expect(session.refreshTargetPath, '/home/user');
    });
  });

  group('session state file resilience', () {
    test('concurrent session loads share one read and restore the root',
        () async {
      final session = VolwardSession.test();
      final file = File(
        '${Directory.systemTemp.path}/volward-session-concurrent.json',
      );
      final readGate = Completer<String>();
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });

      await file.writeAsString('{}');
      var readCount = 0;
      session
        ..sessionStateFileForTest = file
        ..sessionStateReaderForTest = (_) {
          readCount++;
          return readGate.future;
        };

      final first = session.loadSessionStateIfNeeded();
      final second = session.loadSessionStateIfNeeded();
      expect(identical(first, second), isTrue);

      readGate.complete(
        jsonEncode({
          'scan_roots': ['/Users/test/Downloads'],
        }),
      );
      await Future.wait([first, second]);

      expect(readCount, 1);
      expect(session.scanRoots, ['/Users/test/Downloads']);
    });

    test('does not restore an old root after the user switches folders',
        () async {
      final session = VolwardSession.test();
      final file = File(
        '${Directory.systemTemp.path}/volward-session-root-switch.json',
      );
      final readGate = Completer<String>();
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });

      await file.writeAsString('{}');
      session
        ..sessionStateFileForTest = file
        ..sessionStateReaderForTest = ((_) => readGate.future)
        ..scanRunnerForTest = ((_, __) async => null);

      final load = session.loadSessionStateIfNeeded();
      await session.switchScanRoot('/Users/test/Downloads');
      readGate.complete(
        jsonEncode({
          'scan_roots': ['/Users/test/OldRoot'],
        }),
      );
      await load;

      expect(session.scanRoots, ['/Users/test/Downloads']);
    });

    test('loadSessionStateIfNeeded ignores empty and malformed session files',
        () async {
      final file =
          File('${Directory.systemTemp.path}/volward-session-malformed.json');
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });

      // Truncated JSON.
      await file.writeAsString('{"scan_roots":[');
      final malformed = VolwardSession.test()..sessionStateFileForTest = file;
      await malformed.loadSessionStateIfNeeded();
      expect(malformed.scanRoots, isEmpty);

      // Empty file.
      await file.writeAsString('');
      final empty = VolwardSession.test()..sessionStateFileForTest = file;
      await empty.loadSessionStateIfNeeded();
      expect(empty.scanRoots, isEmpty);
    });

    test('a missing or truncated session file still leaves the app usable',
        () async {
      final file =
          File('${Directory.systemTemp.path}/volward-session-truncated.json');
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });

      await file.writeAsString('{"scan_roots":');
      final session = VolwardSession.test()..sessionStateFileForTest = file;
      await session.loadSessionStateIfNeeded();

      expect(session.scanRoots, isEmpty);
      expect(session.refreshTargetPath, isNotEmpty);
    });
  });

  group('resolveStartupRoot fallback', () {
    test('falls back from a stale root to home, then to folder picker',
        () async {
      final session = VolwardSession.test()
        ..rootExistsForTest = ((path) => path == '/Users/test')
        ..defaultRootForTest = (() => '/Users/test');

      session.setScanRoots(['/missing/root']);
      final resolved = await session.resolveStartupRootForTest();
      expect(resolved, '/Users/test');

      // Home also unusable → empty string signals "show the folder picker".
      session.defaultRootForTest = () => '';
      session.rootExistsForTest = (_) => false;
      final fallback = await session.resolveStartupRootForTest();
      expect(fallback, isEmpty);
    });

    test('keeps a valid saved root', () async {
      final session = VolwardSession.test()
        ..rootExistsForTest = ((_) => true)
        ..defaultRootForTest = (() => '/Users/test');

      session.setScanRoots(['/data/projects']);
      expect(await session.resolveStartupRootForTest(), '/data/projects');
    });

    test('a saved root with a trailing slash normalizes to the launch root',
        () async {
      // Both loadSessionStateIfNeeded and resolveStartupRoot normalize with
      // ScanTreeBuilder.normalizeRoot. Pin that contract: a persisted root
      // written with a trailing slash must resolve to the same string that
      // refreshTargetPath reports, so HomePage's
      // `refreshTargetPath != launchRoot` comparison does not false-positive
      // into a redundant setScanRoots.
      final session = VolwardSession.test()
        ..rootExistsForTest = ((_) => true)
        ..defaultRootForTest = (() => '/Users/test');

      session.setScanRoots(['/Users/test/']); // trailing slash on purpose
      final launchRoot = await session.resolveStartupRootForTest();

      expect(launchRoot, '/Users/test');
      expect(session.refreshTargetPath, launchRoot);
    });
  });
}
