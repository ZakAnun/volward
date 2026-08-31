const int capabilitySchemaVersion = 1;
const int defaultCapabilityPageSize = 100;
const int maxCapabilityPageSize = 500;
const Object _unset = Object();

enum Capability {
  largeFiles,
  cleanupCandidates,
  duplicateFiles,
  similarPhotos,
  applications,
  browserPrivacy,
  spaceAnalysis,
}

enum CapabilityLevel { fullPath, appStatsOnly, guidedOnly }

enum LargeFileThresholdPreset { mb50, mb100, gb1, gb5 }

enum AgePreset { days7, days30, days90 }

enum SimilarityPreset { strict, balanced, loose }

enum Recommendation { safeToRemove, reviewNeeded, keep, unknown }

enum AnalysisConfidence { low, medium, high }

enum CapabilityAnalysisPhase {
  preparing,
  indexing,
  inspecting,
  hashing,
  grouping,
  buildingResult,
  completed,
}

extension CapabilityWire on Capability {
  String get wireValue => switch (this) {
    Capability.largeFiles => 'large_files',
    Capability.cleanupCandidates => 'cleanup_candidates',
    Capability.duplicateFiles => 'duplicate_files',
    Capability.similarPhotos => 'similar_photos',
    Capability.applications => 'applications',
    Capability.browserPrivacy => 'browser_privacy',
    Capability.spaceAnalysis => 'space_analysis',
  };
}

extension CapabilityLevelWire on CapabilityLevel {
  String get wireValue => switch (this) {
    CapabilityLevel.fullPath => 'full_path',
    CapabilityLevel.appStatsOnly => 'app_stats_only',
    CapabilityLevel.guidedOnly => 'guided_only',
  };
}

extension LargeFileThresholdPresetWire on LargeFileThresholdPreset {
  String get wireValue => switch (this) {
    LargeFileThresholdPreset.mb50 => '50_mb',
    LargeFileThresholdPreset.mb100 => '100_mb',
    LargeFileThresholdPreset.gb1 => '1_gb',
    LargeFileThresholdPreset.gb5 => '5_gb',
  };

  int get thresholdBytes => switch (this) {
    LargeFileThresholdPreset.mb50 => 50000000,
    LargeFileThresholdPreset.mb100 => 100000000,
    LargeFileThresholdPreset.gb1 => 1000000000,
    LargeFileThresholdPreset.gb5 => 5000000000,
  };
}

extension AgePresetWire on AgePreset {
  String get wireValue => switch (this) {
    AgePreset.days7 => '7_days',
    AgePreset.days30 => '30_days',
    AgePreset.days90 => '90_days',
  };
}

extension SimilarityPresetWire on SimilarityPreset {
  String get wireValue => switch (this) {
    SimilarityPreset.strict => 'strict',
    SimilarityPreset.balanced => 'balanced',
    SimilarityPreset.loose => 'loose',
  };
}

extension RecommendationWire on Recommendation {
  String get wireValue => switch (this) {
    Recommendation.safeToRemove => 'safe_to_remove',
    Recommendation.reviewNeeded => 'review_needed',
    Recommendation.keep => 'keep',
    Recommendation.unknown => 'unknown',
  };
}

extension AnalysisConfidenceWire on AnalysisConfidence {
  String get wireValue => switch (this) {
    AnalysisConfidence.low => 'low',
    AnalysisConfidence.medium => 'medium',
    AnalysisConfidence.high => 'high',
  };
}

extension CapabilityAnalysisPhaseWire on CapabilityAnalysisPhase {
  String get wireValue => switch (this) {
    CapabilityAnalysisPhase.preparing => 'preparing',
    CapabilityAnalysisPhase.indexing => 'indexing',
    CapabilityAnalysisPhase.inspecting => 'inspecting',
    CapabilityAnalysisPhase.hashing => 'hashing',
    CapabilityAnalysisPhase.grouping => 'grouping',
    CapabilityAnalysisPhase.buildingResult => 'building_result',
    CapabilityAnalysisPhase.completed => 'completed',
  };
}

