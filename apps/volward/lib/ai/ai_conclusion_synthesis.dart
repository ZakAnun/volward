import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'ai_provider.dart';
import 'ai_result_overview.dart';

const int aiConclusionSynthesisSchemaVersion = 2;

/// Scan context sent to conclusion synthesis (Stage B).
class AiConclusionSynthesisScan {
  const AiConclusionSynthesisScan({
    required this.rootPath,
    required this.truncated,
    required this.fullCoverage,
  });

  final String rootPath;
  final bool truncated;
  final bool fullCoverage;

  Map<String, dynamic> toJson() => {
    'root_path': rootPath,
    'truncated': truncated,
    'full_coverage': fullCoverage,
  };
}

/// Rollup totals for the whole analyzed scope.
class AiConclusionSynthesisTotals {
  const AiConclusionSynthesisTotals({
    required this.safeBytes,
    required this.reviewCount,
    required this.keepCount,
    required this.analyzedItemCount,
    required this.analyzedTotalBytes,
    required this.rootSizeBytes,
    this.shareOfRootPct,
  });

  final int safeBytes;
  final int reviewCount;
  final int keepCount;
  final int analyzedItemCount;
  final int analyzedTotalBytes;
  final int rootSizeBytes;
  final double? shareOfRootPct;

  Map<String, dynamic> toJson() => {
    'safe_bytes': safeBytes,
    'review_count': reviewCount,
    'keep_count': keepCount,
    'analyzed_item_count': analyzedItemCount,
    'analyzed_total_bytes': analyzedTotalBytes,
    'root_size_bytes': rootSizeBytes,
    if (shareOfRootPct != null) 'share_of_root_pct': shareOfRootPct,
  };
}

/// Per-directory rollup included in the synthesis user JSON.
class AiConclusionSynthesisDirectory {
  const AiConclusionSynthesisDirectory({
    required this.path,
    required this.displayLabel,
    required this.safeBytes,
    required this.reviewCount,
    required this.keepCount,
    required this.shareOfSafePct,
    required this.reasonHighlights,
  });

  final String path;
  final String displayLabel;
  final int safeBytes;
  final int reviewCount;
  final int keepCount;
  final double shareOfSafePct;
  final List<String> reasonHighlights;

  Map<String, dynamic> toJson() => {
    'path': path,
    'display_label': displayLabel,
    'safe_bytes': safeBytes,
    'review_count': reviewCount,
    'keep_count': keepCount,
    'share_of_safe_pct': shareOfSafePct,
    'reason_highlights': reasonHighlights,
  };

  factory AiConclusionSynthesisDirectory.fromOverviewDirectory(
    AiDirectoryConclusion directory,
  ) => AiConclusionSynthesisDirectory(
    path: directory.path,
    displayLabel: directory.displayLabel,
    safeBytes: directory.safeBytes,
    reviewCount: directory.reviewCount,
    keepCount: directory.keepCount,
    shareOfSafePct: directory.shareOfSafePct,
    reasonHighlights: List<String>.from(directory.reasonHighlights),
  );
}

/// User JSON payload for POST `/v1/ai/synthesize-conclusion` (schema v2).
class AiConclusionSynthesisRequest {
  const AiConclusionSynthesisRequest({
    required this.analysisSessionId,
    required this.locale,
    required this.rootLabel,
    required this.scan,
    required this.totals,
    required this.directories,
    this.schemaVersion = aiConclusionSynthesisSchemaVersion,
  });

  final int schemaVersion;
  final String analysisSessionId;
  final String locale;
  final String rootLabel;
  final AiConclusionSynthesisScan scan;
  final AiConclusionSynthesisTotals totals;
  final List<AiConclusionSynthesisDirectory> directories;

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'analysis_session_id': analysisSessionId,
    'locale': locale,
    'root_label': rootLabel,
    'scan': scan.toJson(),
    'totals': totals.toJson(),
    'directories': directories.map((d) => d.toJson()).toList(growable: false),
  };
}

class AiConclusionSynthesisResponse {
  const AiConclusionSynthesisResponse({required this.text});

  final String text;

  factory AiConclusionSynthesisResponse.fromJson(Map<String, dynamic> json) {
    return AiConclusionSynthesisResponse(text: json['text'] as String? ?? '');
  }
}

/// Builds the Stage B request from P1 overview data and the same build input
/// used to produce the overview (keeps [root_label] / scan flags aligned).
AiConclusionSynthesisRequest buildConclusionSynthesisRequest({
  required AiAnalysisConclusionOverview overview,
  required AiResultOverviewBuildInput buildInput,
  required String analysisSessionId,
  required String locale,
}) {
  assert(
    overview.rootPath == buildInput.rootPath,
    'overview rootPath must match buildInput.rootPath',
  );
  return AiConclusionSynthesisRequest(
    analysisSessionId: analysisSessionId,
    locale: locale,
    rootLabel: buildInput.targetLabel,
    scan: AiConclusionSynthesisScan(
      rootPath: buildInput.rootPath,
      truncated: buildInput.truncated,
      fullCoverage: buildInput.fullCoverage,
    ),
    totals: AiConclusionSynthesisTotals(
      safeBytes: overview.safeBytes,
      reviewCount: overview.reviewCount,
      keepCount: overview.keepCount,
      analyzedItemCount: overview.analyzedItemCount,
      analyzedTotalBytes: overview.analyzedTotalBytes,
      rootSizeBytes: overview.rootSizeBytes,
      shareOfRootPct: overview.shareOfRootPct,
    ),
    directories: overview.directories
        .map(AiConclusionSynthesisDirectory.fromOverviewDirectory)
        .toList(growable: false),
  );
}

/// Stable cache key for synthesized narrative text (overview stats + verdict reasons).
String conclusionContentHash(
  AiAnalysisConclusionOverview overview,
  Iterable<AiVerdict> verdicts,
) {
  final payload = _conclusionHashPayload(overview, verdicts);
  final encoded = jsonEncode(payload);
  return sha256.convert(utf8.encode(encoded)).toString();
}

Map<String, dynamic> _conclusionHashPayload(
  AiAnalysisConclusionOverview overview,
  Iterable<AiVerdict> verdicts,
) {
  final sortedVerdicts = verdicts.toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return {
    'overview': {
      'root_path': overview.rootPath,
      'safe_bytes': overview.safeBytes,
      'review_count': overview.reviewCount,
      'keep_count': overview.keepCount,
      'analyzed_item_count': overview.analyzedItemCount,
      'analyzed_total_bytes': overview.analyzedTotalBytes,
      'root_size_bytes': overview.rootSizeBytes,
      'share_of_root_pct': overview.shareOfRootPct,
      'truncated': overview.truncated,
      'full_coverage': overview.fullCoverage,
      'directories': overview.directories
          .map(
            (dir) => {
              'path': dir.path,
              'safe_bytes': dir.safeBytes,
              'review_count': dir.reviewCount,
              'keep_count': dir.keepCount,
              'share_of_safe_pct': dir.shareOfSafePct,
              'reason_highlights': dir.reasonHighlights,
            },
          )
          .toList(growable: false),
    },
    'verdicts': [
      for (final verdict in sortedVerdicts)
        if (verdict.verdict != 'unanalyzed')
          {
            'path': verdict.path,
            'verdict': verdict.verdict,
            'confidence': verdict.confidence,
            'reason': verdict.reason,
          },
    ],
  };
}
