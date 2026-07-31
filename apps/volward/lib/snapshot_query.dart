import 'scan_entry_record.dart';
import 'scan_tree.dart';
import 'widgets/scan_filter_bar.dart';

String rustSortModeName(ScanSortMode mode) => switch (mode) {
      ScanSortMode.sizeDesc => 'size_desc',
      ScanSortMode.sizeAsc => 'size_asc',
      ScanSortMode.nameAsc => 'name_asc',
    };

// ---------------------------------------------------------------------------
// SnapshotNodeRecord — lightweight node descriptor for catalog query results.
// Mirrors the Rust `SnapshotNodeRecord` struct field-for-field.
// Used by ScanColumnView instead of ScanTreeNode so Dart doesn't need to hold
// the full recursive tree (Design §2.1.4 / §5.1).
// ---------------------------------------------------------------------------

class SnapshotNodeRecord {
  const SnapshotNodeRecord({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.sizeBytes,
    this.entryId,
    this.category,
    this.deletable = false,
    this.scanned = true,
    this.categoryMask = 0,
    this.deletableCategoryMask = 0,
    this.deletableFileCount = 0,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final int sizeBytes;
  final String? entryId;
  final String? category;
  final bool deletable;
  final bool scanned;
  final int categoryMask;
  final int deletableCategoryMask;
  final int deletableFileCount;

  factory SnapshotNodeRecord.fromJson(Map<String, dynamic> json) =>
      SnapshotNodeRecord(
        path: json['path'] as String,
        name: json['name'] as String,
        isDirectory: json['is_directory'] as bool,
        sizeBytes: (json['size_bytes'] as num).toInt(),
        entryId: json['entry_id'] as String?,
        category: json['category'] as String?,
        deletable: json['deletable'] as bool? ?? false,
        scanned: json['scanned'] as bool? ?? true,
        categoryMask: (json['category_mask'] as num?)?.toInt() ?? 0,
        deletableCategoryMask:
            (json['deletable_category_mask'] as num?)?.toInt() ?? 0,
        deletableFileCount:
            (json['deletable_file_count'] as num?)?.toInt() ?? 0,
      );

  factory SnapshotNodeRecord.fromTree(ScanTreeNode node) => SnapshotNodeRecord(
        path: node.path,
        name: node.name,
        isDirectory: node.isDirectory,
        sizeBytes: node.displayBytes,
        entryId: node.entryId,
        category: node.category,
        deletable: node.deletable,
        scanned: node.scanned,
        categoryMask: node.categoryMask,
        deletableCategoryMask: node.deletableCategoryMask,
        deletableFileCount: node.deletableFileCount,
      );

  /// Converts back to a minimal [ScanTreeNode] for code paths that still
  /// require the tree type (e.g. column navigation chain).
  ScanTreeNode toScanTreeNode() => ScanTreeNode(
        name: name,
        path: path,
        isDirectory: isDirectory,
        sizeBytes: sizeBytes,
        entryId: entryId,
        category: category,
        deletable: deletable,
        subtreeBytes: sizeBytes,
        categoryMask: categoryMask,
        deletableCategoryMask: deletableCategoryMask,
        deletableFileCount: deletableFileCount,
        scanned: scanned,
      );

  int get displayBytes => sizeBytes;

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
    if (categoryFilter == null) return true;
    if (isDirectory) {
      return (categoryMask & categoryBit) != 0;
    }
    return (categoryMask & categoryBit) != 0;
  }
}

class SnapshotQueryKey {
  const SnapshotQueryKey({
    required this.snapshotId,
    required this.version,
    required this.path,
    required this.categoryFilter,
    required this.deletableOnly,
    required this.sortMode,
  });

  final String snapshotId;
  final int version;
  final String path;
  final String? categoryFilter;
  final bool deletableOnly;
  final ScanSortMode sortMode;

  SnapshotQueryKey copyWith({String? path}) => SnapshotQueryKey(
        snapshotId: snapshotId,
        version: version,
        path: path ?? this.path,
        categoryFilter: categoryFilter,
        deletableOnly: deletableOnly,
        sortMode: sortMode,
      );

  @override
  bool operator ==(Object other) =>
      other is SnapshotQueryKey &&
      other.snapshotId == snapshotId &&
      other.version == version &&
      other.path == path &&
      other.categoryFilter == categoryFilter &&
      other.deletableOnly == deletableOnly &&
      other.sortMode == sortMode;

  @override
  int get hashCode => Object.hash(
        snapshotId,
        version,
        path,
        categoryFilter,
        deletableOnly,
        sortMode,
      );
}

class SnapshotQueryResult {
  const SnapshotQueryResult({
    required this.directNodes,
    required this.directChildren,
    required this.directEntries,
    required this.totalBytes,
    required this.reclaimableBytes,
  });

  final List<ScanTreeNode> directNodes;
  final List<ScanTreeNode> directChildren;
  final List<ScanEntryRecord> directEntries;
  final int totalBytes;
  final int reclaimableBytes;
}
