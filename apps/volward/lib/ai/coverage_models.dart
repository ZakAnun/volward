import 'dart:convert';

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
  });

  factory CoverageRow.fromJson(Map<String, dynamic> json) => CoverageRow(
    rowIndex: (json['row_index'] as num?)?.toInt() ?? 0,
    kind: CoverageRowKind.fromWire(json['kind']),
    path: json['path'] as String,
    sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    memberCount: (json['member_count'] as num?)?.toInt(),
  );

  final int rowIndex;
  final CoverageRowKind kind;
  final String path;
  final int sizeBytes;
  final int? memberCount;

  int get memberFiles => memberCount ?? 1;

  Map<String, dynamic> toJson() => {
    'row_index': rowIndex,
    'kind': kind.name,
    'path': path,
    'size_bytes': sizeBytes,
    if (memberCount != null) 'member_count': memberCount,
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
      );

  final String snapshotId;
  final int planVersion;
  final String rootPath;
  final int totalUnclassified;
  final int preClassifiedCount;
  final int groupRows;
  final int fileRows;
  final int estimatedPages;
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
