import 'ai_provider.dart';
import 'coverage_models.dart';

/// Shared DeepSeek analyze contract (request/parse/batch/endpoint).
///
/// Production supplies an FFI adapter. Tests inject a fake.
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

  String buildConclusionSynthesisJson(String userJson) {
    throw UnimplementedError('conclusion synthesis contract unavailable');
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