class AnalysisOptions {
  const AnalysisOptions({
    required this.rootPath,
    this.largeFileThresholdBytes = 50000000,
    this.largeFileThresholdPreset = LargeFileThresholdPreset.mb50,
    this.agePreset = AgePreset.days30,
    this.similarityPreset = SimilarityPreset.balanced,
    this.pageSize = defaultCapabilityPageSize,
    this.cursor,
  });

  final String rootPath;
  final int largeFileThresholdBytes;
  final LargeFileThresholdPreset largeFileThresholdPreset;
  final AgePreset agePreset;
  final SimilarityPreset similarityPreset;
  final int pageSize;
  final String? cursor;

  factory AnalysisOptions.fromJson(
    Map<String, dynamic> json, {
    required Capability capability,
  }) {
    final capabilityContext = capability.wireValue;
    final preset = _largeFileThresholdPreset(
      _string(
        json['large_file_threshold_preset'],
        capabilityContext,
        'large_file_threshold_preset',
      ),
      capabilityContext,
      'large_file_threshold_preset',
    );
    final options = AnalysisOptions(
      rootPath: _string(json['root_path'], capabilityContext, 'root_path'),
      largeFileThresholdBytes: _int(
        json['large_file_threshold_bytes'],
        capabilityContext,
        'large_file_threshold_bytes',
      ),
      largeFileThresholdPreset: preset,
      agePreset: _agePreset(
        _string(json['age_preset'], capabilityContext, 'age_preset'),
        capabilityContext,
        'age_preset',
      ),
      similarityPreset: _similarityPreset(
        _string(
          json['similarity_preset'],
          capabilityContext,
          'similarity_preset',
        ),
        capabilityContext,
        'similarity_preset',
      ),
      pageSize: _int(json['page_size'], capabilityContext, 'page_size'),
      cursor: _optionalString(json['cursor'], capabilityContext, 'cursor'),
    );
    options._validate(capabilityContext);
    return options;
  }

  AnalysisOptions copyWith({
    String? rootPath,
    int? largeFileThresholdBytes,
    LargeFileThresholdPreset? largeFileThresholdPreset,
    AgePreset? agePreset,
    SimilarityPreset? similarityPreset,
    int? pageSize,
    Object? cursor = _unset,
  }) => AnalysisOptions(
    rootPath: rootPath ?? this.rootPath,
    largeFileThresholdBytes:
        largeFileThresholdBytes ?? this.largeFileThresholdBytes,
    largeFileThresholdPreset:
        largeFileThresholdPreset ?? this.largeFileThresholdPreset,
    agePreset: agePreset ?? this.agePreset,
    similarityPreset: similarityPreset ?? this.similarityPreset,
    pageSize: pageSize ?? this.pageSize,
    cursor: identical(cursor, _unset) ? this.cursor : cursor as String?,
  );

  Map<String, dynamic> toJson() => {
    'root_path': rootPath,
    'large_file_threshold_bytes': largeFileThresholdBytes,
    'large_file_threshold_preset': largeFileThresholdPreset.wireValue,
    'age_preset': agePreset.wireValue,
    'similarity_preset': similarityPreset.wireValue,
    'page_size': pageSize,
    'cursor': cursor,
  };

  void _validate(String capability) {
    if (pageSize < 1 || pageSize > maxCapabilityPageSize) {
      _malformed(capability, 'page_size');
    }
    if (largeFileThresholdBytes != largeFileThresholdPreset.thresholdBytes) {
      _malformed(capability, 'large_file_threshold_bytes');
    }
  }
}

class CapabilityAnalysisResult {
  const CapabilityAnalysisResult({
    required this.schemaVersion,
    required this.capability,
    required this.snapshotId,
    required this.rootPath,
    required this.analyzerVersion,
    required this.generatedAtMs,
    required this.capabilityLevel,
    required this.summary,
    required this.groups,
    required this.nextCursor,
    required this.deletionPlan,
    required this.warnings,
  });

  final int schemaVersion;
  final Capability capability;
  final String snapshotId;
  final String rootPath;
  final String analyzerVersion;
  final int generatedAtMs;
  final CapabilityLevel capabilityLevel;
  final AnalysisSummary summary;
  final List<AnalysisGroup> groups;
  final String? nextCursor;
  final DeletionPlan deletionPlan;
  final List<String> warnings;

