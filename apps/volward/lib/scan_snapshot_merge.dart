import 'scan_entry_record.dart';
import 'scan_snapshot_state.dart';
import 'scan_tree.dart';

/// Merges a subtree snapshot into [snapshot] and returns the result as a raw
/// wire map for callers that still use the old [Map<String, dynamic>] API.
///
/// The tree merge is delegated to [mergeSubtreeIntoSnapshotState]. The flat
/// [snapshot]['entries'] list is merged separately by id so that legacy
/// snapshots whose entries are not linked to tree leaf nodes (no [entry_id]
/// in the tree) still have their entries preserved and de-duplicated in the
/// returned wire map.
Map<String, dynamic> mergeSubtreeIntoSnapshot({
  required Map<String, dynamic> snapshot,
  required String targetPath,
  required Map<String, dynamic> subtreeTree,
  required List<Map<String, dynamic>> subtreeEntries,
  bool replacementIsAuthoritative = false,
}) {
  final mergedState = mergeSubtreeIntoSnapshotState(
    snapshot: ScanSnapshotState.fromWire(snapshot),
    targetPath: targetPath,
    subtreeTree: subtreeTree,
    subtreeEntries: subtreeEntries,
    replacementIsAuthoritative: replacementIsAuthoritative,
  );

  // Build the base wire map from the tree-based merged state.
  final wire = mergedState.toWire();

  // Merge the flat entries list so callers that maintain entries outside the
  // tree structure (no entry_id on tree leaf nodes) still get correct output.
  // Start from the snapshot's existing flat entries, override with subtree
  // entries (fresh data wins on id collision), then apply path-based cleanup
  // for authoritative (peek) merges.
  final oldFlat =
      (snapshot['entries'] as List?)
          ?.whereType<Map>()
          .map(
            (e) => e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e),
          )
          .toList() ??
      <Map<String, dynamic>>[];

  if (oldFlat.isNotEmpty || subtreeEntries.isNotEmpty) {
    final byId = <String, Map<String, dynamic>>{};

    // Seed from existing flat entries.
    for (final e in oldFlat) {
      final id = e['id']?.toString();
      if (id != null) byId[id] = e;
    }

    // Fresh subtree entries override stale ones with the same id.
    for (final e in subtreeEntries) {
      final id = e['id']?.toString();
      if (id != null) byId[id] = e;
    }

    // Also include any entries materialized from the merged tree (handles
    // well-formed snapshots where entries are linked via entry_id).
    for (final record in mergedState.materializeEntries()) {
      byId[record.id] ??= record.toWire();
    }

    // For authoritative (peek) merges remove stale entries whose path falls
    // under the target but whose id is absent from the fresh result.
    if (replacementIsAuthoritative) {
      final prefix = targetPath.endsWith('/') ? targetPath : '$targetPath/';
      final freshIds = <String>{
        for (final e in subtreeEntries)
          if (e['id'] != null) e['id'].toString(),
        for (final r in mergedState.materializeEntries()) r.id,
      };
      byId.removeWhere((id, e) {
        final path = e['path_or_uri']?.toString() ?? '';
        final underTarget = path == targetPath || path.startsWith(prefix);
        return underTarget && !freshIds.contains(id);
      });
    }

    wire['entries'] = byId.values.toList(growable: false);
    wire['reclaimable_estimate_bytes'] = byId.values
        .where((e) => e['deletable'] == true)
        .fold<int>(0, (s, e) => s + ((e['size_bytes'] as num?)?.toInt() ?? 0));
  }

  return wire;
}

ScanSnapshotState mergeSubtreeIntoSnapshotState({
  required ScanSnapshotState snapshot,
  required String targetPath,
  required Map<String, dynamic> subtreeTree,
  required List<Map<String, dynamic>> subtreeEntries,
  bool replacementIsAuthoritative = false,
}) {
  final currentTree = snapshot.tree ?? _legacyTreeFallback(snapshot);
  final incomingTree = _buildIncomingTree(subtreeTree, subtreeEntries);
  if (incomingTree == null) return snapshot;

  final mergedTree = currentTree == null
      ? incomingTree
      : _replaceNodeAtPath(
          currentTree,
          targetPath,
          replacement: incomingTree,
          replacementIsAuthoritative: replacementIsAuthoritative,
        );

  final oldSubtree = _nodeAtPath(currentTree, targetPath);
  final newSubtree = _nodeAtPath(mergedTree, targetPath);
  if (newSubtree == null) {
    return snapshot;
  }

  final oldSummary = oldSubtree == null
      ? const ScanSnapshotSummary(
          entryCount: 0,
          categoryCounts: <String, int>{},
          deletableCategoryCounts: <String, int>{},
          deletableCount: 0,
        )
      : summarizeSnapshotTree(oldSubtree);
  final newSummary = summarizeSnapshotTree(newSubtree);

  final summary = replacementIsAuthoritative
      ? summarizeSnapshotTree(mergedTree)
      : _applyDelta(
          baseCounts: snapshot.categoryCounts,
          baseDeletableCounts: snapshot.deletableCategoryCounts,
          baseEntryCount: snapshot.entryCount,
          baseDeletableCount: snapshot.deletableCount,
          oldSummary: oldSummary,
          newSummary: newSummary,
        );
  return ScanSnapshotState(
    snapshotId: snapshot.snapshotId,
    scannedAtMs: snapshot.scannedAtMs,
    stats: snapshot.stats,
    reclaimableEstimateBytes: replacementIsAuthoritative
        ? _reclaimableFromTree(mergedTree)
        : snapshot.reclaimableEstimateBytes -
              _reclaimableFromTree(oldSubtree) +
              _reclaimableFromTree(newSubtree),
    tree: mergedTree,
    entryCount: summary.entryCount,
    categoryCounts: summary.categoryCounts,
    deletableCategoryCounts: summary.deletableCategoryCounts,
    deletableCount: summary.deletableCount,
    extraFields: snapshot.extraFields,
  );
}

