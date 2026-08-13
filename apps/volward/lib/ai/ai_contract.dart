import 'ai_provider.dart';
import '../volward_session.dart';

/// Shared DeepSeek analyze contract (request/parse/batch/endpoint).
///
/// Production uses [SessionAiContract] over FFI. Tests inject a fake.
abstract class AiContract {
  String upstreamEndpoint();
  int batchSize();
  String buildRequestJson(List<AiCandidate> batch);
  List<AiVerdict> parseResponseJson(String body, List<AiCandidate> batch);
}

Map<String, dynamic> analyzeCandidateMap(AiCandidate c) => {
  'path': c.path,
  'size_bytes': c.sizeBytes,
  'is_dir': c.isDir,
  if (c.childCount != null) 'child_count': c.childCount,
  if (c.extension != null) 'extension': c.extension,
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
}
