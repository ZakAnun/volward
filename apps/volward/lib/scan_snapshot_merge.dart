/// Splices [subtreeTree] (already in the wire "ScanTreeNode json" shape)
/// into [snapshot]'s `tree` at [targetPath], replacing that node's
/// `size_bytes`/`scanned`/`children`. Also merges [subtreeEntries] into
/// `snapshot['entries']`, overwriting any existing entry with the same
/// `id`, and recomputes `reclaimable_estimate_bytes` locally from the
/// merged entries (rather than trusting a possibly-stale value carried
/// over from an earlier partial result).
///
/// Pure function: [snapshot] is never mutated; a new map is returned.
Map<String, dynamic> mergeSubtreeIntoSnapshot({
  required Map<String, dynamic> snapshot,
  required String targetPath,
  required Map<String, dynamic> subtreeTree,
  required List<Map<String, dynamic>> subtreeEntries,
}) {
  final tree = snapshot['tree'];
  final mergedTree = tree is Map
      ? _replaceNodeAtPath(
          Map<String, dynamic>.from(tree),
          targetPath,
          subtreeTree,
        )
      : subtreeTree;

  final existingEntries = (snapshot['entries'] is List)
      ? (snapshot['entries'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
      : <Map<String, dynamic>>[];
  final byId = <String, Map<String, dynamic>>{
    for (final e in existingEntries)
      if (e['id'] != null) e['id'].toString(): e,
  };
  for (final e in subtreeEntries) {
    final id = e['id']?.toString();
    if (id != null) byId[id] = e;
  }
  final mergedEntries = byId.values.toList();

  final reclaimable = mergedEntries
      .where((e) => e['deletable'] == true)
      .fold<int>(0, (sum, e) => sum + ((e['size_bytes'] as num?)?.toInt() ?? 0));

  return {
    ...snapshot,
    'tree': mergedTree,
    'entries': mergedEntries,
    'reclaimable_estimate_bytes': reclaimable,
  };
}

Map<String, dynamic> _replaceNodeAtPath(
  Map<String, dynamic> node,
  String targetPath,
  Map<String, dynamic> replacement,
) {
  if (node['path']?.toString() == targetPath) {
    return {
      ...node,
      'size_bytes': replacement['size_bytes'],
      'scanned': replacement['scanned'] ?? true,
      'children': replacement['children'],
    };
  }

  final children = node['children'];
  if (children is! List) return node;

  final newChildren = <dynamic>[];
  var found = false;
  for (final child in children) {
    final childPath = (child is Map) ? child['path']?.toString() ?? '' : '';
    final isOnPath = child is Map &&
        childPath.isNotEmpty &&
        (targetPath == childPath ||
            targetPath.startsWith(
              childPath.endsWith('/') ? childPath : '$childPath/',
            ));
    if (isOnPath) {
      newChildren.add(
        _replaceNodeAtPath(
          Map<String, dynamic>.from(child),
          targetPath,
          replacement,
        ),
      );
      found = true;
    } else {
      newChildren.add(child);
    }
  }

  if (!found) return node;
  return {...node, 'children': newChildren};
}
