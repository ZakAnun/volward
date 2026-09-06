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
  });

  factory CoveragePlanSummary.fromJson(Map<String, dynamic> json) =>
      CoveragePlanSummary(
        snapshotId: json['snapshot_id'] as String,
        planVersion: (json['plan_version'] as num?)?.toInt() ?? 0,
        rootPath: json['root_path'] as String,
        totalUnclassified: (json['total_unclassified'] as num?)?.toInt() ?? 0,
        preClassifiedCount:
            (json['pre_classified_count'] as num?)?.toInt() ?? 0,
        groupRows: (json['group_rows'] as num?)?.toInt() ?? 0,
        fileRows: (json['file_rows'] as num?)?.toInt() ?? 0,
        estimatedPages: (json['estimated_pages'] as num?)?.toInt() ?? 0,
        fingerprint:
            json.containsKey('root_size_bytes') ||
                json.containsKey('scanned_at_ms') ||
                json.containsKey('stats')
            ? CoverageSnapshotFingerprint.fromJson(json)
            : null,
      );

  final String snapshotId;
  final int planVersion;
  final String rootPath;
  final int totalUnclassified;
  final int preClassifiedCount;
  final int groupRows;
  final int fileRows;
  final int estimatedPages;
  final CoverageSnapshotFingerprint? fingerprint;
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

String coverageJsonEncode(Object value) => jsonEncode(value);