  factory CapabilityAnalysisResult.fromJson(Map<String, dynamic> json) {
    const unknownCapability = 'unknown';
    final capabilityValue = _string(
      json['capability'],
      unknownCapability,
      'capability',
    );
    final capability = _capability(
      capabilityValue,
      unknownCapability,
      'capability',
    );
    final capabilityContext = capability.wireValue;
    return CapabilityAnalysisResult(
      schemaVersion: _int(
        json['schema_version'],
        capabilityContext,
        'schema_version',
      ),
      capability: capability,
      snapshotId: _string(
        json['snapshot_id'],
        capabilityContext,
        'snapshot_id',
      ),
      rootPath: _string(json['root_path'], capabilityContext, 'root_path'),
      analyzerVersion: _string(
        json['analyzer_version'],
        capabilityContext,
        'analyzer_version',
      ),
      generatedAtMs: _int(
        json['generated_at_ms'],
        capabilityContext,
        'generated_at_ms',
      ),
      capabilityLevel: _capabilityLevel(
        _string(
          json['capability_level'],
          capabilityContext,
          'capability_level',
        ),
        capabilityContext,
        'capability_level',
      ),
      summary: AnalysisSummary.fromJson(
        _json(json['summary'], capabilityContext, 'summary'),
        capability: capabilityContext,
        fieldPrefix: 'summary',
      ),
      groups: _list(json['groups'], capabilityContext, 'groups')
          .asMap()
          .entries
          .map(
            (entry) => AnalysisGroup.fromJson(
              _json(entry.value, capabilityContext, 'groups[${entry.key}]'),
              capability: capabilityContext,
              fieldPrefix: 'groups[${entry.key}]',
            ),
          )
          .toList(growable: false),
      nextCursor: _optionalString(
        json['next_cursor'],
        capabilityContext,
        'next_cursor',
      ),
      deletionPlan: DeletionPlan.fromJson(
        _json(json['deletion_plan'], capabilityContext, 'deletion_plan'),
        capability: capabilityContext,
        fieldPrefix: 'deletion_plan',
      ),
      warnings: _strings(json['warnings'], capabilityContext, 'warnings'),
    );
  }

  CapabilityAnalysisResult copyWith({
    AnalysisSummary? summary,
    List<AnalysisGroup>? groups,
    Object? nextCursor = _unset,
    DeletionPlan? deletionPlan,
    List<String>? warnings,
  }) => CapabilityAnalysisResult(
    schemaVersion: schemaVersion,
    capability: capability,
    snapshotId: snapshotId,
    rootPath: rootPath,
    analyzerVersion: analyzerVersion,
    generatedAtMs: generatedAtMs,
    capabilityLevel: capabilityLevel,
    summary: summary ?? this.summary,
    groups: groups ?? this.groups,
    nextCursor: identical(nextCursor, _unset)
        ? this.nextCursor
        : nextCursor as String?,
    deletionPlan: deletionPlan ?? this.deletionPlan,
    warnings: warnings ?? this.warnings,
  );

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'capability': capability.wireValue,
    'snapshot_id': snapshotId,
    'root_path': rootPath,
    'analyzer_version': analyzerVersion,
    'generated_at_ms': generatedAtMs,
    'capability_level': capabilityLevel.wireValue,
    'summary': summary.toJson(),
    'groups': groups.map((group) => group.toJson()).toList(growable: false),
    'next_cursor': nextCursor,
    'deletion_plan': deletionPlan.toJson(),
    'warnings': warnings,
  };
}

class AnalysisSummary {
  const AnalysisSummary({
    required this.itemCount,
    required this.totalBytes,
    required this.safeCount,
    required this.reviewCount,
    required this.keptCount,
    required this.truncated,
  });

  final int itemCount;
  final int totalBytes;
  final int safeCount;
  final int reviewCount;
  final int keptCount;
  final bool truncated;

