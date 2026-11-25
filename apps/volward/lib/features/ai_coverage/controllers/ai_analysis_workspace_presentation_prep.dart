import 'dart:convert';
import 'dart:io';

import '../../../ai/ai_provider.dart';
import '../../../ai/ai_result_groups.dart';
import '../../../proto/ai_payload_pb_decoder.dart';
import '../../../snapshot_cache.dart';

int asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

class LoadedAnalysisParseResult {
  const LoadedAnalysisParseResult({
    required this.loadedRootPath,
    required this.entryMaps,
    required this.resultSizes,
  });

  final String loadedRootPath;
  final List<Map<String, dynamic>> entryMaps;
  final Map<String, int> resultSizes;
}

String? readAnalysisJsonFromCacheRoot(String cacheRoot, List<String> keys) {
  final base = '$cacheRoot/ai_analysis';
  for (final key in keys) {
    if (key.isEmpty) continue;
    final pbFile = File('$base/$key.pb');
    if (pbFile.existsSync()) {
      final map = decodeAiAnalysisResultPb(pbFile.readAsBytesSync());
      if (map != null) {
        return jsonEncode({
          'root_path': map['root_path'],
          'entries': map['entries'],
        });
      }
    }
    final jsonFile = File('$base/$key.json');
    if (jsonFile.existsSync()) {
      return jsonFile.readAsStringSync();
    }
  }
  return null;
}

bool savedAnalysisFileExists(String key) {
  if (key.isEmpty) return false;
  final base = '${SnapshotCache.cacheDir().path}/ai_analysis';
  return File('$base/$key.pb').existsSync() ||
      File('$base/$key.json').existsSync();
}

LoadedAnalysisParseResult parseLoadedAnalysisJsonString(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('expected object');
  }
  final map = Map<String, dynamic>.from(decoded);
  final loadedRootPath = map['root_path']?.toString() ?? '';
  final entriesRaw = map['entries'];
  if (entriesRaw is! List) {
    throw const FormatException('missing entries');
  }
  final entryMaps = <Map<String, dynamic>>[];
  final resultSizes = <String, int>{};
  for (final rawEntry in entriesRaw) {
    if (rawEntry is! Map) continue;
    final entry = Map<String, dynamic>.from(rawEntry);
    final path = entry['path'] as String?;
    if (path == null || path.isEmpty) continue;
    resultSizes[path] = asInt(entry['size_bytes']);
    entryMaps.add(entry);
  }
  return LoadedAnalysisParseResult(
    loadedRootPath: loadedRootPath,
    entryMaps: entryMaps,
    resultSizes: resultSizes,
  );
}

class CandidateCleanupMeta {
  const CandidateCleanupMeta({
    this.cleanupSource,
    this.cleanupHint,
    this.retentionDays,
  });

  final String? cleanupSource;
  final String? cleanupHint;
  final int? retentionDays;
}

class LoadedVerdictsBuildInput {
  const LoadedVerdictsBuildInput({
    required this.entryMaps,
    required this.candidateMetaByPath,
  });

  final List<Map<String, dynamic>> entryMaps;
  final Map<String, CandidateCleanupMeta> candidateMetaByPath;
}

List<AiVerdict> buildLoadedVerdicts(LoadedVerdictsBuildInput input) {
  return input.entryMaps
      .map((entry) {
        final path = entry['path'] as String? ?? '';
        final meta = input.candidateMetaByPath[path];
        return AiVerdict(
          path: path,
          verdict: entry['verdict']?.toString() ?? '',
          confidence: entry['confidence']?.toString() ?? '',
          reason: entry['reason']?.toString() ?? '',
          classificationSource: entry['classification_source'] as String?,
          cleanupSource:
              entry['cleanup_source'] as String? ?? meta?.cleanupSource,
          cleanupHint: entry['cleanup_hint'] as String? ?? meta?.cleanupHint,
          retentionDays: switch (entry['retention_days']) {
            int value => value,
            num value => value.toInt(),
            _ => meta?.retentionDays,
          },
        );
      })
      .toList(growable: false);
}

class ResultsPresentationPrepInput {
  const ResultsPresentationPrepInput({
    required this.verdicts,
    required this.sizeByPath,
    required this.rootPath,
    required this.directoryPaths,
    required this.maxAutoExpandedRows,
    required this.preClassified,
    required this.firstLevelDirectoryPaths,
    required this.fullCoverageLayout,
  });

  final List<AiVerdict> verdicts;
  final Map<String, int> sizeByPath;
  final String rootPath;
  final List<String> directoryPaths;
  final int maxAutoExpandedRows;
  final List<Map<String, dynamic>> preClassified;
  final List<String> firstLevelDirectoryPaths;
  final bool fullCoverageLayout;
}

class ResultsPresentationPrepOutput {
  const ResultsPresentationPrepOutput({
    required this.verdictPaths,
    required this.normalizedGroups,
    required this.expandedGroupPaths,
    required this.selectedPaths,
  });

  final Set<String> verdictPaths;
  final List<AiResultGroup> normalizedGroups;
  final Set<String> expandedGroupPaths;
  final Set<String> selectedPaths;
}

Set<String> selectedPathsForVerdictsIsolate(
  List<AiVerdict> verdicts,
  List<Map<String, dynamic>> preClassified,
) {
  final aiPaths = verdicts.map((verdict) => verdict.path).toSet();
  final selected = <String>{};
  for (final entry in preClassified) {
    if (entry['deletable'] != true || entry['confidence'] != 'high') continue;
    final path = entry['path'] as String?;
    if (path == null || path.isEmpty || aiPaths.contains(path)) continue;
    selected.add(path);
  }
  for (final verdict in verdicts) {
    if (verdict.verdict == 'safe_to_remove') {
      selected.add(verdict.path);
    }
  }
  return selected;
}

Set<String> expandedGroupPathsForPresentation(
  List<AiResultGroup> groups, {
  required int maxAutoExpandedRows,
}) {
  var rowBudget = maxAutoExpandedRows;
  final expanded = <String>{};
  for (final group in groups) {
    final actionable = group.reviewCount > 0 || group.safeCount > 0;
    if (!actionable && group.items.length >= 3) continue;
    final rowCost = group.items.length + 1;
    if (rowBudget < rowCost) break;
    expanded.add(group.path);
    rowBudget -= rowCost;
  }
  return expanded;
}

ResultsPresentationPrepOutput prepareResultsPresentationIsolate(
  ResultsPresentationPrepInput input,
) {
  var groups = groupAiResults(
    classifiedVerdictsForGroups(input.verdicts, input.preClassified),
    input.sizeByPath,
    rootPath: input.rootPath,
    directoryPaths: input.directoryPaths.toSet(),
  );
  if (input.fullCoverageLayout && input.rootPath.isNotEmpty) {
    groups = ensureFirstLevelDirectoryGroups(
      groups,
      input.rootPath,
      input.firstLevelDirectoryPaths,
    );
  }
  final expanded = expandedGroupPathsForPresentation(
    groups,
    maxAutoExpandedRows: input.maxAutoExpandedRows,
  );
  return ResultsPresentationPrepOutput(
    verdictPaths: Set.unmodifiable(input.verdicts.map((v) => v.path)),
    normalizedGroups: groups,
    expandedGroupPaths: expanded,
    selectedPaths: selectedPathsForVerdictsIsolate(
      input.verdicts,
      input.preClassified,
    ),
  );
}
