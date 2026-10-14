import 'dart:convert';

/// Keep in sync with `crates/volward-ai` (`MODEL`, `TEMPERATURE`, etc.).
const _kConclusionModel = 'deepseek-v4-flash';
const _kConclusionTemperature = 0.0;
const _kConclusionMaxOutputTokens = 8192;
const _kConclusionThinkingDisabled = true;

/// System prompt for post-analysis conclusion narrative synthesis (Stage B).
const _kConclusionSynthesisPrompt =
    r'''You are a conclusion organizer (整理员). You receive JSON summarizing an already-completed disk cleanup AI analysis.
Your job is to weave the provided statistics and reason_highlights into a short narrative for the user.

Rules:
- Use ONLY numbers, counts, byte totals, percentages, labels, and reason_highlights present in the JSON.
- Do NOT introduce new file paths, folders, verdicts, or cleanup actions not implied by the JSON.
- Do NOT re-classify items or change safe/review/keep judgments.
- Write 2–4 sentences of plain text (no JSON, no markdown, no bullet lists).
- Match the language of reason_highlights when possible.

Respond with plain text only.
''';

/// Build DeepSeek Chat Completions request body for conclusion synthesis.
String buildConclusionSynthesisBody(String userJson) {
  final thinking = _kConclusionThinkingDisabled
      ? {'type': 'disabled'}
      : {'type': 'enabled'};
  final body = {
    'model': _kConclusionModel,
    'temperature': _kConclusionTemperature,
    'max_tokens': _kConclusionMaxOutputTokens,
    'thinking': thinking,
    'messages': [
      {'role': 'system', 'content': _kConclusionSynthesisPrompt},
      {'role': 'user', 'content': userJson},
    ],
  };
  return jsonEncode(body);
}
