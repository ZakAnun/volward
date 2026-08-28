import 'dart:collection';

import 'ai_provider.dart';

class AiResultGroup {
  const AiResultGroup._({
    required this.path,
    required this.items,
    required this.totalBytes,
    required this.safeCount,
    required this.reviewCount,
    required this.keepCount,
  });

  final String path;
  final List<AiVerdict> items;
  final int totalBytes;
  final int safeCount;
  final int reviewCount;
  final int keepCount;
}

class _GroupBuilder {
  _GroupBuilder(this.path);

  final String path;
  final List<AiVerdict> items = <AiVerdict>[];
  int totalBytes = 0;
  int safeCount = 0;
  int reviewCount = 0;
  int keepCount = 0;

  void add(AiVerdict item, int bytes) {
    items.add(item);
    totalBytes += bytes;
    switch (item.verdict) {
      case 'safe_to_remove':
        safeCount++;
        break;
      case 'review_needed':
        reviewCount++;
        break;
      default:
        keepCount++;
        break;
    }
  }

  AiResultGroup build() {
    return AiResultGroup._(
      path: path,
      items: List.unmodifiable(items),
      totalBytes: totalBytes,
      safeCount: safeCount,
      reviewCount: reviewCount,
      keepCount: keepCount,
    );
  }
}

List<AiResultGroup> groupAiResults(
  Iterable<AiVerdict> verdicts,
  Map<String, int> sizeByPath,
) {
  final builders = LinkedHashMap<String, _GroupBuilder>();
  for (final verdict in verdicts) {
    final parentPath = _parentDirectory(verdict.path);
    final builder = builders.putIfAbsent(
      parentPath,
      () => _GroupBuilder(parentPath),
    );
    builder.add(verdict, sizeByPath[verdict.path] ?? 0);
  }

  final groups = builders.values.map((builder) => builder.build()).toList();
  groups.sort((a, b) {
    final reviewDiff = b.reviewCount.compareTo(a.reviewCount);
    if (reviewDiff != 0) return reviewDiff;
    final sizeDiff = b.totalBytes.compareTo(a.totalBytes);
    if (sizeDiff != 0) return sizeDiff;
    return a.path.compareTo(b.path);
  });
  return groups;
}

String _parentDirectory(String path) {
  if (path.isEmpty) return '';
  var normalized = path;
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  if (normalized == '/') return '/';
  final separator = normalized.lastIndexOf('/');
  if (separator <= 0) return '/';
  return normalized.substring(0, separator);
}
