import 'dart:convert';

class CoverageSnapshotFingerprint {
  const CoverageSnapshotFingerprint({
    required this.rootSizeBytes,
    required this.scannedAtMs,
    required this.pathsSeen,
    required this.dirsSeen,
    required this.filesSeen,
    required this.filesInSnapshot,
    required this.pathsSkipped,
    required this.truncated,
    required this.incompleteReason,
  });

  factory CoverageSnapshotFingerprint.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] is Map
        ? Map<String, dynamic>.from(json['stats'] as Map)
        : json;
    return CoverageSnapshotFingerprint(
      rootSizeBytes: (json['root_size_bytes'] as num?)?.toInt() ?? 0,
      scannedAtMs: (json['scanned_at_ms'] as num?)?.toInt() ?? 0,
      pathsSeen: (stats['paths_seen'] as num?)?.toInt() ?? 0,
      dirsSeen: (stats['dirs_seen'] as num?)?.toInt() ?? 0,
      filesSeen: (stats['files_seen'] as num?)?.toInt() ?? 0,
      filesInSnapshot: (stats['files_in_snapshot'] as num?)?.toInt() ?? 0,
      pathsSkipped: (stats['paths_skipped'] as num?)?.toInt() ?? 0,
      truncated: stats['truncated'] == true,
      incompleteReason: stats['incomplete_reason']?.toString(),
    );
  }

  final int rootSizeBytes;
  final int scannedAtMs;
  final int pathsSeen;
  final int dirsSeen;
  final int filesSeen;
  final int filesInSnapshot;
  final int pathsSkipped;
  final bool truncated;
  final String? incompleteReason;

  bool matches(CoverageSnapshotFingerprint other) =>
      rootSizeBytes == other.rootSizeBytes &&
      scannedAtMs == other.scannedAtMs &&
      pathsSeen == other.pathsSeen &&
      dirsSeen == other.dirsSeen &&
      filesSeen == other.filesSeen &&
      filesInSnapshot == other.filesInSnapshot &&
      pathsSkipped == other.pathsSkipped &&
      truncated == other.truncated &&
      incompleteReason == other.incompleteReason;

  Map<String, dynamic> toJson() => {
    'root_size_bytes': rootSizeBytes,
    'scanned_at_ms': scannedAtMs,
    'stats': {
      'paths_seen': pathsSeen,
      'dirs_seen': dirsSeen,
      'files_seen': filesSeen,
      'files_in_snapshot': filesInSnapshot,
      'paths_skipped': pathsSkipped,
      'truncated': truncated,
      if (incompleteReason != null) 'incomplete_reason': incompleteReason,
    },
  };
}

enum CoverageRowKind {
  file,
  group;

  static CoverageRowKind fromWire(Object? value) =>
      value == 'group' ? group : file;
}

class CoverageRow {
  const CoverageRow({
    required this.rowIndex,
    required this.kind,
    required this.path,
    required this.sizeBytes,
    this.memberCount,
    this.cleanupSource,
    this.cleanupHint,
    this.retentionDays,
  });

  factory CoverageRow.fromJson(Map<String, dynamic> json) => CoverageRow(
    rowIndex: (json['row_index'] as num?)?.toInt() ?? 0,
    kind: CoverageRowKind.fromWire(json['kind']),
    path: json['path'] as String,
    sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    memberCount: (json['member_count'] as num?)?.toInt(),
    cleanupSource: json['cleanup_source'] as String?,
    cleanupHint: json['cleanup_hint'] as String?,
    retentionDays: (json['retention_days'] as num?)?.toInt(),
  );

  final int rowIndex;
  final CoverageRowKind kind;
  final String path;
  final int sizeBytes;
  final int? memberCount;
  final String? cleanupSource;
  final String? cleanupHint;
  final int? retentionDays;

  int get memberFiles => memberCount ?? 1;

