import 'dart:convert';
import 'dart:io';

enum CoverageJobStatus { idle, running, paused, completed, cancelled }

enum CoveragePauseReason { manual, budget, failed, appQuit }

class CoverageJobState {
  const CoverageJobState({
    required this.snapshotId,
    required this.rootPath,
    required this.planVersion,
    required this.cursor,
    required this.totalUnclassified,
    required this.analyzedFiles,
    required this.preClassifiedCount,
    required this.status,
    this.pauseReason,
    required this.usedTokens,
    required this.usedCredits,
    required this.budgetTokens,
    required this.budgetCredits,
    required this.updatedAtMs,
  });

  factory CoverageJobState.fromJson(Map<String, dynamic> json) =>
      CoverageJobState(
        snapshotId: json['snapshot_id'] as String,
        rootPath: json['root_path'] as String,
        planVersion: (json['plan_version'] as num?)?.toInt() ?? 0,
        cursor: (json['cursor'] as num?)?.toInt() ?? 0,
        totalUnclassified: (json['total_unclassified'] as num?)?.toInt() ?? 0,
        analyzedFiles: (json['analyzed_files'] as num?)?.toInt() ?? 0,
        preClassifiedCount:
            (json['pre_classified_count'] as num?)?.toInt() ?? 0,
        status:
            CoverageJobStatus.values.asNameMap()[json['status']] ??
            CoverageJobStatus.idle,
        pauseReason: json['pause_reason'] == null
            ? null
            : CoveragePauseReason.values.asNameMap()[json['pause_reason']],
        usedTokens: (json['used_tokens'] as num?)?.toInt() ?? 0,
        usedCredits: (json['used_credits'] as num?)?.toInt() ?? 0,
        budgetTokens: (json['budget_tokens'] as num?)?.toInt() ?? 0,
        budgetCredits: (json['budget_credits'] as num?)?.toInt() ?? 0,
        updatedAtMs: (json['updated_at_ms'] as num?)?.toInt() ?? 0,
      );

  final String snapshotId;
  final String rootPath;
  final int planVersion;
  final int cursor;
  final int totalUnclassified;
  final int analyzedFiles;
  final int preClassifiedCount;
  final CoverageJobStatus status;
  final CoveragePauseReason? pauseReason;
  final int usedTokens;
  final int usedCredits;
  final int budgetTokens;
  final int budgetCredits;
  final int updatedAtMs;

  CoverageJobState copyWith({
    int? cursor,
    int? analyzedFiles,
    CoverageJobStatus? status,
    CoveragePauseReason? Function()? pauseReason,
    int? usedTokens,
    int? usedCredits,
    int? budgetTokens,
    int? budgetCredits,
    int? updatedAtMs,
  }) => CoverageJobState(
    snapshotId: snapshotId,
    rootPath: rootPath,
    planVersion: planVersion,
    cursor: cursor ?? this.cursor,
    totalUnclassified: totalUnclassified,
    analyzedFiles: analyzedFiles ?? this.analyzedFiles,
    preClassifiedCount: preClassifiedCount,
    status: status ?? this.status,
    pauseReason: pauseReason != null ? pauseReason() : this.pauseReason,
    usedTokens: usedTokens ?? this.usedTokens,
    usedCredits: usedCredits ?? this.usedCredits,
    budgetTokens: budgetTokens ?? this.budgetTokens,
    budgetCredits: budgetCredits ?? this.budgetCredits,
    updatedAtMs: updatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
  );

  Map<String, dynamic> toJson() => {
    'snapshot_id': snapshotId,
    'root_path': rootPath,
    'plan_version': planVersion,
    'cursor': cursor,
    'total_unclassified': totalUnclassified,
    'analyzed_files': analyzedFiles,
    'pre_classified_count': preClassifiedCount,
    'status': status.name,
    if (pauseReason != null) 'pause_reason': pauseReason!.name,
    'used_tokens': usedTokens,
    'used_credits': usedCredits,
    'budget_tokens': budgetTokens,
    'budget_credits': budgetCredits,
    'updated_at_ms': updatedAtMs,
  };
}

class CoverageJobStateStore {
  CoverageJobStateStore(this.directory);

  final Directory directory;

  File _fileFor(String snapshotId) =>
      File('${directory.path}/ai_coverage_job_$snapshotId.json');

  Future<void> save(CoverageJobState state) async {
    await directory.create(recursive: true);
    final file = _fileFor(state.snapshotId);
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temp.writeAsString(jsonEncode(state.toJson()), flush: true);
    await temp.rename(file.path);
  }

  Future<CoverageJobState?> load(String snapshotId) async {
    final file = _fileFor(snapshotId);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return CoverageJobState.fromJson(
        Map<String, dynamic>.from(decoded as Map),
      );
    } catch (_) {
      return null;
    }
  }
}
