import 'dart:convert';

/// Extract plain-text narrative from an OpenAI-compatible chat completion body.
String parseCompletionText(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw Exception('api_error:bad_completion');
  }
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty) {
    throw Exception('api_error:bad_completion');
  }
  final choice = choices.first;
  if (choice is! Map) {
    throw Exception('api_error:bad_completion');
  }
  if (choice['finish_reason'] == 'length') {
    throw Exception('api_error:truncated_completion');
  }
  final message = choice['message'];
  if (message is! Map) {
    throw Exception('api_error:bad_completion');
  }
  final content = message['content'];
  if (content is! String) {
    throw Exception('api_error:bad_completion');
  }
  final stripped = _stripMarkdownFence(content);
  if (stripped.trim().isEmpty) {
    throw Exception('api_error:empty_completion');
  }
  return stripped;
}

String _stripMarkdownFence(String text) {
  final trimmed = text.trim();
  if (!trimmed.startsWith('```')) {
    return trimmed;
  }
  final lines = trimmed.split('\n');
  if (lines.length < 3) {
    return trimmed;
  }
  final last = lines.last.trim();
  final end = last == '```' ? lines.length - 1 : lines.length;
  return lines.sublist(1, end).join('\n').trim();
}
