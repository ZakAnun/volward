/// One node in the scan results tree (directory or file leaf).
class ScanTreeNode {
  ScanTreeNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.entryId,
    this.entry,
    this.subtreeFileCount,
    this.scanned = true,
    List<ScanTreeNode>? children,
  }) : children = children ?? [];

  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final String? entryId;
  final Map<String, dynamic>? entry;

  /// Precomputed file count under this directory (files only, not dirs).
  final int? subtreeFileCount;

  /// False for directories whose contents haven't been scanned yet (the
  /// pre-scan preview, or a not-yet-covered node before a Wave-2 peek scan
  /// completes). Always true for files and for data from a real scan
  /// snapshot or checkpoint.
  final bool scanned;
  final List<ScanTreeNode> children;

  factory ScanTreeNode.empty(String rootPath) {
    final root = ScanTreeBuilder.normalizeRoot(rootPath);
    final parts = root.split('/').where((s) => s.isNotEmpty).toList();
    final rootName = parts.isEmpty ? root : parts.last;
    return ScanTreeNode(name: rootName, path: root, isDirectory: true);
  }

  factory ScanTreeNode.fromSnapshotJson(
    Map<String, dynamic> json, {
    Map<String, Map<String, dynamic>>? entriesById,
  }) {
    final isDir = json['is_dir'] == true;
    final entryId = json['entry_id']?.toString();
    Map<String, dynamic>? entry;
    if (entryId != null && entriesById != null) {
      entry = entriesById[entryId];
    }

    final childrenJson = json['children'];
    final children = <ScanTreeNode>[];
    if (childrenJson is List) {
      for (final child in childrenJson) {
        if (child is Map) {
          children.add(
            ScanTreeNode.fromSnapshotJson(
              Map<String, dynamic>.from(child),
              entriesById: entriesById,
            ),
          );
        }
      }
    }

    return ScanTreeNode(
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      isDirectory: isDir,
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      entryId: entryId,
      entry: entry,
      scanned: json['scanned'] is bool ? json['scanned'] as bool : true,
      children: children,
    );
  }

  int get totalBytes {
    if (!isDirectory) {
      if (sizeBytes > 0) return sizeBytes;
      return (entry?['size_bytes'] as num?)?.toInt() ?? 0;
    }
    if (sizeBytes > 0) return sizeBytes;
    return children.fold<int>(0, (sum, c) => sum + c.totalBytes);
  }

  int get fileCount {
    if (!isDirectory) return 1;
    if (subtreeFileCount != null) return subtreeFileCount!;
    return children.fold<int>(0, (sum, c) => sum + c.fileCount);
  }

  /// Returns a copy of [node] with [subtreeFileCount] filled for every directory.
  static ScanTreeNode withAggregatedCounts(ScanTreeNode node) {
    if (!node.isDirectory) return node;

    var count = 0;
    final annotatedChildren = node.children.map((child) {
      final annotated = withAggregatedCounts(child);
      count += annotated.fileCount;
      return annotated;
    }).toList();

    return ScanTreeNode(
      name: node.name,
      path: node.path,
      isDirectory: true,
      sizeBytes: node.sizeBytes,
      entryId: node.entryId,
      entry: node.entry,
      subtreeFileCount: count,
      scanned: node.scanned,
      children: annotatedChildren,
    );
  }

  int get displayBytes => sizeBytes > 0 ? sizeBytes : totalBytes;
}

/// Builds a Finder-like directory tree from flat scan entries (file paths only).
abstract final class ScanTreeBuilder {
  static String normalizeRoot(String root) {
    if (root.length > 1 && root.endsWith('/')) {
      return root.substring(0, root.length - 1);
    }
    return root;
  }

  static ScanTreeNode build({
    required List<Map<String, dynamic>> entries,
    required String rootPath,
  }) {
    final root = normalizeRoot(rootPath);
    final parts = root.split('/').where((s) => s.isNotEmpty).toList();
    final rootName = parts.isEmpty ? root : parts.last;
    final tree = ScanTreeNode(name: rootName, path: root, isDirectory: true);

    for (final entry in entries) {
      final rawPath = entry['path_or_uri']?.toString();
      if (rawPath == null || rawPath.isEmpty) continue;
      _insertFile(tree, root, rawPath, entry);
    }

    _sortNode(tree);
    return tree;
  }

  static void _insertFile(
    ScanTreeNode root,
    String rootPath,
    String filePath,
    Map<String, dynamic> entry,
  ) {
    if (!filePath.startsWith(rootPath)) return;

    var relative = filePath.substring(rootPath.length);
    if (relative.startsWith('/')) relative = relative.substring(1);
    if (relative.isEmpty) return;

    final segments = relative.split('/');
    var current = root;
    var currentPath = rootPath;

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isLast = i == segments.length - 1;
      currentPath = '$currentPath/$segment';

      if (isLast) {
        current.children.add(
          ScanTreeNode(
            name: segment,
            path: currentPath,
            isDirectory: false,
            sizeBytes: (entry['size_bytes'] as num?)?.toInt() ?? 0,
            entryId: entry['id']?.toString(),
            entry: entry,
          ),
        );
        return;
      }

      current = _childDir(current, segment, currentPath);
    }
  }

  static ScanTreeNode _childDir(ScanTreeNode parent, String name, String path) {
    for (final child in parent.children) {
      if (child.isDirectory && child.name == name) return child;
    }
    final node = ScanTreeNode(name: name, path: path, isDirectory: true);
    parent.children.add(node);
    return node;
  }

  static void _sortNode(ScanTreeNode node) {
    node.children.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      if (a.isDirectory)
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      final sa = a.totalBytes;
      final sb = b.totalBytes;
      return sb.compareTo(sa);
    });
    for (final child in node.children) {
      if (child.isDirectory) _sortNode(child);
    }
  }
}
