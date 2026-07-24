import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/snapshot_cache.dart';

void main() {
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

    final path = await SnapshotCache.latestSnapshotPath(preferredRoot: '/Users/test');
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

    File('${snapshots.path}/deadbeef.json').writeAsStringSync(
      jsonEncode({'snapshot_id': 'snap-2', 'entries': []}),
    );

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
}
