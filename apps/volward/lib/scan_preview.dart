import 'scan_tree.dart';

/// Builds a lightweight, snapshot-shaped map from a `quick_list_dir` result
/// so the UI can render it through the same [ScanTreeNode.fromSnapshotJson]
/// path used for real scan results, before any deep scan has started.
Map<String, dynamic> buildPreviewSnapshot({
  required String rootPath,
  required List<Map<String, dynamic>> quickListEntries,
}) {
  final normalizedRoot = ScanTreeBuilder.normalizeRoot(rootPath);
  final children = quickListEntries.map((entry) {
    final isDir = entry['is_dir'] == true;
    return <String, dynamic>{
      'name': lastPathSegment(entry['path']?.toString() ?? ''),
      'path': normalizeFsPath(entry['path']?.toString() ?? ''),
      'is_dir': isDir,
      'size_bytes': isDir ? 0 : ((entry['size_bytes'] as num?)?.toInt() ?? 0),
      'entry_id': null,
      'scanned': !isDir,
      'children': const <Map<String, dynamic>>[],
    };
  }).toList();

  return <String, dynamic>{
    // Use a unique snapshot_id per preview target so that switching between
    // folders (Custom → Home, or vice versa) invalidates UI caches properly.
    // Without this, both previews would share 'preview' as ID, causing
    // _onSessionChanged to skip cache invalidation when the ID hasn't changed.
    'snapshot_id':
        'preview-${normalizedRoot.hashCode}-${DateTime.now().microsecondsSinceEpoch}',
    'scanned_at_ms': DateTime.now().millisecondsSinceEpoch,
    'reclaimable_estimate_bytes': 0,
    'entries': const <Map<String, dynamic>>[],
    'tree': {
      'name': lastPathSegment(normalizedRoot),
      'path': normalizedRoot,
      'is_dir': true,
      'size_bytes': 0,
      'entry_id': null,
      'scanned': false,
      'children': children,
    },
    'stats': {
      'paths_seen': 0,
      'dirs_seen': 0,
      'files_seen': 0,
      'files_in_snapshot': 0,
      'paths_skipped': 0,
      'truncated': false,
    },
    'warnings': const <String>[],
  };
}