  factory AnalysisSummary.fromJson(
    Map<String, dynamic> json, {
    required String capability,
    required String fieldPrefix,
  }) => AnalysisSummary(
    itemCount: _int(json['item_count'], capability, '$fieldPrefix.item_count'),
    totalBytes: _int(
      json['total_bytes'],
      capability,
      '$fieldPrefix.total_bytes',
    ),
    safeCount: _int(json['safe_count'], capability, '$fieldPrefix.safe_count'),
    reviewCount: _int(
      json['review_count'],
      capability,
      '$fieldPrefix.review_count',
    ),
    keptCount: _int(json['kept_count'], capability, '$fieldPrefix.kept_count'),
    truncated: _bool(json['truncated'], capability, '$fieldPrefix.truncated'),
  );

  Map<String, dynamic> toJson() => {
    'item_count': itemCount,
    'total_bytes': totalBytes,
    'safe_count': safeCount,
    'review_count': reviewCount,
    'kept_count': keptCount,
    'truncated': truncated,
  };
}

class AnalysisGroup {
  const AnalysisGroup({
    required this.groupId,
    required this.groupPath,
    required this.title,
    required this.itemCount,
    required this.totalBytes,
    required this.safeCount,
    required this.reviewCount,
    required this.keptCount,
    required this.defaultExpanded,
    required this.items,
  });

  final String groupId;
  final String groupPath;
  final String title;
  final int itemCount;
  final int totalBytes;
  final int safeCount;
  final int reviewCount;
  final int keptCount;
  final bool defaultExpanded;
  final List<AnalysisItem> items;

  factory AnalysisGroup.fromJson(
    Map<String, dynamic> json, {
    required String capability,
    required String fieldPrefix,
  }) => AnalysisGroup(
    groupId: _string(json['group_id'], capability, '$fieldPrefix.group_id'),
    groupPath: _string(
      json['group_path'],
      capability,
      '$fieldPrefix.group_path',
    ),
    title: _string(json['title'], capability, '$fieldPrefix.title'),
    itemCount: _int(json['item_count'], capability, '$fieldPrefix.item_count'),
    totalBytes: _int(
      json['total_bytes'],
      capability,
      '$fieldPrefix.total_bytes',
    ),
    safeCount: _int(json['safe_count'], capability, '$fieldPrefix.safe_count'),
    reviewCount: _int(
      json['review_count'],
      capability,
      '$fieldPrefix.review_count',
    ),
    keptCount: _int(json['kept_count'], capability, '$fieldPrefix.kept_count'),
    defaultExpanded: _bool(
      json['default_expanded'],
      capability,
      '$fieldPrefix.default_expanded',
    ),
    items: _list(json['items'], capability, '$fieldPrefix.items')
        .asMap()
        .entries
        .map(
          (entry) => AnalysisItem.fromJson(
            _json(entry.value, capability, '$fieldPrefix.items[${entry.key}]'),
            capability: capability,
            fieldPrefix: '$fieldPrefix.items[${entry.key}]',
          ),
        )
        .toList(growable: false),
  );

  AnalysisGroup copyWith({List<AnalysisItem>? items, bool? defaultExpanded}) =>
      AnalysisGroup(
        groupId: groupId,
        groupPath: groupPath,
        title: title,
        itemCount: itemCount,
        totalBytes: totalBytes,
        safeCount: safeCount,
        reviewCount: reviewCount,
        keptCount: keptCount,
        defaultExpanded: defaultExpanded ?? this.defaultExpanded,
        items: items ?? this.items,
      );

  Map<String, dynamic> toJson() => {
    'group_id': groupId,
    'group_path': groupPath,
    'title': title,
    'item_count': itemCount,
    'total_bytes': totalBytes,
    'safe_count': safeCount,
    'review_count': reviewCount,
    'kept_count': keptCount,
    'default_expanded': defaultExpanded,
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };
}

class AnalysisItem {
  const AnalysisItem({
    required this.id,
    required this.path,
    required this.displayName,
    required this.sizeBytes,
    required this.isDirectory,
    required this.modifiedAtMs,
    required this.recommendation,
    required this.recommendationValue,
    required this.confidence,
    required this.reason,
    required this.evidence,
    required this.deleteTarget,
    required this.preview,
  });

  final String id;
  final String path;
  final String displayName;
  final int sizeBytes;
  final bool isDirectory;
  final int? modifiedAtMs;
  final Recommendation recommendation;
  final String recommendationValue;
  final AnalysisConfidence confidence;
  final String reason;
  final List<String> evidence;
  final String? deleteTarget;
  final AnalysisPreview? preview;

