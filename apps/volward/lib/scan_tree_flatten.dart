import 'scan_tree.dart';

class FlatRow {
  const FlatRow({
    required this.node,
    required this.depth,
    required this.isExpanded,
  });

  final ScanTreeNode node;
  final int depth;
  final bool isExpanded;
}

/// Flattens [root] into visible rows based on [expandedPaths].
List<FlatRow> flattenVisible(
  ScanTreeNode root,
  Set<String> expandedPaths, {
  Map<String, List<ScanTreeNode>> visibleChildrenByPath = const {},
}) {
  final out = <FlatRow>[];

  void walk(ScanTreeNode node, int depth) {
    out.add(
      FlatRow(
        node: node,
        depth: depth,
        isExpanded: expandedPaths.contains(node.path),
      ),
    );
    if (!node.isDirectory || !expandedPaths.contains(node.path)) return;
    for (final child in visibleChildrenByPath[node.path] ?? node.children) {
      walk(child, depth + 1);
    }
  }

  walk(root, 0);
  return out;
}
