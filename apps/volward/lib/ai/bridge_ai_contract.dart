import 'dart:convert';

import '../bridge/native_bridge.dart';
import 'ai_conclusion_synthesis_body.dart';
import 'ai_contract_api.dart';
import 'ai_provider.dart';
import 'coverage_models.dart';

/// FFI-backed contract for background isolates (without a UI session).
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

  @override
  String buildConclusionSynthesisJson(String userJson) {
    final raw = _bridge.aiBuildConclusionSynthesisJson(userJson);
    if (raw != null && raw.isNotEmpty && !raw.startsWith('error:')) {
      return raw;
    }
    return buildConclusionSynthesisBody(userJson);
  }
}
