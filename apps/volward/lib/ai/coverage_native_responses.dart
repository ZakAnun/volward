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

List<Map<String, dynamic>> parseCoverageGroupMembers(String raw) {
  final map = decodeCoverageObjectJson(raw);
  final members = map['members'];
  if (members is! List) return const [];
  return members
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList(growable: false);
}
