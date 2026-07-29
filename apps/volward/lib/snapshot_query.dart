import 'scan_entry_record.dart';
import 'scan_tree.dart';
import 'widgets/scan_filter_bar.dart';

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
    required this.directChildren,
    required this.directEntries,
    required this.totalBytes,
    required this.reclaimableBytes,
  });

  final List<ScanTreeNode> directChildren;
  final List<ScanEntryRecord> directEntries;
  final int totalBytes;
  final int reclaimableBytes;
}
