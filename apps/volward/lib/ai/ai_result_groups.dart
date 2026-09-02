import '../scan_tree.dart';
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
  Map<String, int> sizeByPath, {
  String rootPath = '',
  Set<String> directoryPaths = const {},
}) {
  final normalizedRoot = normalizeFsPath(rootPath);
  final normalizedDirectoryPaths = directoryPaths
      .map(normalizeFsPath)
      .map(_pathKey)
      .toSet();
  final builders = <String, _GroupBuilder>{};
  for (final verdict in verdicts) {
    final groupPath = _groupDirectory(
      verdict.path,
      rootPath: normalizedRoot,
      directoryPaths: normalizedDirectoryPaths,
    );
    final builder = builders.putIfAbsent(
      groupPath,
      () => _GroupBuilder(groupPath),
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

String _groupDirectory(
  String path, {
  String rootPath = '',
  Set<String> directoryPaths = const {},
}) {
  final normalizedRoot = normalizeFsPath(rootPath);
  final normalizedPath = normalizeFsPath(path);
  if (normalizedRoot.isNotEmpty &&
      _isWithinRoot(normalizedPath, normalizedRoot)) {
    if (normalizedPath == normalizedRoot) return normalizedRoot;
    final relativePath = normalizedRoot == '/'
        ? normalizedPath.substring(1)
        : normalizedRoot.endsWith('/')
        ? normalizedPath.substring(normalizedRoot.length)
        : normalizedPath.substring(normalizedRoot.length + 1);
    final separator = relativePath.indexOf('/');
    if (separator == -1 && !directoryPaths.contains(_pathKey(normalizedPath))) {
      return normalizedRoot;
    }
    final firstDirectory = separator == -1
        ? relativePath
        : relativePath.substring(0, separator);
    return joinFsPath(normalizedRoot, firstDirectory);
  }

  return _fallbackGroupDirectory(normalizedPath);
}

String _fallbackGroupDirectory(String path) {
  final parent = parentFsPath(path);
  if (parent == '/' || parent.isEmpty) return parent;
  final secondary = parentFsPath(parent);
  return secondary == '/' ? parent : secondary;
}

String _pathKey(String path) {
  final normalized = normalizeFsPath(path);
  final windowsStyle =
      (normalized.length >= 3 && normalized.codeUnitAt(1) == 58) ||
      normalized.startsWith('//');
  return windowsStyle ? normalized.toLowerCase() : normalized;
}

bool _isWithinRoot(String path, String root) {
  return isUnderFsRoot(path, root);
}
