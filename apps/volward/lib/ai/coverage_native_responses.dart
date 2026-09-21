import 'dart:convert';

import 'coverage_models.dart';

class CoverageEngineException implements Exception {
  CoverageEngineException(this.message);

  final String message;

  @override
  String toString() => message;
}

Map<String, dynamic> decodeCoverageObjectJson(String raw) {
  if (raw.startsWith('error:')) {
    throw CoverageEngineException(raw);
  }
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw CoverageEngineException('invalid coverage json');
  }
  return Map<String, dynamic>.from(decoded);
}

CoveragePlanSummary parseCoveragePlanSummary(String raw) =>
    CoveragePlanSummary.fromJson(decodeCoverageObjectJson(raw));

CoveragePage parseCoveragePage(String raw) =>
    CoveragePage.fromJson(decodeCoverageObjectJson(raw));

CoverageTreePage parseCoverageTreePage(String raw) =>
    CoverageTreePage.fromJson(decodeCoverageObjectJson(raw));

CoverageTailPage parseCoverageTailPage(String raw) =>
    CoverageTailPage.fromJson(decodeCoverageObjectJson(raw));

List<CoverageTreeNode> parseCoverageTreeExpandNodes(String raw) {
  final map = decodeCoverageObjectJson(raw);
  final nodes = map['nodes'];
  if (nodes is! List) return const [];
  return nodes
      .whereType<Map>()
      .map((e) => CoverageTreeNode.fromJson(Map<String, dynamic>.from(e)))
      .toList(growable: false);
}

List<Map<String, dynamic>> parseCoverageGroupMembers(String raw) {
  final map = decodeCoverageObjectJson(raw);
  final members = map['members'];
  if (members is! List) return const [];
  return members
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList(growable: false);
}
