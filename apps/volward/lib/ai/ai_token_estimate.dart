import 'ai_provider.dart';

/// Keep in sync with `volward_core::DEFAULT_CANDIDATE_CAP`.
const kDefaultAiCandidateCap = 150;

/// Keep in sync with `volward_core::BYOK_ANALYZE_BATCH_SIZE`.
const kByokAnalyzeBatchSize = 40;

int estimateCandidateInputTokens(Iterable<AiCandidate> candidates) {
  const basePromptTokens = 320;
  return candidates.fold(basePromptTokens, (total, candidate) {
    final pathTokens = (candidate.path.length ~/ 4).clamp(8, 1 << 30);
    final hint = candidate.cleanupHint;
    final hintTokens = hint == null ? 0 : hint.length ~/ 4;
    return total + 24 + pathTokens + hintTokens;
  });
}

int estimateByokBatchInputTokens(List<AiCandidate> candidates, int batchSize) {
  if (candidates.isEmpty || batchSize <= 0) return 0;
  final end = candidates.length < batchSize ? candidates.length : batchSize;
  return estimateCandidateInputTokens(candidates.take(end));
}

int estimateByokTotalInputTokens(List<AiCandidate> candidates, int batchSize) {
  if (candidates.isEmpty || batchSize <= 0) return 0;
  var total = 0;
  for (var i = 0; i < candidates.length; i += batchSize) {
    final end = i + batchSize < candidates.length
        ? i + batchSize
        : candidates.length;
    total += estimateCandidateInputTokens(candidates.sublist(i, end));
  }
  return total;
}
