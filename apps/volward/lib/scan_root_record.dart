import 'dart:convert';
import 'dart:io';

import 'scan_tree.dart';

enum ScanRootStatus { empty, scanning, paused, completed }

class ScanRootRecord {
  const ScanRootRecord({
    required this.root,
    required this.status,
    required this.updatedAtMs,
    this.snapshotId = '',
    this.checkpointPath,
    this.jobId,
  });

  factory ScanRootRecord.fromJson(Map<String, dynamic> json) {
    return ScanRootRecord(
      root: json['root'] as String? ?? '',
      status:
          ScanRootStatus.values.asNameMap()[json['status']] ??
          ScanRootStatus.empty,
      snapshotId: json['snapshot_id'] as String? ?? '',
      checkpointPath: json['checkpoint_path'] as String?,
      jobId: json['job_id'] as String?,
      updatedAtMs: (json['updated_at_ms'] as num?)?.toInt() ?? 0,
    );
  }

  final String root;
  final ScanRootStatus status;
  final String snapshotId;
  final String? checkpointPath;
  final String? jobId;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => {
    'root': root,
    'status': status.name,
    'snapshot_id': snapshotId,
    if (checkpointPath != null) 'checkpoint_path': checkpointPath,
    if (jobId != null) 'job_id': jobId,
    'updated_at_ms': updatedAtMs,
  };
}

class ScanRootRecordStore {
  ScanRootRecordStore(this.directory);

  final Directory directory;

  File fileFor(String root) {
    final key = ScanTreeBuilder.normalizeRoot(root).replaceAll('/', '_');
    return File('${directory.path}/root_records/$key.json');
  }

  Future<ScanRootRecord?> load(String root) async {
    final file = fileFor(root);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return ScanRootRecord.fromJson(Map<String, dynamic>.from(decoded as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(ScanRootRecord record) async {
    final normalized = ScanRootRecord(
      root: ScanTreeBuilder.normalizeRoot(record.root),
      status: record.status,
      snapshotId: record.snapshotId,
      checkpointPath: record.checkpointPath,
      jobId: record.jobId,
      updatedAtMs: record.updatedAtMs,
    );
    final file = fileFor(normalized.root);
    await file.parent.create(recursive: true);
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temp.writeAsString(jsonEncode(normalized.toJson()), flush: true);
    await temp.rename(file.path);
  }

  Future<void> clear(String root) async {
    final file = fileFor(root);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static ScanRootStatus inferredStatus({
    required String root,
    required bool isCurrentAndScanning,
    ScanRootRecord? record,
    bool hasCompletedSnapshot = false,
  }) {
    if (isCurrentAndScanning) return ScanRootStatus.scanning;
    if (record != null) return record.status;
    if (hasCompletedSnapshot) return ScanRootStatus.completed;
    return ScanRootStatus.empty;
  }
}
