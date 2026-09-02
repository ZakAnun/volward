String? _optionalString(Object? value) {
  if (value == null) return null;
  final string = value.toString();
  return string.isEmpty ? null : string;
}

int? _optionalInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

class AiVerdict {
  final String path;
  final String verdict;
  final String confidence;
  final String reason;
  final String? cleanupSource;
  final String? cleanupHint;
  final int? retentionDays;
  const AiVerdict({
    required this.path,
    required this.verdict,
    required this.confidence,
    required this.reason,
    this.cleanupSource,
    this.cleanupHint,
    this.retentionDays,
  });
  factory AiVerdict.fromJson(Map<String, dynamic> j) => AiVerdict(
    path: j['path'] as String,
    verdict: j['verdict'] as String,
    confidence: j['confidence'] as String,
    reason: j['reason'] as String,
    cleanupSource: _optionalString(j['cleanup_source']),
    cleanupHint: _optionalString(j['cleanup_hint']),
    retentionDays: _optionalInt(j['retention_days']),
  );
}

class AiCandidate {
  final String path;
  final int sizeBytes;
  final bool isDir;
  final int? childCount;
  final String? extension;
  final String? cleanupSource;
  final String? cleanupHint;
  final int? retentionDays;

  /// Files folded into this candidate by the native aggregator. When non-empty,
  /// `path` is only the shared parent directory and must never be deleted —
  /// delete these member files instead.
  final List<String> memberPaths;

  /// Opaque native target resolved to all aggregate members at deletion time.
  final String? deleteTarget;

  const AiCandidate({
    required this.path,
    required this.sizeBytes,
    required this.isDir,
    this.childCount,
    this.extension,
    this.cleanupSource,
    this.cleanupHint,
    this.retentionDays,
    this.memberPaths = const [],
    this.deleteTarget,
  });
  factory AiCandidate.fromJson(Map<String, dynamic> j) {
    final raw = j['member_paths'];
    final memberPaths = raw is List
        ? raw.whereType<String>().toList(growable: false)
        : const <String>[];
    return AiCandidate(
      path: j['path'] as String,
      sizeBytes: j['size_bytes'] as int,
      isDir: j['is_dir'] as bool? ?? false,
      childCount: j['child_count'] as int?,
      extension: j['extension'] as String?,
      cleanupSource: _optionalString(j['cleanup_source']),
      cleanupHint: _optionalString(j['cleanup_hint']),
      retentionDays: _optionalInt(j['retention_days']),
      memberPaths: memberPaths,
      deleteTarget: j['delete_target'] as String?,
    );
  }
  Map<String, dynamic> toJson() => {
    'path': path,
    'size_bytes': sizeBytes,
    'is_dir': isDir,
    if (childCount != null) 'child_count': childCount,
    if (extension != null) 'extension': extension,
    if (cleanupSource != null && cleanupSource!.isNotEmpty)
      'cleanup_source': cleanupSource,
    if (cleanupHint != null && cleanupHint!.isNotEmpty)
      'cleanup_hint': cleanupHint,
    if (retentionDays != null) 'retention_days': retentionDays,
    if (memberPaths.isNotEmpty) 'member_paths': memberPaths,
    if (deleteTarget != null && deleteTarget!.isNotEmpty)
      'delete_target': deleteTarget,
  };
}

class AiQuotaInfo {
  final int creditsRemaining;
  final int creditsTotal;
  const AiQuotaInfo({
    required this.creditsRemaining,
    required this.creditsTotal,
  });
}

abstract interface class AiProvider {
  Future<List<AiVerdict>> analyze(List<AiCandidate> candidates);
  Future<AiQuotaInfo?> queryQuota();
}