  factory AnalysisItem.fromJson(
    Map<String, dynamic> json, {
    required String capability,
    required String fieldPrefix,
  }) {
    final recommendationValue = _string(
      json['recommendation'],
      capability,
      '$fieldPrefix.recommendation',
    );
    return AnalysisItem(
      id: _string(json['id'], capability, '$fieldPrefix.id'),
      path: _string(json['path'], capability, '$fieldPrefix.path'),
      displayName: _string(
        json['display_name'],
        capability,
        '$fieldPrefix.display_name',
      ),
      sizeBytes: _int(
        json['size_bytes'],
        capability,
        '$fieldPrefix.size_bytes',
      ),
      isDirectory: _bool(
        json['is_directory'],
        capability,
        '$fieldPrefix.is_directory',
      ),
      modifiedAtMs: _optionalInt(
        json['modified_at_ms'],
        capability,
        '$fieldPrefix.modified_at_ms',
      ),
      recommendation: _recommendation(recommendationValue),
      recommendationValue: recommendationValue,
      confidence: _analysisConfidence(
        _string(json['confidence'], capability, '$fieldPrefix.confidence'),
        capability,
        '$fieldPrefix.confidence',
      ),
      reason: _string(json['reason'], capability, '$fieldPrefix.reason'),
      evidence: _strings(json['evidence'], capability, '$fieldPrefix.evidence'),
      deleteTarget: _optionalString(
        json['delete_target'],
        capability,
        '$fieldPrefix.delete_target',
      ),
      preview: json['preview'] == null
          ? null
          : AnalysisPreview.fromJson(
              _json(json['preview'], capability, '$fieldPrefix.preview'),
              capability: capability,
              fieldPrefix: '$fieldPrefix.preview',
            ),
    );
  }

  AnalysisItem copyWith({
    String? displayName,
    Object? modifiedAtMs = _unset,
    String? recommendationValue,
    AnalysisConfidence? confidence,
    String? reason,
    List<String>? evidence,
    Object? deleteTarget = _unset,
    Object? preview = _unset,
  }) {
    final updatedRecommendationValue =
        recommendationValue ?? this.recommendationValue;
    return AnalysisItem(
      id: id,
      path: path,
      displayName: displayName ?? this.displayName,
      sizeBytes: sizeBytes,
      isDirectory: isDirectory,
      modifiedAtMs: identical(modifiedAtMs, _unset)
          ? this.modifiedAtMs
          : modifiedAtMs as int?,
      recommendation: _recommendation(updatedRecommendationValue),
      recommendationValue: updatedRecommendationValue,
      confidence: confidence ?? this.confidence,
      reason: reason ?? this.reason,
      evidence: evidence ?? this.evidence,
      deleteTarget: identical(deleteTarget, _unset)
          ? this.deleteTarget
          : deleteTarget as String?,
      preview: identical(preview, _unset)
          ? this.preview
          : preview as AnalysisPreview?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'display_name': displayName,
    'size_bytes': sizeBytes,
    'is_directory': isDirectory,
    'modified_at_ms': modifiedAtMs,
    'recommendation': recommendationValue,
    'confidence': confidence.wireValue,
    'reason': reason,
    'evidence': evidence,
    'delete_target': deleteTarget,
    'preview': preview?.toJson(),
  };
}

class AnalysisPreview {
  const AnalysisPreview({required this.kind, required this.locatable});

  final String kind;
  final bool locatable;

  factory AnalysisPreview.fromJson(
    Map<String, dynamic> json, {
    required String capability,
    required String fieldPrefix,
  }) => AnalysisPreview(
    kind: _string(json['kind'], capability, '$fieldPrefix.kind'),
    locatable: _bool(json['locatable'], capability, '$fieldPrefix.locatable'),
  );

  Map<String, dynamic> toJson() => {'kind': kind, 'locatable': locatable};
}

class DeletionPlan {
  const DeletionPlan({
    required this.snapshotId,
    required this.targetCount,
    required this.targetBytes,
    required this.targets,
    required this.blockedTargets,
    required this.requiresConfirmation,
  });

  final String snapshotId;
  final int targetCount;
  final int targetBytes;
  final List<String> targets;
  final List<String> blockedTargets;
  final bool requiresConfirmation;