ScanTreeNode? _buildIncomingTree(
  Map<String, dynamic> subtreeTree,
  List<Map<String, dynamic>> subtreeEntries,
) {
  final byId = <String, ScanEntryRecord>{
    for (final entry in subtreeEntries)
      if (entry['id'] != null)
        entry['id'].toString(): ScanEntryRecord.fromWire(entry),
  };
  final tree = ScanTreeNode.fromSnapshotJson(
    Map<String, dynamic>.from(subtreeTree),
    entriesById: byId,
  );
  return tree;
}

ScanTreeNode? _nodeAtPath(ScanTreeNode? root, String targetPath) {
  if (root == null) return null;
  if (root.path == targetPath) return root;
  if (!root.isDirectory) return null;
  for (final child in root.children) {
    final found = _nodeAtPath(child, targetPath);
    if (found != null) return found;
  }
  return null;
}

ScanTreeNode _replaceNodeAtPath(
  ScanTreeNode node,
  String targetPath, {
  required ScanTreeNode replacement,
  required bool replacementIsAuthoritative,
}) {
  if (node.path == targetPath) {
    return ScanTreeNode(
      name: node.name,
      path: node.path,
      isDirectory: node.isDirectory,
      sizeBytes: replacement.sizeBytes,
      entryId: node.entryId,
      category: node.category,
      deletable: node.deletable,
      scanned: replacement.scanned,
      peekScanned: replacementIsAuthoritative || node.peekScanned,
      children: replacementIsAuthoritative
          ? replacement.children
          : _mergeChildrenByPath(node.children, replacement.children),
    );
  }

  if (!node.isDirectory) return node;

  final newChildren = <ScanTreeNode>[];
  var found = false;
  for (final child in node.children) {
    final childPath = child.path;
    final isOnPath =
        childPath.isNotEmpty &&
        (targetPath == childPath ||
            targetPath.startsWith(
              childPath.endsWith('/') ? childPath : '$childPath/',
            ));
    if (isOnPath) {
      newChildren.add(
        _replaceNodeAtPath(
          child,
          targetPath,
          replacement: replacement,
          replacementIsAuthoritative: replacementIsAuthoritative,
        ),
      );
      found = true;
    } else {
      newChildren.add(child);
    }
  }

  if (!found) return node;
  return ScanTreeNode(
    name: node.name,
    path: node.path,
    isDirectory: true,
    sizeBytes: node.sizeBytes,
    entryId: node.entryId,
    category: node.category,
    deletable: node.deletable,
    scanned: node.scanned,
    peekScanned: node.peekScanned,
    children: newChildren,
  );
}

List<ScanTreeNode> _mergeChildrenByPath(
  List<ScanTreeNode> oldChildren,
  List<ScanTreeNode> newChildren,
) {
  final oldByPath = <String, ScanTreeNode>{
    for (final child in oldChildren) child.path: child,
  };

  final merged = <ScanTreeNode>[];
  final seenPaths = <String>{};
  for (final newChild in newChildren) {
    final path = newChild.path;
    seenPaths.add(path);
    final oldChild = oldByPath[path];
    merged.add(
      oldChild == null ? newChild : _pickMoreComplete(oldChild, newChild),
    );
  }
  for (final entry in oldByPath.entries) {
    if (!seenPaths.contains(entry.key)) merged.add(entry.value);
  }
  return merged;
}

