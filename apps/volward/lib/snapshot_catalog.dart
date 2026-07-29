import 'scan_entry_record.dart';
import 'scan_snapshot_state.dart';
import 'scan_tree.dart';
import 'snapshot_query.dart';
import 'widgets/scan_filter_bar.dart';

class SnapshotCatalog {
  SnapshotCatalog(ScanSnapshotState snapshot) : _snapshot = snapshot {
    final root = snapshot.tree;
    if (root != null) _index(root);
  }

  final ScanSnapshotState _snapshot;
  final Map<String, ScanTreeNode> _directories = {};

  void _index(ScanTreeNode node) {
    if (!node.isDirectory) {
      return;
    }
    _directories[node.path] = node;
    for (final child in node.children) {
      _index(child);
    }
  }

  SnapshotQueryResult query(SnapshotQueryKey key) {
    if (key.snapshotId != _snapshot.snapshotId) {
      return const SnapshotQueryResult(
        directNodes: <ScanTreeNode>[],
        directChildren: <ScanTreeNode>[],
        directEntries: <ScanEntryRecord>[],
        totalBytes: 0,
        reclaimableBytes: 0,
      );
    }
    final node = _directories[key.path];
    if (node == null) {
      return const SnapshotQueryResult(
        directNodes: <ScanTreeNode>[],
        directChildren: <ScanTreeNode>[],
        directEntries: <ScanEntryRecord>[],
        totalBytes: 0,
        reclaimableBytes: 0,
      );
    }
    final children = <ScanTreeNode>[];
    final fileNodes = <ScanTreeNode>[];
    final entries = <ScanEntryRecord>[];
    for (final child in node.children) {
      if (!child.matchesView(
        categoryFilter: key.categoryFilter,
        deletableOnly: key.deletableOnly,
      )) {
        continue;
      }
      final entry = child.toEntryRecord();
      if (entry == null) {
        children.add(child);
      } else {
        fileNodes.add(child);
        entries.add(entry);
      }
    }
    int compare(ScanTreeNode left, ScanTreeNode right) {
      switch (key.sortMode) {
        case ScanSortMode.sizeAsc:
          return left.displayBytes.compareTo(right.displayBytes);
        case ScanSortMode.sizeDesc:
          return right.displayBytes.compareTo(left.displayBytes);
        case ScanSortMode.nameAsc:
          return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      }
    }

    children.sort(compare);
    fileNodes.sort(compare);
    final sortedEntries = fileNodes
        .map((node) => node.toEntryRecord())
        .whereType<ScanEntryRecord>()
        .toList(growable: false);
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.sizeBytes);
    final reclaimable = entries
        .where((entry) => entry.deletable)
        .fold<int>(0, (sum, entry) => sum + entry.sizeBytes);
    return SnapshotQueryResult(
      directNodes: List.unmodifiable(<ScanTreeNode>[...children, ...fileNodes]),
      directChildren: List.unmodifiable(children),
      directEntries: List.unmodifiable(sortedEntries),
      totalBytes: total,
      reclaimableBytes: reclaimable,
    );
  }
}