  factory DeletionPlan.fromJson(
    Map<String, dynamic> json, {
    required String capability,
    required String fieldPrefix,
  }) {
    final requiresConfirmation = _bool(
      json['requires_confirmation'],
      capability,
      '$fieldPrefix.requires_confirmation',
    );
    if (!requiresConfirmation) {
      _malformed(capability, '$fieldPrefix.requires_confirmation');
    }

    return DeletionPlan(
      snapshotId: _string(
        json['snapshot_id'],
        capability,
        '$fieldPrefix.snapshot_id',
      ),
      targetCount: _int(
        json['target_count'],
        capability,
        '$fieldPrefix.target_count',
      ),
      targetBytes: _int(
        json['target_bytes'],
        capability,
        '$fieldPrefix.target_bytes',
      ),
      targets: _strings(json['targets'], capability, '$fieldPrefix.targets'),
      blockedTargets: _strings(
        json['blocked_targets'],
        capability,
        '$fieldPrefix.blocked_targets',
      ),
      requiresConfirmation: true,
    );
  }

  DeletionPlan copyWith({
    List<String>? targets,
    List<String>? blockedTargets,
  }) => DeletionPlan(
    snapshotId: snapshotId,
    targetCount: targetCount,
    targetBytes: targetBytes,
    targets: targets ?? this.targets,
    blockedTargets: blockedTargets ?? this.blockedTargets,
    requiresConfirmation: requiresConfirmation,
  );

  Map<String, dynamic> toJson() => {
    'snapshot_id': snapshotId,
    'target_count': targetCount,
    'target_bytes': targetBytes,
    'targets': targets,
    'blocked_targets': blockedTargets,
    'requires_confirmation': requiresConfirmation,
  };
}

class CapabilityAnalysisProgress {
  const CapabilityAnalysisProgress({
    required this.jobId,
    required this.snapshotId,
    required this.capability,
    required this.phase,
    required this.processed,
    required this.total,
    required this.currentPath,
    required this.cancelled,
    required this.error,
  });

  final String jobId;
  final String snapshotId;
  final Capability capability;
  final CapabilityAnalysisPhase phase;
  final int processed;
  final int total;
  final String? currentPath;
  final bool cancelled;
  final String? error;

  factory CapabilityAnalysisProgress.fromJson(Map<String, dynamic> json) {
    const unknownCapability = 'unknown';
    final capabilityValue = _string(
      json['capability'],
      unknownCapability,
      'capability',
    );
    final capability = _capability(
      capabilityValue,
      unknownCapability,
      'capability',
    );
    final context = capability.wireValue;
    return CapabilityAnalysisProgress(
      jobId: _string(json['job_id'], context, 'job_id'),
      snapshotId: _string(json['snapshot_id'], context, 'snapshot_id'),
      capability: capability,
      phase: _analysisPhase(
        _string(json['phase'], context, 'phase'),
        context,
        'phase',
      ),
      processed: _int(json['processed'], context, 'processed'),
      total: _int(json['total'], context, 'total'),
      currentPath: _optionalString(
        json['current_path'],
        context,
        'current_path',
      ),
      cancelled: _bool(json['cancelled'], context, 'cancelled'),
      error: _optionalString(json['error'], context, 'error'),
    );
  }

  CapabilityAnalysisProgress copyWith({
    int? processed,
    int? total,
    Object? currentPath = _unset,
    bool? cancelled,
    Object? error = _unset,
  }) => CapabilityAnalysisProgress(
    jobId: jobId,
    snapshotId: snapshotId,
    capability: capability,
    phase: phase,
    processed: processed ?? this.processed,
    total: total ?? this.total,
    currentPath: identical(currentPath, _unset)
        ? this.currentPath
        : currentPath as String?,
    cancelled: cancelled ?? this.cancelled,
    error: identical(error, _unset) ? this.error : error as String?,
  );

