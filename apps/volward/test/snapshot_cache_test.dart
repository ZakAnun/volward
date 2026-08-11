import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/snapshot_cache.dart';

void main() {
  group('cacheDirForPlatform', () {
    test('uses override before platform defaults', () {
      final dir = SnapshotCache.cacheDirForPlatform(
        environment: {
          'VOLWARD_CACHE_DIR': '/custom/cache',
          'HOME': '/Users/me',
        },
        isMacOS: true,
        isWindows: false,
        isLinux: false,
        systemTempPath: '/tmp',
      );

      expect(dir.path, '/custom/cache');
    });

    test('uses macOS Application Support', () {
      final dir = SnapshotCache.cacheDirForPlatform(
        environment: {'HOME': '/Users/me'},
        isMacOS: true,
        isWindows: false,
        isLinux: false,
        systemTempPath: '/tmp',
      );

      expect(dir.path, '/Users/me/Library/Application Support/Volward');
    });

    test('uses Windows roaming app data', () {
      final dir = SnapshotCache.cacheDirForPlatform(
        environment: {'APPDATA': r'C:\Users\me\AppData\Roaming'},
        isMacOS: false,
        isWindows: true,
        isLinux: false,
        systemTempPath: r'C:\Temp',
      );

      expect(dir.path, r'C:\Users\me\AppData\Roaming\Volward');
    });

    test('uses Windows profile fallback', () {
      final dir = SnapshotCache.cacheDirForPlatform(
        environment: {'USERPROFILE': r'D:\Users\me'},
        isMacOS: false,
        isWindows: true,
        isLinux: false,
        systemTempPath: r'C:\Temp',
      );

      expect(dir.path, r'D:\Users\me\AppData\Roaming\Volward');
    });

    test('uses Linux XDG data home', () {
      final dir = SnapshotCache.cacheDirForPlatform(
        environment: {'XDG_DATA_HOME': '/home/me/.local/state'},
        isMacOS: false,
        isWindows: false,
        isLinux: true,
        systemTempPath: '/tmp',
      );

      expect(dir.path, '/home/me/.local/state/volward');
    });

    test('uses Linux home fallback', () {
      final dir = SnapshotCache.cacheDirForPlatform(
        environment: {'HOME': '/home/me'},
        isMacOS: false,
        isWindows: false,
        isLinux: true,
        systemTempPath: '/tmp',
      );

      expect(dir.path, '/home/me/.local/share/volward');
    });
  });

  test('latestSnapshotPath resolves snapshot_path from manifest', () async {
    final temp = await Directory.systemTemp.createTemp('volward-cache-test');
    addTearDown(() {
      SnapshotCache.cacheDirForTest = null;
      temp.delete(recursive: true);
    });
    SnapshotCache.cacheDirForTest = temp;

    final manifests = Directory('${temp.path}/manifests')..createSync();
    final snapshots = Directory('${temp.path}/snapshots')..createSync();

    final snapshotFile = File('${snapshots.path}/abc.json')
      ..writeAsStringSync(jsonEncode({'snapshot_id': 'snap-1', 'entries': []}));

    File('${manifests.path}/abc.json').writeAsStringSync(
      jsonEncode({
        'root': '/Users/test',
        'scanned_at_ms': 1000,
        'snapshot_id': 'snap-1',
        'snapshot_path': snapshotFile.path,
        'dir_fingerprints': {},
      }),
    );

    final path = await SnapshotCache.latestSnapshotPath(
      preferredRoot: '/Users/test',
    );
    expect(path, snapshotFile.path);
  });

  test('latestSnapshotPath falls back to snapshots hash file', () async {
    final temp = await Directory.systemTemp.createTemp('volward-cache-test');
    addTearDown(() {
      SnapshotCache.cacheDirForTest = null;
      temp.delete(recursive: true);
    });
    SnapshotCache.cacheDirForTest = temp;

    final manifests = Directory('${temp.path}/manifests')..createSync();
    final snapshots = Directory('${temp.path}/snapshots')..createSync();

    File(
      '${snapshots.path}/deadbeef.json',
    ).writeAsStringSync(jsonEncode({'snapshot_id': 'snap-2', 'entries': []}));

    File('${manifests.path}/deadbeef.json').writeAsStringSync(
      jsonEncode({
        'root': '/Users/other',
        'scanned_at_ms': 2000,
        'snapshot_id': 'snap-2',
        'dir_fingerprints': {},
      }),
    );

    final path = await SnapshotCache.latestSnapshotPath();
    expect(path, '${snapshots.path}/deadbeef.json');
  });

  test(
    'latestSnapshotPath does not fall back to another root when preferred root is missing',
    () async {
      final temp = await Directory.systemTemp.createTemp('volward-cache-test');
      addTearDown(() {
        SnapshotCache.cacheDirForTest = null;
        temp.delete(recursive: true);
      });
      SnapshotCache.cacheDirForTest = temp;

      final manifests = Directory('${temp.path}/manifests')..createSync();
      final snapshots = Directory('${temp.path}/snapshots')..createSync();

      final snapshotFile = File('${snapshots.path}/old.json')
        ..writeAsStringSync(
          jsonEncode({'snapshot_id': 'snap-old', 'entries': []}),
        );

      File('${manifests.path}/old.json').writeAsStringSync(
        jsonEncode({
          'root': '/Users/old-root',
          'scanned_at_ms': 2500,
          'snapshot_id': 'snap-old',
          'snapshot_path': snapshotFile.path,
          'dir_fingerprints': {},
        }),
      );

      final path = await SnapshotCache.latestSnapshotPath(
        preferredRoot: '/Users/new-root',
      );
      expect(path, isNull);
    },
  );

  test(
    'latestSnapshotPath reads manifest header without full json decode',
    () async {
      final temp = await Directory.systemTemp.createTemp('volward-cache-test');
      addTearDown(() {
        SnapshotCache.cacheDirForTest = null;
        temp.delete(recursive: true);
      });
      SnapshotCache.cacheDirForTest = temp;

      final manifests = Directory('${temp.path}/manifests')..createSync();
      final snapshots = Directory('${temp.path}/snapshots')..createSync();

      final snapshotFile = File('${snapshots.path}/large.json')
        ..writeAsStringSync(jsonEncode({'snapshot_id': 'snap-large'}));
      File('${manifests.path}/large.json').writeAsStringSync('''
{
  "root": "/Users/test",
  "scanned_at_ms": 3000,
  "snapshot_id": "snap-large",
  "snapshot_path": "${snapshotFile.path}",
  "dir_fingerprints": {
    ${List.filled(20000, '"x": {"mtime_secs": 1}').join(',')}
  }
''');

      final path = await SnapshotCache.latestSnapshotPath(
        preferredRoot: '/Users/test',
      );
      expect(path, snapshotFile.path);
    },
  );
}
