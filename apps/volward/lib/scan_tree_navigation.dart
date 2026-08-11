import 'scan_tree.dart';
import 'snapshot_query.dart';

/// Applies Finder-style selection to one browser column.
///
/// Clicking the selected row again removes it and every column to its right.
/// Clicking another row replaces the selection at that column and truncates
/// any deeper selection.
List<ScanTreeNode> toggleColumnSelection(
  List<ScanTreeNode> currentChain,
  int columnIndex,
  ScanTreeNode node,
) {
  final prefix = currentChain.take(columnIndex).toList(growable: true);
  final alreadySelected =
      columnIndex < currentChain.length &&
      currentChain[columnIndex].path == node.path;
  if (!alreadySelected) prefix.add(node);
  return prefix;
}

/// Returns the visible records between [anchorPath] and [targetPath],
/// inclusive. The order is the order already presented by the column, so
/// range selection follows the user's active sort and filter.
List<SnapshotNodeRecord> selectColumnRange(
  List<SnapshotNodeRecord> items, {
  required String anchorPath,
  required String targetPath,
}) {
  final anchorIndex = items.indexWhere((item) => item.path == anchorPath);
  final targetIndex = items.indexWhere((item) => item.path == targetPath);
  if (anchorIndex < 0 || targetIndex < 0) return const [];
  final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
  final end = anchorIndex < targetIndex ? targetIndex : anchorIndex;
  return items.sublist(start, end + 1);
}

/// Deepest selected directory, or `null` when browsing the scan root.
String? browsedDirectoryPath(List<ScanTreeNode> selectionChain) {
  for (final node in selectionChain.reversed) {
    if (node.isDirectory) return node.path;
  }
  return null;
}

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
