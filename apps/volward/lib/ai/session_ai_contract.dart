import '../volward_session.dart';
import 'ai_contract_api.dart';
import 'ai_conclusion_synthesis_body.dart';
import 'ai_provider.dart';
import 'coverage_models.dart';

/// FFI-backed contract. Throws `ai_contract_unavailable` if symbols are missing.
class SessionAiContract implements AiContract {
  SessionAiContract(this._session) {
    if (!_session.hasAiContractApi) {
      throw Exception('ai_contract_unavailable');
    }
  }

  final VolwardSession _session;

  /// Compatibility path for callers that have no injected contract.
  static SessionAiContract? forCurrentSession() {
    final session = VolwardSession.instance;
    return session == null ? null : SessionAiContract(session);
  }

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

  @override
  String buildConclusionSynthesisJson(String userJson) {
    final raw = _session.aiBuildConclusionSynthesisJson(userJson);
    if (raw != null && raw.isNotEmpty && !raw.startsWith('error:')) {
      return raw;
    }
    return buildConclusionSynthesisBody(userJson);
  }
}
