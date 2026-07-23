import 'scan_tree.dart';

/// Returns a pruned copy of [node], keeping files that satisfy [keep] and
/// ancestor directories that contain at least one kept file.
ScanTreeNode? pruneTree(
  ScanTreeNode node,
  bool Function(Map<String, dynamic> entry) keep,
) {
  if (!node.isDirectory) {
    final entry = node.entry;
    if (entry == null) return null;
    return keep(entry) ? node : null;
  }

  final prunedChildren = <ScanTreeNode>[];
  for (final child in node.children) {
    final pruned = pruneTree(child, keep);
    if (pruned != null) prunedChildren.add(pruned);
  }

  if (prunedChildren.isEmpty) return null;

  return ScanTreeNode(
    name: node.name,
    path: node.path,
    isDirectory: true,
    sizeBytes: node.sizeBytes,
    entryId: node.entryId,
    entry: node.entry,
    children: prunedChildren,
  );
}
