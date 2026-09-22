import 'dart:convert';

import 'ai_provider.dart';
import 'coverage_models.dart';
import '../bridge/native_bridge.dart';
import '../volward_session.dart';

/// Shared DeepSeek analyze contract (request/parse/batch/endpoint).
///
/// Production uses [SessionAiContract] over FFI. Tests inject a fake.
abstract class AiContract {
  String upstreamEndpoint();
  int batchSize();
  String buildRequestJson(List<AiCandidate> batch);
  List<AiVerdict> parseResponseJson(String body, List<AiCandidate> batch);

  int treeBatchSize() => 80;

  String buildTreeRequestJson(List<CoverageTreeNode> batch) {
    throw UnimplementedError('tree contract unavailable');
  }

  List<AiVerdict> parseTreeResponseJson(
    String body,
    List<CoverageTreeNode> batch,
  ) {
    throw UnimplementedError('tree contract unavailable');
  }
}

Map<String, dynamic> analyzeCandidateMap(AiCandidate c) => {
  'path': c.path,
  'size_bytes': c.sizeBytes,
  'is_dir': c.isDir,
  if (c.childCount != null) 'child_count': c.childCount,
  if (c.extension != null) 'extension': c.extension,
  if (c.cleanupSource != null && c.cleanupSource!.isNotEmpty)
    'cleanup_source': c.cleanupSource,
  if (c.cleanupHint != null && c.cleanupHint!.isNotEmpty)
    'cleanup_hint': c.cleanupHint,
  if (c.retentionDays != null) 'retention_days': c.retentionDays,
};

/// FFI-backed contract. Throws [ai_contract_unavailable] if symbols missing.
class SessionAiContract implements AiContract {
  SessionAiContract(this._session) {
    if (!_session.hasAiContractApi) {
      throw Exception('ai_contract_unavailable');
    }
  }

  final VolwardSession _session;

  @override
  String upstreamEndpoint() {
    final v = _session.aiUpstreamEndpoint();
    if (v == null || v.isEmpty) {
      throw Exception('ai_contract_unavailable');
    }
    return v;
  }

  @override
  int batchSize() {
    final v = _session.aiBatchSize();
    if (v == null || v <= 0) {
      throw Exception('ai_contract_unavailable');
    }
    return v;
  }

  @override
  String buildRequestJson(List<AiCandidate> batch) {
    final raw = _session.aiBuildRequestJson(
      batch.map(analyzeCandidateMap).toList(),
    );
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) {
      throw Exception('ai_contract_unavailable');
    }
    return raw;
  }

  @override
  List<AiVerdict> parseResponseJson(String body, List<AiCandidate> batch) {
    final out = _session.aiParseResponseJson(
      body,
      batch.map(analyzeCandidateMap).toList(),
    );
    if (out == null) {
      throw Exception('ai_contract_unavailable');
    }
    return out;
  }

  @override
  int treeBatchSize() {
    final v = _session.aiTreeBatchSize();
    if (v == null || v <= 0) {
      throw Exception('ai_tree_contract_unavailable');
    }
    return v;
  }

  @override
  String buildTreeRequestJson(List<CoverageTreeNode> batch) {
    final raw = _session.aiBuildTreeRequestJson(
      batch.map((n) => n.toJson()).toList(),
    );
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) {
      throw Exception('ai_tree_contract_unavailable');
    }
    return raw;
  }

  @override
  List<AiVerdict> parseTreeResponseJson(
    String body,
    List<CoverageTreeNode> batch,
  ) {
    final out = _session.aiParseTreeResponseJson(
      body,
      batch.map((n) => n.toJson()).toList(),
    );
    if (out == null) {
      throw Exception('ai_tree_contract_unavailable');
    }
    return out;
  }
}

/// FFI-backed contract for background isolates (no [VolwardSession]).
class BridgeAiContract implements AiContract {
  BridgeAiContract(this._bridge) {
    if (!_bridge.hasAiContractApi) {
      throw Exception('ai_contract_unavailable');
    }
  }

  final VolwardNativeBridge _bridge;

  @override
  String upstreamEndpoint() {
    final v = _bridge.aiUpstreamEndpoint();
    if (v == null || v.isEmpty) {
      throw Exception('ai_contract_unavailable');
    }
    return v;
  }

  @override
  int batchSize() {
    final v = _bridge.aiBatchSize();
    if (v == null || v <= 0) {
      throw Exception('ai_contract_unavailable');
    }
    return v;
  }

  @override
  String buildRequestJson(List<AiCandidate> batch) {
    final raw = _bridge.aiBuildRequestJson(
      jsonEncode(batch.map(analyzeCandidateMap).toList()),
    );
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) {
      throw Exception('ai_contract_unavailable');
    }
    return raw;
  }

  @override
  List<AiVerdict> parseResponseJson(String body, List<AiCandidate> batch) {
    final raw = _bridge.aiParseResponseJson(
      body,
      jsonEncode(batch.map(analyzeCandidateMap).toList()),
    );
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) {
      throw Exception('ai_contract_unavailable');
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw Exception('ai_contract_unavailable');
      }
      return decoded
          .whereType<Map>()
          .map((e) => AiVerdict.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      throw Exception('ai_contract_unavailable');
    }
  }

  @override
  int treeBatchSize() {
    if (!_bridge.hasAiTreeContractApi) {
      throw Exception('ai_tree_contract_unavailable');
    }
    final v = _bridge.aiTreeBatchSize();
    if (v == null || v <= 0) {
      throw Exception('ai_tree_contract_unavailable');
    }
    return v;
  }

  @override
  String buildTreeRequestJson(List<CoverageTreeNode> batch) {
    final raw = _bridge.aiBuildTreeRequestJson(
      jsonEncode(batch.map((n) => n.toJson()).toList()),
    );
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) {
      throw Exception('ai_tree_contract_unavailable');
    }
    return raw;
  }

  @override
  List<AiVerdict> parseTreeResponseJson(
    String body,
    List<CoverageTreeNode> batch,
  ) {
    final raw = _bridge.aiParseTreeResponseJson(
      body,
      jsonEncode(batch.map((n) => n.toJson()).toList()),
    );
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) {
      throw Exception('ai_tree_contract_unavailable');
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw Exception('ai_tree_contract_unavailable');
      }
      return decoded
          .whereType<Map>()
          .map((e) => AiVerdict.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      throw Exception('ai_tree_contract_unavailable');
    }
  }
}
