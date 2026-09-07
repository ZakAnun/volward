import 'dart:convert';
import 'dart:io';

void writeCachedSnapshot({
  required Directory cacheDir,
  required String manifestName,
  required String snapshotName,
  required String root,
  required String snapshotId,
  required int scannedAtMs,
  required int sizeBytes,
  required int reclaimableBytes,
}) {
  Directory('${cacheDir.path}/manifests').createSync(recursive: true);
  Directory('${cacheDir.path}/snapshots').createSync(recursive: true);
  final snapshotFile = File('${cacheDir.path}/snapshots/$snapshotName.json')
    ..writeAsStringSync(
      jsonEncode({
        'snapshot_id': snapshotId,
        'scanned_at_ms': scannedAtMs,
        'reclaimable_estimate_bytes': reclaimableBytes,
        'entries': const [],
        'tree': {
          'name': root.split('/').last,
          'path': root,
          'is_dir': true,
          'size_bytes': sizeBytes,
          'children': const [],
        },
        'stats': {
          'scan_state': 'Done',
          'files_seen': 4,
          'files_in_snapshot': 4,
        },
      }),
    );
  File('${cacheDir.path}/manifests/$manifestName.json').writeAsStringSync(
    jsonEncode({
      'root': root,
      'scanned_at_ms': scannedAtMs,
      'snapshot_id': snapshotId,
      'snapshot_path': snapshotFile.path,
    }),
  );
}
