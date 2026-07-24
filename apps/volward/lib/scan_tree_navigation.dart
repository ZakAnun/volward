import 'scan_tree.dart';

/// Re-resolves [oldChain] (previously-selected nodes, matched by path)
/// against [newRoot] after the underlying snapshot changed — e.g. a
/// background checkpoint or peek scan merged new data. Stops at the first
/// path segment that no longer exists under the new tree, so a still-valid
/// prefix of the user's navigation is preserved instead of resetting to
/// the root.
List<ScanTreeNode> refreshColumnChain(
  ScanTreeNode newRoot,
  List<ScanTreeNode> oldChain,
) {
  final refreshed = <ScanTreeNode>[];
  var current = newRoot;
  for (final oldNode in oldChain) {
    ScanTreeNode? match;
    for (final child in current.children) {
      if (child.path == oldNode.path) {
        match = child;
        break;
      }
    }
    if (match == null) break;
    refreshed.add(match);
    current = match;
  }
  return refreshed;
}
