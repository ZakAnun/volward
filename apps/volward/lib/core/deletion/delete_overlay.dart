import '../../scan_tree.dart';
import '../../snapshot_query.dart';

/// Computes the overlay only; Session still owns publishing and invalidation.
({List<ScanTreeNode> remaining, Set<String> removedPaths}) deletedEntryOverlay({
  required List<SnapshotNodeRecord> records,
  required List<String> targets,
  required Map<String, dynamic> report,
  Map<String, String>? targetPathById,
}) {
  final targetIds = targets.toSet();
  final targetPaths = <String>{
    for (final target in targets)
      ScanTreeBuilder.normalizeRoot(targetPathById?[target] ?? target),
  };
  final failedPaths =
      (report['failed_paths'] as List?)
          ?.whereType<Object>()
          .map((path) => ScanTreeBuilder.normalizeRoot(path.toString()))
          .toSet() ??
      <String>{};
  final remaining = <ScanTreeNode>[];
  final removedPaths = <String>{};
  for (final node in records) {
    final matchesTarget =
        (node.entryId != null && targetIds.contains(node.entryId)) ||
        targetPaths.contains(ScanTreeBuilder.normalizeRoot(node.path));
    if (!matchesTarget) {
      remaining.add(node.toScanTreeNode());
      continue;
    }
    final nodePath = ScanTreeBuilder.normalizeRoot(node.path);
    if (failedPaths.contains(nodePath)) {
      remaining.add(node.toScanTreeNode());
    } else {
      removedPaths.add(nodePath);
    }
  }

  return (remaining: remaining, removedPaths: removedPaths);
}
