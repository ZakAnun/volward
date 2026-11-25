import 'dart:convert';
import 'dart:io';

import 'coverage_client_logic.dart';
import 'coverage_models.dart';

enum CoverageJobStatus { idle, running, paused, completed, cancelled }

enum CoveragePauseReason { manual, budget, failed, appQuit }

/// Category persisted when [CoveragePauseReason.failed] (design §4.4).
enum CoveragePauseDetail { parse, network, api }

class CoverageJobStateCorruptException implements Exception {
  CoverageJobStateCorruptException(this.message);

  final String message;

  @override
  String toString() => message;
}

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
    this.fingerprint,
    this.estimatedCreditsRemaining,
    this.pauseDetail,
    this.pauseMessage,
    this.failedBatchPaths = const [],
    this.creditsChargedNoVerdict = 0,
    this.clientLogicVersion = kCoverageClientLogicVersion,
    this.treeQueueCursor = 0,
    this.tailQueueCursor = 0,
    this.localResolvedFiles = 0,
    this.localRuleFiles = 0,
    this.localPlannedFiles,
    this.localFlushCursor = 0,
    this.localPhaseComplete = false,
    this.aiResolvedFiles = 0,
    this.treeNodesCompleted = 0,
    this.estimatedTreeCredits,
    this.estimatedTailCredits,
    this.scopeFingerprint,
    this.reconciliationPending,
    this.reconciliationFailed,
    this.reconciliationCompleted = false,
  });

  factory CoverageJobState.fromJson(
    Map<String, dynamic> json,
  ) => CoverageJobState(
    snapshotId: json['snapshot_id'] as String,
    rootPath: json['root_path'] as String,
    planVersion: (json['plan_version'] as num?)?.toInt() ?? 0,
    cursor: (json['cursor'] as num?)?.toInt() ?? 0,
    totalUnclassified: (json['total_unclassified'] as num?)?.toInt() ?? 0,
    analyzedFiles: (json['analyzed_files'] as num?)?.toInt() ?? 0,
    preClassifiedCount: (json['pre_classified_count'] as num?)?.toInt() ?? 0,
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
    fingerprint: json['fingerprint'] is Map
        ? CoverageSnapshotFingerprint.fromJson(
            Map<String, dynamic>.from(json['fingerprint'] as Map),
          )
        : null,
    estimatedCreditsRemaining: (json['estimated_credits_remaining'] as num?)
        ?.toInt(),
    pauseDetail: json['pause_detail'] == null
        ? null
        : CoveragePauseDetail.values.asNameMap()[json['pause_detail']],
    pauseMessage: json['pause_message'] as String?,
    failedBatchPaths: _readStringList(json['failed_batch_paths']),
    creditsChargedNoVerdict:
        (json['credits_charged_no_verdict'] as num?)?.toInt() ?? 0,
    clientLogicVersion: (json['client_logic_version'] as num?)?.toInt() ?? 1,
    treeQueueCursor: (json['tree_queue_cursor'] as num?)?.toInt() ?? 0,
    tailQueueCursor: (json['tail_queue_cursor'] as num?)?.toInt() ?? 0,
    localResolvedFiles: (json['local_resolved_files'] as num?)?.toInt() ?? 0,
    localRuleFiles: (json['local_rule_files'] as num?)?.toInt() ?? 0,
    localPlannedFiles: (json['local_planned_files'] as num?)?.toInt(),
    localFlushCursor: (json['local_flush_cursor'] as num?)?.toInt() ?? 0,
    localPhaseComplete: json['local_phase_complete'] == true,
    aiResolvedFiles: (json['ai_resolved_files'] as num?)?.toInt() ?? 0,
    treeNodesCompleted: (json['tree_nodes_completed'] as num?)?.toInt() ?? 0,
    estimatedTreeCredits: (json['estimated_tree_credits'] as num?)?.toInt(),
    estimatedTailCredits: (json['estimated_tail_credits'] as num?)?.toInt(),
    scopeFingerprint: json['scope_fingerprint'] as String?,
    reconciliationPending: (json['reconciliation_pending'] as num?)?.toInt(),
    reconciliationFailed: (json['reconciliation_failed'] as num?)?.toInt(),
    reconciliationCompleted: json['reconciliation_completed'] == true,
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
  final CoverageSnapshotFingerprint? fingerprint;
  final int? estimatedCreditsRemaining;
  final CoveragePauseDetail? pauseDetail;
  final String? pauseMessage;
  final List<String> failedBatchPaths;
  final int creditsChargedNoVerdict;
  final int clientLogicVersion;
  final int treeQueueCursor;
  final int tailQueueCursor;
  final int localResolvedFiles;
  final int localRuleFiles;
  final int? localPlannedFiles;
  final int localFlushCursor;
  final bool localPhaseComplete;
  final int aiResolvedFiles;
  final int treeNodesCompleted;
  final int? estimatedTreeCredits;
  final int? estimatedTailCredits;
  final String? scopeFingerprint;
  final int? reconciliationPending;
  final int? reconciliationFailed;
  final bool reconciliationCompleted;

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
    CoverageSnapshotFingerprint? fingerprint,
    int? Function()? estimatedCreditsRemaining,
    CoveragePauseDetail? Function()? pauseDetail,
    String? Function()? pauseMessage,
    List<String>? failedBatchPaths,
    int? creditsChargedNoVerdict,
    int? clientLogicVersion,
    int? treeQueueCursor,
    int? tailQueueCursor,
    int? localResolvedFiles,
    int? localRuleFiles,
    int? Function()? localPlannedFiles,
    int? localFlushCursor,
    bool? localPhaseComplete,
    int? aiResolvedFiles,
    int? treeNodesCompleted,
    int? Function()? estimatedTreeCredits,
    int? Function()? estimatedTailCredits,
    String? scopeFingerprint,
    int? reconciliationPending,
    int? reconciliationFailed,
    bool? reconciliationCompleted,
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
    fingerprint: fingerprint ?? this.fingerprint,
    estimatedCreditsRemaining: estimatedCreditsRemaining != null
        ? estimatedCreditsRemaining()
        : this.estimatedCreditsRemaining,
    pauseDetail: pauseDetail != null ? pauseDetail() : this.pauseDetail,
    pauseMessage: pauseMessage != null ? pauseMessage() : this.pauseMessage,
    failedBatchPaths: failedBatchPaths ?? this.failedBatchPaths,
    creditsChargedNoVerdict:
        creditsChargedNoVerdict ?? this.creditsChargedNoVerdict,
    clientLogicVersion: clientLogicVersion ?? this.clientLogicVersion,
    treeQueueCursor: treeQueueCursor ?? this.treeQueueCursor,
    tailQueueCursor: tailQueueCursor ?? this.tailQueueCursor,
    localResolvedFiles: localResolvedFiles ?? this.localResolvedFiles,
    localRuleFiles: localRuleFiles ?? this.localRuleFiles,
    localPlannedFiles: localPlannedFiles != null
        ? localPlannedFiles()
        : this.localPlannedFiles,
    localFlushCursor: localFlushCursor ?? this.localFlushCursor,
    localPhaseComplete: localPhaseComplete ?? this.localPhaseComplete,
    aiResolvedFiles: aiResolvedFiles ?? this.aiResolvedFiles,
    treeNodesCompleted: treeNodesCompleted ?? this.treeNodesCompleted,
    estimatedTreeCredits: estimatedTreeCredits != null
        ? estimatedTreeCredits()
        : this.estimatedTreeCredits,
    estimatedTailCredits: estimatedTailCredits != null
        ? estimatedTailCredits()
        : this.estimatedTailCredits,
    scopeFingerprint: scopeFingerprint ?? this.scopeFingerprint,
    reconciliationPending: reconciliationPending ?? this.reconciliationPending,
    reconciliationFailed: reconciliationFailed ?? this.reconciliationFailed,
    reconciliationCompleted:
        reconciliationCompleted ?? this.reconciliationCompleted,
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
    if (fingerprint != null) 'fingerprint': fingerprint!.toJson(),
    if (estimatedCreditsRemaining != null)
      'estimated_credits_remaining': estimatedCreditsRemaining,
    if (pauseDetail != null) 'pause_detail': pauseDetail!.name,
    if (pauseMessage != null && pauseMessage!.isNotEmpty)
      'pause_message': pauseMessage,
    if (failedBatchPaths.isNotEmpty) 'failed_batch_paths': failedBatchPaths,
    if (creditsChargedNoVerdict > 0)
      'credits_charged_no_verdict': creditsChargedNoVerdict,
    'client_logic_version': clientLogicVersion,
    if (treeQueueCursor != 0) 'tree_queue_cursor': treeQueueCursor,
    if (tailQueueCursor != 0) 'tail_queue_cursor': tailQueueCursor,
    if (localResolvedFiles != 0) 'local_resolved_files': localResolvedFiles,
    if (localRuleFiles != 0) 'local_rule_files': localRuleFiles,
    if (localPlannedFiles != null) 'local_planned_files': localPlannedFiles,
    if (localFlushCursor != 0) 'local_flush_cursor': localFlushCursor,
    if (localPhaseComplete) 'local_phase_complete': true,
    if (aiResolvedFiles != 0) 'ai_resolved_files': aiResolvedFiles,
    if (treeNodesCompleted != 0) 'tree_nodes_completed': treeNodesCompleted,
    if (estimatedTreeCredits != null)
      'estimated_tree_credits': estimatedTreeCredits,
    if (estimatedTailCredits != null)
      'estimated_tail_credits': estimatedTailCredits,
    if (scopeFingerprint != null) 'scope_fingerprint': scopeFingerprint,
    if (reconciliationPending != null)
      'reconciliation_pending': reconciliationPending,
    if (reconciliationFailed != null)
      'reconciliation_failed': reconciliationFailed,
    if (reconciliationCompleted) 'reconciliation_completed': true,
  };
}

List<String> _readStringList(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<String>().toList(growable: false);
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
    final result = await loadResult(snapshotId);
    if (result.error != null) {
      throw CoverageJobStateCorruptException(result.error!);
    }
    return result.state;
  }

  Future<({CoverageJobState? state, String? error})> loadResult(
    String snapshotId,
  ) async {
    final file = _fileFor(snapshotId);
    if (!await file.exists()) return (state: null, error: null);
    try {
      final decoded = jsonDecode(await file.readAsString());
      return (
        state: CoverageJobState.fromJson(
          Map<String, dynamic>.from(decoded as Map),
        ),
        error: null,
      );
    } catch (error) {
      return (state: null, error: 'coverage checkpoint is corrupt: $error');
    }
  }
}
