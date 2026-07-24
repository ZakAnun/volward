/// Builds a lightweight, snapshot-shaped map from a `quick_list_dir` result
/// so the UI can render it through the same [ScanTreeNode.fromSnapshotJson]
/// path used for real scan results, before any deep scan has started.
Map<String, dynamic> buildPreviewSnapshot({
  required String rootPath,
  required List<Map<String, dynamic>> quickListEntries,
}) {
  final normalizedRoot = _normalizeRoot(rootPath);
  final children = quickListEntries.map((entry) {
    final isDir = entry['is_dir'] == true;
    return <String, dynamic>{
      'name': _lastPathSegment(entry['path']?.toString() ?? ''),
      'path': entry['path']?.toString() ?? '',
      'is_dir': isDir,
      'size_bytes': isDir ? 0 : ((entry['size_bytes'] as num?)?.toInt() ?? 0),
      'entry_id': null,
      'scanned': !isDir,
      'children': const <Map<String, dynamic>>[],
    };
  }).toList();

  return <String, dynamic>{
    'snapshot_id': 'preview',
    'scanned_at_ms': DateTime.now().millisecondsSinceEpoch,
    'reclaimable_estimate_bytes': 0,
    'entries': const <Map<String, dynamic>>[],
    'tree': {
      'name': _lastPathSegment(normalizedRoot),
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

String _normalizeRoot(String path) {
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

String _lastPathSegment(String path) {
  final normalized = _normalizeRoot(path);
  final idx = normalized.lastIndexOf('/');
  if (idx == -1 || idx == normalized.length - 1) return normalized;
  return normalized.substring(idx + 1);
}
