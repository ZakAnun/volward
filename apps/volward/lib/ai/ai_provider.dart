class AiVerdict {
  final String path;
  final String verdict;
  final String confidence;
  final String reason;
  const AiVerdict({
    required this.path,
    required this.verdict,
    required this.confidence,
    required this.reason,
  });
  factory AiVerdict.fromJson(Map<String, dynamic> j) => AiVerdict(
    path: j['path'] as String,
    verdict: j['verdict'] as String,
    confidence: j['confidence'] as String,
    reason: j['reason'] as String,
  );
}

class AiCandidate {
  final String path;
  final int sizeBytes;
  final bool isDir;
  final int? childCount;
  final String? extension;

  /// Files folded into this candidate by the native aggregator. When non-empty,
  /// `path` is only the shared parent directory and must never be deleted —
  /// delete these member files instead.
  final List<String> memberPaths;

  /// Complete concrete paths used for deletion. This remains separate from
  /// the bounded model/UI member list.
  final List<String> deleteMemberPaths;

  const AiCandidate({
    required this.path,
    required this.sizeBytes,
    required this.isDir,
    this.childCount,
    this.extension,
    this.memberPaths = const [],
    this.deleteMemberPaths = const [],
  });
  factory AiCandidate.fromJson(Map<String, dynamic> j) {
    final raw = j['member_paths'];
    final rawDelete = j['delete_member_paths'];
    final memberPaths = raw is List
        ? raw.whereType<String>().toList(growable: false)
        : const <String>[];
    return AiCandidate(
      path: j['path'] as String,
      sizeBytes: j['size_bytes'] as int,
      isDir: j['is_dir'] as bool? ?? false,
      childCount: j['child_count'] as int?,
      extension: j['extension'] as String?,
      memberPaths: memberPaths,
      deleteMemberPaths: rawDelete is List
          ? rawDelete.whereType<String>().toList(growable: false)
          : memberPaths,
    );
  }
  Map<String, dynamic> toJson() => {
    'path': path,
    'size_bytes': sizeBytes,
    'is_dir': isDir,
    if (childCount != null) 'child_count': childCount,
    if (extension != null) 'extension': extension,
    if (memberPaths.isNotEmpty) 'member_paths': memberPaths,
    if (deleteMemberPaths.isNotEmpty) 'delete_member_paths': deleteMemberPaths,
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