  Map<String, dynamic> toJson() => {
    'job_id': jobId,
    'snapshot_id': snapshotId,
    'capability': capability.wireValue,
    'phase': phase.wireValue,
    'processed': processed,
    'total': total,
    'current_path': currentPath,
    'cancelled': cancelled,
    'error': error,
  };
}

Capability _capability(String value, String capability, String field) =>
    switch (value) {
      'large_files' => Capability.largeFiles,
      'cleanup_candidates' => Capability.cleanupCandidates,
      'duplicate_files' => Capability.duplicateFiles,
      'similar_photos' => Capability.similarPhotos,
      'applications' => Capability.applications,
      'browser_privacy' => Capability.browserPrivacy,
      'space_analysis' => Capability.spaceAnalysis,
      _ => _malformed(capability, field),
    };

CapabilityLevel _capabilityLevel(
  String value,
  String capability,
  String field,
) => switch (value) {
  'full_path' => CapabilityLevel.fullPath,
  'app_stats_only' => CapabilityLevel.appStatsOnly,
  'guided_only' => CapabilityLevel.guidedOnly,
  _ => _malformed(capability, field),
};

LargeFileThresholdPreset _largeFileThresholdPreset(
  String value,
  String capability,
  String field,
) => switch (value) {
  '50_mb' => LargeFileThresholdPreset.mb50,
  '100_mb' => LargeFileThresholdPreset.mb100,
  '1_gb' => LargeFileThresholdPreset.gb1,
  '5_gb' => LargeFileThresholdPreset.gb5,
  _ => _malformed(capability, field),
};

AgePreset _agePreset(String value, String capability, String field) =>
    switch (value) {
      '7_days' => AgePreset.days7,
      '30_days' => AgePreset.days30,
      '90_days' => AgePreset.days90,
      _ => _malformed(capability, field),
    };

SimilarityPreset _similarityPreset(
  String value,
  String capability,
  String field,
) => switch (value) {
  'strict' => SimilarityPreset.strict,
  'balanced' => SimilarityPreset.balanced,
  'loose' => SimilarityPreset.loose,
  _ => _malformed(capability, field),
};

Recommendation _recommendation(String value) => switch (value) {
  'safe_to_remove' => Recommendation.safeToRemove,
  'review_needed' => Recommendation.reviewNeeded,
  'keep' => Recommendation.keep,
  _ => Recommendation.unknown,
};

AnalysisConfidence _analysisConfidence(
  String value,
  String capability,
  String field,
) => switch (value) {
  'low' => AnalysisConfidence.low,
  'medium' => AnalysisConfidence.medium,
  'high' => AnalysisConfidence.high,
  _ => _malformed(capability, field),
};

CapabilityAnalysisPhase _analysisPhase(
  String value,
  String capability,
  String field,
) => switch (value) {
  'preparing' => CapabilityAnalysisPhase.preparing,
  'indexing' => CapabilityAnalysisPhase.indexing,
  'inspecting' => CapabilityAnalysisPhase.inspecting,
  'hashing' => CapabilityAnalysisPhase.hashing,
  'grouping' => CapabilityAnalysisPhase.grouping,
  'building_result' => CapabilityAnalysisPhase.buildingResult,
  'completed' => CapabilityAnalysisPhase.completed,
  _ => _malformed(capability, field),
};

Map<String, dynamic> _json(Object? value, String capability, String field) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  _malformed(capability, field);
}

List<dynamic> _list(Object? value, String capability, String field) {
  if (value is List<dynamic>) return value;
  _malformed(capability, field);
}

List<String> _strings(Object? value, String capability, String field) =>
    _list(value, capability, field)
        .asMap()
        .entries
        .map(
          (entry) => _string(entry.value, capability, '$field[${entry.key}]'),
        )
        .toList(growable: false);

String _string(Object? value, String capability, String field) {
  if (value is String) return value;
  _malformed(capability, field);
}

String? _optionalString(Object? value, String capability, String field) {
  if (value == null) return null;
  return _string(value, capability, field);
}

int _int(Object? value, String capability, String field) {
  if (value is int) return value;
  _malformed(capability, field);
}

int? _optionalInt(Object? value, String capability, String field) {
  if (value == null) return null;
  return _int(value, capability, field);
}

bool _bool(Object? value, String capability, String field) {
  if (value is bool) return value;
  _malformed(capability, field);
}

Never _malformed(String capability, String field) {
  throw FormatException('Malformed capability payload for $capability: $field');
}
