import 'scan_entry_record.dart';
import 'scan_snapshot_state.dart';
import 'scan_tree.dart';
import 'snapshot_query.dart';
import 'volward_session.dart';
import 'widgets/scan_filter_bar.dart';

class SnapshotCatalog {
  SnapshotCatalog(ScanSnapshotState snapshot) : _snapshot = snapshot {
    final root = snapshot.tree;
    if (root != null && root.isDirectory) {
      _directories[root.path] = root;
    }
  }

  final ScanSnapshotState _snapshot;
  final Map<String, ScanTreeNode> _directories = {};

  SnapshotQueryResult query(SnapshotQueryKey key) {
    if (key.snapshotId != _snapshot.snapshotId) {
      return _emptyResult;
    }
    final node = _directoryForPath(key.path);
    if (node == null) {
      return _emptyResult;
    }
    return queryNode(key: key, node: node);
  }

  ScanTreeNode? _directoryForPath(String path) {
    final cached = _directories[path];
    if (cached != null) return cached;

    final root = _snapshot.tree;
    if (root == null || !root.isDirectory) return null;
    if (path == root.path) {
      _directories[path] = root;
      return root;
    }

    final found = _findDirectory(root, path);
    if (found != null) _directories[path] = found;
    return found;
  }

  ScanTreeNode? _findDirectory(ScanTreeNode node, String path) {
    if (node.path == path) return node;
    if (!node.isDirectory) return null;

    final prefix = node.path.endsWith('/') ? node.path : '${node.path}/';
    if (!path.startsWith(prefix)) return null;

    for (final child in node.children) {
      if (!child.isDirectory) continue;
      final childPath = child.path;
      if (path == childPath || path.startsWith('$childPath/')) {
        return _findDirectory(child, path);
      }
    }
    return null;
  }

  static SnapshotQueryResult queryNode({
    required SnapshotQueryKey key,
    required ScanTreeNode node,
    bool includeEntryRecords = true,
  }) {
    if (!node.isDirectory) return _emptyResult;

    // Fast path: delegate to Rust catalog when the index API is available
    // (Design §7 — avoids Dart tree traversal and keeps memory bounded).
    final session = VolwardSession.instance;
    if (session != null && session.hasIndexApi) {
      final catalogChildren = session.queryDirectoryChildrenFromCatalog(
        node.path,
        categoryFilter: key.categoryFilter,
        deletableOnly: key.deletableOnly,
        sortMode: rustSortModeName(key.sortMode),
      );
      if (catalogChildren != null) {
        // Convert SnapshotNodeRecord → ScanTreeNode for compatibility with
        // the rest of the Dart codebase that still uses ScanTreeNode.
        final allNodes = catalogChildren
            .map((r) => r.toScanTreeNode())
            .toList(growable: false);
        final dirs = allNodes.where((n) => n.isDirectory).toList();
        final files = allNodes.where((n) => !n.isDirectory).toList();
        final entries = includeEntryRecords
            ? files
                .map((n) => n.toEntryRecord())
                .whereType<ScanEntryRecord>()
                .toList(growable: false)
            : const <ScanEntryRecord>[];
        final totalBytes = files.fold<int>(0, (s, n) => s + n.displayBytes);
        final reclaimable = files.where((n) => n.deletable).fold<int>(
              0,
              (s, n) => s + n.displayBytes,
            );
        return SnapshotQueryResult(
          directNodes: List.unmodifiable(<ScanTreeNode>[...dirs, ...files]),
          directChildren: List.unmodifiable(dirs),
          directEntries: List.unmodifiable(entries),
          totalBytes: totalBytes,
          reclaimableBytes: reclaimable,
        );
      }
    }

    // Fallback: Dart-side tree traversal for older builds without index API.
    final children = <ScanTreeNode>[];
    final fileNodes = <ScanTreeNode>[];
    var total = 0;
    var reclaimable = 0;
    for (final child in node.children) {
      if (!child.matchesView(
        categoryFilter: key.categoryFilter,
        deletableOnly: key.deletableOnly,
      )) {
        continue;
      }
      if (child.isDirectory) {
        children.add(child);
      } else {
        fileNodes.add(child);
        total += child.displayBytes;
        if (child.deletable) reclaimable += child.displayBytes;
      }
    }

    children.sort((left, right) => _compareNodes(key.sortMode, left, right));
    fileNodes.sort((left, right) => _compareNodes(key.sortMode, left, right));
    final sortedEntries = includeEntryRecords
        ? fileNodes
            .map((node) => node.toEntryRecord())
            .whereType<ScanEntryRecord>()
            .toList(growable: false)
        : const <ScanEntryRecord>[];
    return SnapshotQueryResult(
      directNodes: List.unmodifiable(<ScanTreeNode>[...children, ...fileNodes]),
      directChildren: List.unmodifiable(children),
      directEntries: List.unmodifiable(sortedEntries),
      totalBytes: total,
      reclaimableBytes: reclaimable,
    );
  }

  static int _compareNodes(
    ScanSortMode sortMode,
    ScanTreeNode left,
    ScanTreeNode right,
  ) {
    switch (sortMode) {
      case ScanSortMode.sizeAsc:
        return left.displayBytes.compareTo(right.displayBytes);
      case ScanSortMode.sizeDesc:
        return right.displayBytes.compareTo(left.displayBytes);
      case ScanSortMode.nameAsc:
        return compareAsciiCaseInsensitive(left.name, right.name);
    }
  }

  static int compareAsciiCaseInsensitive(String left, String right) {
    final leftLength = left.length;
    final rightLength = right.length;
    final limit = leftLength < rightLength ? leftLength : rightLength;
    for (var i = 0; i < limit; i++) {
      var a = left.codeUnitAt(i);
      var b = right.codeUnitAt(i);
      if (a > 0x7F || b > 0x7F) {
        return left.toLowerCase().compareTo(right.toLowerCase());
      }
      if (a >= 0x41 && a <= 0x5A) a += 0x20;
      if (b >= 0x41 && b <= 0x5A) b += 0x20;
      if (a != b) return a.compareTo(b);
    }
    return leftLength.compareTo(rightLength);
  }

  static const SnapshotQueryResult _emptyResult = SnapshotQueryResult(
    directNodes: <ScanTreeNode>[],
    directChildren: <ScanTreeNode>[],
    directEntries: <ScanEntryRecord>[],
    totalBytes: 0,
    reclaimableBytes: 0,
  );
}
