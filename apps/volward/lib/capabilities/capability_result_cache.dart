import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'capability_models.dart';

/// In-memory capability result cache. The key covers snapshot, capability,
/// and normalized options; analyzer/schema versions are bound into the
/// stored result. Task 8 adds snapshot-change invalidation.
class CapabilityAnalysisCache {
  final Map<String, CapabilityAnalysisResult> _entries = {};

  String key(
    String snapshotId,
    Capability capability,
    AnalysisOptions options,
    {
    int schemaVersion = capabilitySchemaVersion,
    String? analyzerVersion,
  }) {
    final version = analyzerVersion ?? capabilityAnalyzerVersions[capability] ?? 'unknown';
    return '${capability.wireValue}|$snapshotId|$schemaVersion|$version|'
        '${jsonEncode(options.toJson())}';
  }

  CapabilityAnalysisResult? get(
    String snapshotId,
    Capability capability,
    AnalysisOptions options,
  ) {
    final entry = _entries[key(snapshotId, capability, options)];
    if (entry != null && entry.schemaVersion != capabilitySchemaVersion) {
      return null;
    }
    return entry;
  }

  void put(
    String snapshotId,
    Capability capability,
    AnalysisOptions options,
    CapabilityAnalysisResult result,
  ) {
    _entries[key(snapshotId, capability, options)] = result;
  }

  void invalidateForSnapshot(String snapshotId) {
    _entries.removeWhere((key, _) => key.contains('|$snapshotId|'));
  }

  @visibleForTesting
  int get length => _entries.length;
}
