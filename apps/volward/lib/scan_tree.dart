import 'scan_entry_record.dart';

bool _isUncPath(String path) {
  if (!path.startsWith('//')) return false;
  final parts = path.substring(2).split('/').where((p) => p.isNotEmpty).toList();
  return parts.length >= 2;
}

String? _uncShareRoot(String path) {
  if (!_isUncPath(path)) return null;
  final parts = path.substring(2).split('/').where((p) => p.isNotEmpty).toList();
  return '//${parts[0]}/${parts[1]}';
}

String normalizeFsPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (_isUncPath(normalized)) {
    var trimmed = normalized;
    while (trimmed.length > 1 && trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed == '/' || trimmed.isEmpty) {
      return normalized;
    }
    final shareRoot = _uncShareRoot(trimmed);
    if (shareRoot != null && shareRoot == trimmed) {
      return trimmed;
    }
    return trimmed;
  }
  if (normalized.length > 1 &&
      normalized.endsWith('/') &&
      !_isWindowsDriveRoot(normalized)) {
    return normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

String joinFsPath(String base, String segment) {
  if (base == '/') return '/$segment';
  if (_isWindowsDriveRoot(base) ||
      _isUncPath(base) ||
      base.endsWith('/')) {
    if (base.endsWith('/')) return '$base$segment';
    return '$base/$segment';
  }
  return '$base/$segment';
}

String parentFsPath(String path) {
  final normalized = normalizeFsPath(path);
  if (normalized == '/' || normalized.isEmpty) return '/';
  final shareRoot = _uncShareRoot(normalized);
  if (shareRoot != null && normalized == shareRoot) {
    return shareRoot;
  }
  final idx = normalized.lastIndexOf('/');
  if (idx <= 0) return _isWindowsDriveRoot(normalized) ? normalized : '/';
  if (idx == 2 && _hasWindowsDrivePrefix(normalized)) {
    return normalized.substring(0, 3);
  }
  return normalized.substring(0, idx);
}

String lastPathSegment(String path) {
  final normalized = normalizeFsPath(path);
  final idx = normalized.lastIndexOf('/');
  if (idx == -1) return normalized;
  if (idx == normalized.length - 1) {
    return normalized.isEmpty ? normalized : normalized.substring(0, normalized.length - 1);
  }
  return normalized.substring(idx + 1);
}

bool _isWindowsDriveRoot(String path) {
  return _hasWindowsDrivePrefix(path) &&
      path.length == 3 &&
      path.codeUnitAt(1) == 58 &&
      path.codeUnitAt(2) == 47 &&
      ((path.codeUnitAt(0) >= 65 && path.codeUnitAt(0) <= 90) ||
          (path.codeUnitAt(0) >= 97 && path.codeUnitAt(0) <= 122));
}

bool _hasWindowsDrivePrefix(String path) {
  return path.length >= 3 &&
      path.codeUnitAt(1) == 58 &&
      path.codeUnitAt(2) == 47 &&
      ((path.codeUnitAt(0) >= 65 && path.codeUnitAt(0) <= 90) ||
          (path.codeUnitAt(0) >= 97 && path.codeUnitAt(0) <= 122));
}

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
    int? subtreeBytes,
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
       subtreeBytes =
           subtreeBytes ??
           _deriveSubtreeBytes(
             isDirectory,
             sizeBytes,
             entry?.sizeBytes,
             children,
           ),
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
           ),
       _entry = entry;

  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final String? entryId;
  final String category;
  final bool deletable;

  /// Precomputed bytes for this node's display. For directories, this is the
  /// known subtree total when Rust did not provide a non-zero size.
  final int subtreeBytes;

  /// Precomputed file count under this directory (files only, not dirs).
  final int? subtreeFileCount;
  final int categoryMask;
  final int deletableCategoryMask;
  final int deletableFileCount;
  final ScanEntryRecord? _entry;

  /// False for directories whose contents haven't been scanned yet (the
  /// pre-scan preview, or a not-yet-covered node before a Wave-2 peek scan
  /// completes). Always true for files and for data from a real scan
  /// snapshot or checkpoint.
  final bool scanned;
  final bool peekScanned;
  final List<ScanTreeNode> children;

  /// Backwards-compatible read-only view of the node's leaf payload.
  ScanEntryRecord? get entry => toEntryRecord();

  static int _deriveSubtreeBytes(
    bool isDirectory,
    int sizeBytes,
    int? entrySizeBytes,
    List<ScanTreeNode>? children,
  ) {
    if (!isDirectory) return sizeBytes > 0 ? sizeBytes : (entrySizeBytes ?? 0);
    if (sizeBytes > 0) return sizeBytes;
    var total = 0;
    for (final child in children ?? const <ScanTreeNode>[]) {
      total += child.displayBytes;
    }
    return total;
  }

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
    if (_entry != null) return _entry;
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
          ? normalizeFsPath(entry.pathOrUri)
          : normalizeFsPath(fallbackPath),
      isDirectory: isDir,
      sizeBytes: sizeBytes,
      entryId: entryId,
      entry: entry,
      category: entry?.category ?? json['category']?.toString(),
      deletable: entry?.deletable ?? json['deletable'] == true,
      scanned: json['scanned'] is bool ? json['scanned'] as bool : true,
      peekScanned: json['peekScanned'] == true,
      children: children,
    );
  }

  int get totalBytes {
    return displayBytes;
  }

  int get fileCount {
    if (!isDirectory) return 1;
    if (subtreeFileCount != null) return subtreeFileCount!;
    return children.fold<int>(0, (sum, c) => sum + c.fileCount);
  }

  /// Returns a copy of [node] with subtree totals filled for every directory.
  static ScanTreeNode withAggregatedCounts(ScanTreeNode node) {
    if (!node.isDirectory) return node;

    var count = 0;
    var bytes = 0;
    final annotatedChildren = node.children.map((child) {
      final annotated = withAggregatedCounts(child);
      count += annotated.fileCount;
      bytes += annotated.displayBytes;
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
      subtreeBytes: node.sizeBytes > 0 ? node.sizeBytes : bytes,
      subtreeFileCount: count,
      scanned: node.scanned,
      peekScanned: node.peekScanned,
      children: annotatedChildren,
    );
  }

  int get displayBytes => subtreeBytes;

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
    return normalizeFsPath(root);
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
    final normalizedFilePath = normalizeFsPath(filePath);
    if (!normalizedFilePath.startsWith(rootPath)) return;

    var relative = normalizedFilePath.substring(rootPath.length);
    if (relative.startsWith('/')) relative = relative.substring(1);
    if (relative.isEmpty) return;

    final segments = relative.split('/');
    var current = root;
    var currentPath = rootPath;

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isLast = i == segments.length - 1;
      currentPath = joinFsPath(currentPath, segment);

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