  Map<String, dynamic> toJson() => {
    'row_index': rowIndex,
    'kind': kind.name,
    'path': path,
    'size_bytes': sizeBytes,
    if (memberCount != null) 'member_count': memberCount,
    if (cleanupSource != null && cleanupSource!.isNotEmpty)
      'cleanup_source': cleanupSource,
    if (cleanupHint != null && cleanupHint!.isNotEmpty)
      'cleanup_hint': cleanupHint,
    if (retentionDays != null) 'retention_days': retentionDays,
  };
}

class CoveragePlanSummary {
  const CoveragePlanSummary({
    required this.snapshotId,
    required this.planVersion,
    required this.rootPath,
    required this.totalUnclassified,
    required this.preClassifiedCount,
    required this.groupRows,
    required this.fileRows,
    required this.estimatedPages,
    this.fingerprint,
    this.seedNodeCount,
    this.tailFileCount,
    this.localSafeFiles,
    this.localKeepFiles,
    this.tailFiles,
    this.treePendingFiles,
    this.estimatedTreeCredits,
    this.estimatedTailCredits,
  });

  factory CoveragePlanSummary.fromJson(Map<String, dynamic> json) {
    final planVersion = (json['plan_version'] as num?)?.toInt() ?? 0;
    var totalUnclassified = (json['total_unclassified'] as num?)?.toInt() ?? 0;
    if (planVersion >= 3 && totalUnclassified == 0) {
      final localSafe = (json['local_safe_files'] as num?)?.toInt() ?? 0;
      final localKeep = (json['local_keep_files'] as num?)?.toInt() ?? 0;
      final tail =
          (json['tail_files'] as num?)?.toInt() ??
          (json['tail_file_count'] as num?)?.toInt() ??
          0;
      final treePending = (json['tree_pending_files'] as num?)?.toInt() ?? 0;
      totalUnclassified = localSafe + localKeep + tail + treePending;
    }
    return CoveragePlanSummary(
      snapshotId: json['snapshot_id'] as String,
      planVersion: planVersion,
      rootPath: json['root_path'] as String,
      totalUnclassified: totalUnclassified,
      preClassifiedCount: (json['pre_classified_count'] as num?)?.toInt() ?? 0,
      groupRows: (json['group_rows'] as num?)?.toInt() ?? 0,
      fileRows: (json['file_rows'] as num?)?.toInt() ?? 0,
      estimatedPages: (json['estimated_pages'] as num?)?.toInt() ?? 0,
      fingerprint:
          json.containsKey('root_size_bytes') ||
              json.containsKey('scanned_at_ms') ||
              json.containsKey('stats')
          ? CoverageSnapshotFingerprint.fromJson(json)
          : null,
      seedNodeCount: (json['seed_node_count'] as num?)?.toInt(),
      tailFileCount: (json['tail_file_count'] as num?)?.toInt(),
      localSafeFiles: (json['local_safe_files'] as num?)?.toInt(),
      localKeepFiles: (json['local_keep_files'] as num?)?.toInt(),
      tailFiles: (json['tail_files'] as num?)?.toInt(),
      treePendingFiles: (json['tree_pending_files'] as num?)?.toInt(),
      estimatedTreeCredits: (json['estimated_tree_credits'] as num?)?.toInt(),
      estimatedTailCredits: (json['estimated_tail_credits'] as num?)?.toInt(),
    );
  }

  final String snapshotId;
  final int planVersion;
  final String rootPath;
  final int totalUnclassified;
  final int preClassifiedCount;
  final int groupRows;
  final int fileRows;
  final int estimatedPages;
  final CoverageSnapshotFingerprint? fingerprint;
  final int? seedNodeCount;
  final int? tailFileCount;
  final int? localSafeFiles;
  final int? localKeepFiles;
  final int? tailFiles;
  final int? treePendingFiles;
  final int? estimatedTreeCredits;
  final int? estimatedTailCredits;

  bool get isTreePlan => planVersion >= 3 && seedNodeCount != null;
}

class CoverageTreePage {
  const CoverageTreePage({
    required this.snapshotId,
    required this.planVersion,
    required this.nextCursor,
    required this.nodes,
  });