/// Keeps whichever side of a duplicate-path child looks more complete.
ScanTreeNode _pickMoreComplete(ScanTreeNode oldChild, ScanTreeNode newChild) {
  final oldPeeked = oldChild.peekScanned;
  final oldSize = oldChild.sizeBytes;
  final newSize = newChild.sizeBytes;
  if (oldPeeked && oldSize > newSize) return oldChild;

  if (newChild.isDirectory) {
    final oldScanned = oldPeeked || oldChild.scanned;
    return ScanTreeNode(
      name: newChild.name,
      path: newChild.path,
      isDirectory: true,
      sizeBytes: newChild.sizeBytes,
      entryId: newChild.entryId,
      category: newChild.category,
      deletable: newChild.deletable,
      scanned: true,
      peekScanned: oldChild.peekScanned || newChild.peekScanned,
      children: oldScanned
          ? _mergeChildrenByPath(oldChild.children, newChild.children)
          : newChild.children,
    );
  }
  return newChild;
}

int _reclaimableFromTree(ScanTreeNode? node) {
  if (node == null) return 0;
  if (!node.isDirectory) {
    return node.deletable ? node.sizeBytes : 0;
  }
  var total = 0;
  for (final child in node.children) {
    total += _reclaimableFromTree(child);
  }
  return total;
}

ScanSnapshotSummary _applyDelta({
  required Map<String, int> baseCounts,
  required Map<String, int> baseDeletableCounts,
  required int baseEntryCount,
  required int baseDeletableCount,
  required ScanSnapshotSummary oldSummary,
  required ScanSnapshotSummary newSummary,
}) {
  final categoryCounts = Map<String, int>.from(baseCounts);
  for (final entry in oldSummary.categoryCounts.entries) {
    categoryCounts[entry.key] = (categoryCounts[entry.key] ?? 0) - entry.value;
  }
  for (final entry in newSummary.categoryCounts.entries) {
    categoryCounts[entry.key] = (categoryCounts[entry.key] ?? 0) + entry.value;
  }

  final deletableCategoryCounts = Map<String, int>.from(baseDeletableCounts);
  for (final entry in oldSummary.deletableCategoryCounts.entries) {
    deletableCategoryCounts[entry.key] =
        (deletableCategoryCounts[entry.key] ?? 0) - entry.value;
  }
  for (final entry in newSummary.deletableCategoryCounts.entries) {
    deletableCategoryCounts[entry.key] =
        (deletableCategoryCounts[entry.key] ?? 0) + entry.value;
  }

  return ScanSnapshotSummary(
    entryCount: baseEntryCount - oldSummary.entryCount + newSummary.entryCount,
    categoryCounts: Map.unmodifiable(categoryCounts),
    deletableCategoryCounts: Map.unmodifiable(deletableCategoryCounts),
    deletableCount:
        baseDeletableCount -
        oldSummary.deletableCount +
        newSummary.deletableCount,
  );
}

ScanTreeNode? _legacyTreeFallback(ScanSnapshotState snapshot) {
  if (!snapshot.hasFlatEntries) return null;
  final entries = snapshot.materializeEntries();
  if (entries.isEmpty) return null;
  final rootPath = _inferRootPath(snapshot, entries);
  if (rootPath == null || rootPath.isEmpty) return null;
  return ScanTreeBuilder.build(entries: entries, rootPath: rootPath);
}

String? _inferRootPath(
  ScanSnapshotState snapshot,
  List<ScanEntryRecord> entries,
) {
  for (final key in const ['root', 'root_path', 'scan_root']) {
    final value = snapshot.extraFields[key]?.toString();
    if (value != null && value.isNotEmpty) {
      return ScanTreeBuilder.normalizeRoot(value);
    }
  }

  final paths = entries
      .map((entry) => entry.pathOrUri)
      .where((path) => path.isNotEmpty)
      .toList();
  if (paths.isEmpty) return null;
  if (paths.length == 1) {
    return ScanTreeBuilder.normalizeRoot(_parentDir(paths.first));
  }

  final firstSegments = _pathSegments(paths.first);
  var commonSegments = firstSegments;
  for (final path in paths.skip(1)) {
    final nextSegments = _pathSegments(path);
    final limit = commonSegments.length < nextSegments.length
        ? commonSegments.length
        : nextSegments.length;
    var i = 0;
    while (i < limit && commonSegments[i] == nextSegments[i]) {
      i++;
    }
    commonSegments = commonSegments.sublist(0, i);
    if (commonSegments.isEmpty) break;
  }
  if (commonSegments.isEmpty) return null;
  return ScanTreeBuilder.normalizeRoot('/${commonSegments.join('/')}');
}

String _parentDir(String path) {
  final normalized = path.endsWith('/') && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
  final idx = normalized.lastIndexOf('/');
  if (idx <= 0) return normalized;
  return normalized.substring(0, idx);
}

List<String> _pathSegments(String path) {
  return path.split('/').where((part) => part.isNotEmpty).toList();
}
