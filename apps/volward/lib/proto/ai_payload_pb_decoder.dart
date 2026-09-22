/// Hand-written proto3 decoders for AI workspace wire messages in
/// `proto/volward.proto` (`AiCandidatesPayload`, `AiAnalysisResultWire`).
library;

import 'dart:typed_data';

import 'proto_wire_reader.dart';

/// JSON-shaped map compatible with `_parseAiCandidatesPayload`.
Map<String, dynamic>? decodeAiCandidatesPb(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  try {
    return _decodeCandidatesPayload(ProtoWireReader(bytes, 0, bytes.length));
  } catch (_) {
    return null;
  }
}

/// JSON-shaped map compatible with `_parseLoadedAnalysisJsonString`.
Map<String, dynamic>? decodeAiAnalysisResultPb(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  try {
    return _decodeAnalysisResult(ProtoWireReader(bytes, 0, bytes.length));
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _decodeCandidatesPayload(ProtoWireReader r) {
  final preClassified = <Map<String, dynamic>>[];
  final unknownCandidates = <Map<String, dynamic>>[];
  var snapshotId = '';
  var rootPath = '';
  var resultCacheKey = '';
  var estimatedInputTokens = 0;
  var estimatedByokBatchInputTokens = 0;
  var totalRawCount = 0;
  var candidatesTotalBeforeCap = 0;
  var truncated = false;
  var preClassifiedTruncated = false;
  var hasExistingResult = false;

  while (!r.isDone) {
    final tag = r.readVarint();
    final fieldNum = tag >> 3;
    final wireType = tag & 7;
    switch (fieldNum) {
      case 1:
        snapshotId = r.readString();
      case 2:
        rootPath = r.readString();
      case 3:
        resultCacheKey = r.readString();
      case 4:
        preClassified.add(_decodePreClassified(r.readLenSlice()));
      case 5:
        unknownCandidates.add(_decodeUnknownCandidate(r.readLenSlice()));
      case 6:
        estimatedInputTokens = r.readVarint();
      case 7:
        totalRawCount = r.readVarint();
      case 8:
        candidatesTotalBeforeCap = r.readVarint();
      case 9:
        truncated = r.readVarint() != 0;
      case 10:
        preClassifiedTruncated = r.readVarint() != 0;
      case 11:
        hasExistingResult = r.readVarint() != 0;
      case 12:
        estimatedByokBatchInputTokens = r.readVarint();
      default:
        r.skipField(wireType);
    }
  }

  return {
    'snapshot_id': snapshotId,
    'root_path': rootPath,
    'result_cache_key': resultCacheKey,
    'pre_classified': preClassified,
    'unknown_candidates': unknownCandidates,
    'estimated_input_tokens': estimatedInputTokens,
    'estimated_byok_batch_input_tokens': estimatedByokBatchInputTokens,
    'total_raw_count': totalRawCount,
    'candidates_total_before_cap': candidatesTotalBeforeCap,
    'truncated': truncated,
    'pre_classified_truncated': preClassifiedTruncated,
    'has_existing_result': hasExistingResult,
  };
}

Map<String, dynamic> _decodePreClassified(ProtoWireReader r) {
  var path = '';
  var sizeBytes = 0;
  var isDir = false;
  var category = 8;
  var confidence = '';
  var reason = '';
  var deletable = false;

  while (!r.isDone) {
    final tag = r.readVarint();
    final fieldNum = tag >> 3;
    final wireType = tag & 7;
    switch (fieldNum) {
      case 1:
        path = r.readString();
      case 2:
        sizeBytes = r.readVarint();
      case 3:
        isDir = r.readVarint() != 0;
      case 4:
        category = r.readVarint();
      case 5:
        confidence = r.readString();
      case 6:
        reason = r.readString();
      case 7:
        deletable = r.readVarint() != 0;
      default:
        r.skipField(wireType);
    }
  }

  return {
    'path': path,
    'size_bytes': sizeBytes,
    'is_dir': isDir,
    'category': _entryCategory(category),
    'confidence': confidence,
    'reason': reason,
    'deletable': deletable,
  };
}

Map<String, dynamic> _decodeUnknownCandidate(ProtoWireReader r) {
  var path = '';
  var sizeBytes = 0;
  var isDir = false;
  int? childCount;
  String? extension;
  String? cleanupSource;
  String? cleanupHint;
  int? retentionDays;
  final memberPaths = <String>[];
  String? deleteTarget;

  while (!r.isDone) {
    final tag = r.readVarint();
    final fieldNum = tag >> 3;
    final wireType = tag & 7;
    switch (fieldNum) {
      case 1:
        path = r.readString();
      case 2:
        sizeBytes = r.readVarint();
      case 3:
        isDir = r.readVarint() != 0;
      case 4:
        childCount = r.readVarint();
      case 5:
        extension = r.readString();
      case 6:
        cleanupSource = r.readString();
      case 7:
        cleanupHint = r.readString();
      case 8:
        retentionDays = r.readVarint();
      case 9:
        memberPaths.add(r.readString());
      case 10:
        deleteTarget = r.readString();
      default:
        r.skipField(wireType);
    }
  }

  return {
    'path': path,
    'size_bytes': sizeBytes,
    'is_dir': isDir,
    if (childCount != null) 'child_count': childCount,
    if (extension != null && extension.isNotEmpty) 'extension': extension,
    if (cleanupSource != null && cleanupSource.isNotEmpty)
      'cleanup_source': cleanupSource,
    if (cleanupHint != null && cleanupHint.isNotEmpty)
      'cleanup_hint': cleanupHint,
    if (retentionDays != null) 'retention_days': retentionDays,
    if (memberPaths.isNotEmpty) 'member_paths': memberPaths,
    if (deleteTarget != null && deleteTarget.isNotEmpty)
      'delete_target': deleteTarget,
  };
}

Map<String, dynamic> _decodeAnalysisResult(ProtoWireReader r) {
  final entries = <Map<String, dynamic>>[];
  var schemaVersion = 0;
  var snapshotId = '';
  String? cacheKey;
  String? rootPath;
  var analyzedAtMs = 0;
  var mode = '';
  var model = '';
  Map<String, dynamic>? tokenUsage;
  var costEstimateUsd = 0.0;
  var creditsUsed = 0;

  while (!r.isDone) {
    final tag = r.readVarint();
    final fieldNum = tag >> 3;
    final wireType = tag & 7;
    switch (fieldNum) {
      case 1:
        schemaVersion = r.readVarint();
      case 2:
        snapshotId = r.readString();
      case 3:
        cacheKey = r.readString();
      case 4:
        rootPath = r.readString();
      case 5:
        analyzedAtMs = r.readVarint();
      case 6:
        mode = r.readString();
      case 7:
        model = r.readString();
      case 8:
        entries.add(_decodeVerdictEntry(r.readLenSlice()));
      case 9:
        tokenUsage = _decodeTokenUsage(r.readLenSlice());
      case 10:
        costEstimateUsd = fixed64ToDouble(r.readFixed64());
      case 11:
        creditsUsed = r.readVarint();
      default:
        r.skipField(wireType);
    }
  }

  return {
    'schema_version': schemaVersion,
    'snapshot_id': snapshotId,
    if (cacheKey != null) 'cache_key': cacheKey,
    if (rootPath != null) 'root_path': rootPath,
    'analyzed_at_ms': analyzedAtMs,
    'mode': mode,
    'model': model,
    'entries': entries,
    if (tokenUsage != null) 'token_usage': tokenUsage,
    'cost_estimate_usd': costEstimateUsd,
    'credits_used': creditsUsed,
  };
}

Map<String, dynamic> _decodeVerdictEntry(ProtoWireReader r) {
  var path = '';
  var sizeBytes = 0;
  var verdict = '';
  var confidence = '';
  var reason = '';
  String? cleanupSource;
  String? cleanupHint;
  int? retentionDays;

  while (!r.isDone) {
    final tag = r.readVarint();
    final fieldNum = tag >> 3;
    final wireType = tag & 7;
    switch (fieldNum) {
      case 1:
        path = r.readString();
      case 2:
        sizeBytes = r.readVarint();
      case 3:
        verdict = r.readString();
      case 4:
        confidence = r.readString();
      case 5:
        reason = r.readString();
      case 6:
        cleanupSource = r.readString();
      case 7:
        cleanupHint = r.readString();
      case 8:
        retentionDays = r.readVarint();
      default:
        r.skipField(wireType);
    }
  }

  return {
    'path': path,
    'size_bytes': sizeBytes,
    'verdict': verdict,
    'confidence': confidence,
    'reason': reason,
    if (cleanupSource != null && cleanupSource.isNotEmpty)
      'cleanup_source': cleanupSource,
    if (cleanupHint != null && cleanupHint.isNotEmpty)
      'cleanup_hint': cleanupHint,
    if (retentionDays != null) 'retention_days': retentionDays,
  };
}

Map<String, dynamic> _decodeTokenUsage(ProtoWireReader r) {
  var input = 0;
  var output = 0;
  while (!r.isDone) {
    final tag = r.readVarint();
    final fieldNum = tag >> 3;
    final wireType = tag & 7;
    switch (fieldNum) {
      case 1:
        input = r.readVarint();
      case 2:
        output = r.readVarint();
      default:
        r.skipField(wireType);
    }
  }
  return {'input': input, 'output': output};
}

String _entryCategory(int v) {
  return const {
        1: 'Cache',
        2: 'Temp',
        3: 'Media',
        4: 'AppData',
        5: 'Orphan',
        6: 'Duplicate',
        7: 'System',
        8: 'Unknown',
        9: 'BuildArtifact',
      }[v] ??
      'Unknown';
}
