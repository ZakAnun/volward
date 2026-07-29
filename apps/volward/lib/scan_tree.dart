import 'scan_entry_record.dart';

/// One node in the scan results tree (directory or file leaf).
class ScanTreeNode {
  ScanTreeNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.entryId,
    ScanEntryRecord? entry,
    String? category,
    bool? deletable,
    int? subtreeFileCount,
    int? categoryMask,
    int? deletableCategoryMask,
    int? deletableFileCount,
    this.scanned = true,
    this.peekScanned = false,
    List<ScanTreeNode>? children,
  }) : children = children ?? [],
       category =
           category ?? entry?.category ?? (isDirectory ? 'Folder' : 'Unknown'),
       deletable = deletable ?? entry?.deletable ?? false,
       subtreeFileCount =
           subtreeFileCount ?? _deriveFileCount(isDirectory, children),
       categoryMask =
           categoryMask ??
           _deriveCategoryMask(
             isDirectory,
             category ?? entry?.category ?? 'Unknown',
             children,
           ),
       deletableCategoryMask =
           deletableCategoryMask ??
           _deriveDeletableCategoryMask(
             isDirectory,
             category ?? entry?.category ?? 'Unknown',
             deletable ?? entry?.deletable ?? false,
             children,
           ),
       deletableFileCount =
           deletableFileCount ??
           _deriveDeletableFileCount(
             isDirectory,
             deletable ?? entry?.deletable ?? false,
             children,
           );

  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final String? entryId;
  final String category;
  final bool deletable;

  /// Precomputed file count under this directory (files only, not dirs).
  final int? subtreeFileCount;
  final int categoryMask;
  final int deletableCategoryMask;
  final int deletableFileCount;

  /// False for directories whose contents haven't been scanned yet (the
  /// pre-scan preview, or a not-yet-covered node before a Wave-2 peek scan
  /// completes). Always true for files and for data from a real scan
  /// snapshot or checkpoint.
  final bool scanned;
  final bool peekScanned;
  final List<ScanTreeNode> children;

  /// Backwards-compatible read-only view of the node's leaf payload.
  ScanEntryRecord? get entry => toEntryRecord();

  static int _deriveFileCount(bool isDirectory, List<ScanTreeNode>? children) {
    if (!isDirectory) return 1;
    var count = 0;
    for (final child in children ?? const <ScanTreeNode>[]) {
      count += child.fileCount;
    }
    return count;
  }

  static int _deriveCategoryMask(
    bool isDirectory,
    String category,
    List<ScanTreeNode>? children,
  ) {
    if (!isDirectory) return ScanEntryRecord.categoryMaskFor(category);
    var mask = 0;
    for (final child in children ?? const <ScanTreeNode>[]) {
      mask |= child.categoryMask;
    }
    return mask;
  }

  static int _deriveDeletableCategoryMask(
    bool isDirectory,
    String category,
    bool deletable,
    List<ScanTreeNode>? children,
  ) {
    if (!isDirectory) {
      return deletable ? ScanEntryRecord.categoryMaskFor(category) : 0;
    }
    var mask = 0;
    for (final child in children ?? const <ScanTreeNode>[]) {
      mask |= child.deletableCategoryMask;
    }
    return mask;
  }

  static int _deriveDeletableFileCount(
    bool isDirectory,
    bool deletable,
    List<ScanTreeNode>? children,
  ) {
    if (!isDirectory) return deletable ? 1 : 0;
    var count = 0;
    for (final child in children ?? const <ScanTreeNode>[]) {
      count += child.deletableFileCount;
    }
    return count;
  }

  bool matchesView({String? categoryFilter, required bool deletableOnly}) {
    if (categoryFilter == null && !deletableOnly) return true;
    final categoryBit = ScanEntryRecord.categoryMaskFor(categoryFilter);
    if (deletableOnly) {
      if (deletableFileCount == 0) return false;
      if (categoryFilter != null) {
        return (deletableCategoryMask & categoryBit) != 0;
      }
      return true;
    }
    return (categoryMask & categoryBit) != 0;
  }

  ScanEntryRecord? toEntryRecord() {
    if (isDirectory) return null;
    final id = entryId ?? path;
    if (id.isEmpty || path.isEmpty) return null;
    return ScanEntryRecord(
      id: id,
      displayName: name,
      pathOrUri: path,
      sizeBytes: displayBytes,
      category: category,
      deletable: deletable,
    );
  }

  factory ScanTreeNode.empty(String rootPath) {
    final root = ScanTreeBuilder.normalizeRoot(rootPath);
    final parts = root.split('/').where((s) => s.isNotEmpty).toList();
    final rootName = parts.isEmpty ? root : parts.last;
    return ScanTreeNode(name: rootName, path: root, isDirectory: true);
  }

  factory ScanTreeNode.fromSnapshotJson(
    Map<String, dynamic> json, {
    Map<String, ScanEntryRecord>? entriesById,
  }) {
    final isDir = json['is_dir'] == true;
    final entryId = json['entry_id']?.toString();
    ScanEntryRecord? entry;
    if (entryId != null && entriesById != null) {
      entry = entriesById[entryId];
    }
    if (entry == null && !isDir) {
      final path = json['path']?.toString() ?? '';
      final jsonSize = (json['size_bytes'] as num?)?.toInt();
      final jsonCategory = json['category']?.toString();
      entry = ScanEntryRecord(
        id: entryId ?? path,
        displayName: json['name']?.toString() ?? '',
        pathOrUri: path,
        sizeBytes: jsonSize ?? 0,
        category: jsonCategory ?? 'Unknown',
        deletable: json['deletable'] == true,
      );
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

    final fallbackPath = json['path']?.toString() ?? '';
    final fallbackName = json['name']?.toString() ?? '';
    final jsonSize = (json['size_bytes'] as num?)?.toInt();
    final entrySize = entry?.sizeBytes ?? 0;
    final sizeBytes =
        !isDir && entrySize > 0 && (jsonSize == null || jsonSize == 0)
        ? entrySize
        : (jsonSize ?? entrySize);
    return ScanTreeNode(
      name: !isDir && entry != null && entry.displayName.isNotEmpty
          ? entry.displayName
          : fallbackName,
      path: !isDir && entry != null && entry.pathOrUri.isNotEmpty
          ? entry.pathOrUri
          : fallbackPath,
      isDirectory: isDir,
      sizeBytes: sizeBytes,
      entryId: entryId,
      category: entry?.category ?? json['category']?.toString(),
      deletable: entry?.deletable ?? json['deletable'] == true,
      scanned: json['scanned'] is bool ? json['scanned'] as bool : true,
      peekScanned: json['peekScanned'] == true,
      children: children,
    );
  }

  int get totalBytes {
    if (!isDirectory) {
      return sizeBytes;
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
      category: node.category,
      deletable: node.deletable,
      subtreeFileCount: count,
      scanned: node.scanned,
      peekScanned: node.peekScanned,
      children: annotatedChildren,
    );
  }

  /// Lazily computed and memoized display size.
  ///
  /// Avoids repeated O(subtree) [totalBytes] recursion when [sizeBytes] is 0
  /// (e.g. directories not yet sized by the background scan).  Uses [late final]
  /// so the value is computed at most once per node instance, regardless of how
  /// many times [displayBytes] is accessed during sorting or rendering.
  late final int displayBytes = sizeBytes > 0 ? sizeBytes : totalBytes;

  Map<String, dynamic> toWire() {
    return {
      'name': name,
      'path': path,
      'is_dir': isDirectory,
      'size_bytes': sizeBytes,
      'entry_id': entryId,
      'category': category,
      'deletable': deletable,
      'scanned': scanned,
      if (peekScanned) 'peekScanned': true,
      'children': children.map((c) => c.toWire()).toList(growable: false),
    };
  }
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
    required List<ScanEntryRecord> entries,
    required String rootPath,
  }) {
    final root = normalizeRoot(rootPath);
    final parts = root.split('/').where((s) => s.isNotEmpty).toList();
    final rootName = parts.isEmpty ? root : parts.last;
    final tree = ScanTreeNode(name: rootName, path: root, isDirectory: true);

    for (final entry in entries) {
      final rawPath = entry.pathOrUri;
      if (rawPath.isEmpty) continue;
      _insertFile(tree, root, rawPath, entry);
    }

    _sortNode(tree);
    return ScanTreeNode.withAggregatedCounts(tree);
  }

  static void _insertFile(
    ScanTreeNode root,
    String rootPath,
    String filePath,
    ScanEntryRecord entry,
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
            sizeBytes: entry.sizeBytes,
            entryId: entry.id,
            category: entry.category,
            deletable: entry.deletable,
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
      if (a.isDirectory) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      final sa = a.totalBytes;
      final sb = b.totalBytes;
      return sb.compareTo(sa);
    });
    for (final child in node.children) {
      if (child.isDirectory) _sortNode(child);
    }
  }
}