  factory CoverageTreePage.fromJson(Map<String, dynamic> json) =>
      CoverageTreePage(
        snapshotId: json['snapshot_id'] as String,
        planVersion: (json['plan_version'] as num?)?.toInt() ?? 0,
        nextCursor: (json['next_cursor'] as num?)?.toInt(),
        nodes: ((json['nodes'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => CoverageTreeNode.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );

  final String snapshotId;
  final int planVersion;
  final int? nextCursor;
  final List<CoverageTreeNode> nodes;
}

class CoverageTailRow {
  const CoverageTailRow({required this.path, required this.sizeBytes});

  factory CoverageTailRow.fromJson(Map<String, dynamic> json) =>
      CoverageTailRow(
        path: json['path'] as String,
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      );

  final String path;
  final int sizeBytes;
}

class CoverageTailPage {
  const CoverageTailPage({
    required this.snapshotId,
    required this.planVersion,
    required this.nextCursor,
    required this.rows,
  });

  factory CoverageTailPage.fromJson(Map<String, dynamic> json) =>
      CoverageTailPage(
        snapshotId: json['snapshot_id'] as String,
        planVersion: (json['plan_version'] as num?)?.toInt() ?? 0,
        nextCursor: (json['next_cursor'] as num?)?.toInt(),
        rows: ((json['rows'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => CoverageTailRow.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );

  final String snapshotId;
  final int planVersion;
  final int? nextCursor;
  final List<CoverageTailRow> rows;
}

class CoveragePage {
  const CoveragePage({
    required this.snapshotId,
    required this.planVersion,
    required this.nextCursor,
    required this.rows,
  });

  factory CoveragePage.fromJson(Map<String, dynamic> json) => CoveragePage(
    snapshotId: json['snapshot_id'] as String,
    planVersion: (json['plan_version'] as num?)?.toInt() ?? 0,
    nextCursor: (json['next_cursor'] as num?)?.toInt(),
    rows: ((json['rows'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => CoverageRow.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false),
  );

  final String snapshotId;
  final int planVersion;
  final int? nextCursor;
  final List<CoverageRow> rows;
}

class CoverageTreeTopExtension {
  const CoverageTreeTopExtension({
    required this.extension,
    required this.count,
  });

  final String extension;
  final int count;
}

/// Directory node from native tree coverage pages (plan v3).
class CoverageTreeNode {
  const CoverageTreeNode({
    required this.path,
    required this.sizeBytes,
    required this.fileCount,
    required this.subdirCount,
    required this.role,
    this.markers = const [],
    this.prunedFlags = 0,
    this.topExtensions = const [],
  });

  factory CoverageTreeNode.fromJson(Map<String, dynamic> json) {
    final rawExt = json['top_extensions'];
    final topExtensions = rawExt is List
        ? rawExt
              .whereType<List>()
              .map(
                (pair) => CoverageTreeTopExtension(
                  extension: pair.isNotEmpty ? pair[0].toString() : '',
                  count: pair.length > 1 ? (pair[1] as num?)?.toInt() ?? 0 : 0,
                ),
              )
              .toList(growable: false)
        : const <CoverageTreeTopExtension>[];
    return CoverageTreeNode(
      path: json['path'] as String,
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
      subdirCount: (json['subdir_count'] as num?)?.toInt() ?? 0,
      role: json['role'] as String? ?? 'unknown',
      markers: ((json['markers'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      prunedFlags: (json['pruned_flags'] as num?)?.toInt() ?? 0,
      topExtensions: topExtensions,
    );
  }

  final String path;
  final int sizeBytes;
  final int fileCount;
  final int subdirCount;
  final String role;
  final List<String> markers;
  final int prunedFlags;
  final List<CoverageTreeTopExtension> topExtensions;

  Map<String, dynamic> toJson() => {
    'path': path,
    'size_bytes': sizeBytes,
    'file_count': fileCount,
    'subdir_count': subdirCount,
    'role': role,
    'markers': markers,
    'pruned_flags': prunedFlags,
    'top_extensions': topExtensions
        .map((e) => [e.extension, e.count])
        .toList(growable: false),
  };
}

String coverageJsonEncode(Object value) => jsonEncode(value);
