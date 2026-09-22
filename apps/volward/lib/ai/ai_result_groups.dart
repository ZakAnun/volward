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
  int unanalyzedCount = 0;

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
      case 'unanalyzed':
        unanalyzedCount++;
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

  final groups = builders.values.map((builder) => builder.build()).toList()
    ..sort(_compareAiResultGroups);
  return groups;
}

/// Scan root's immediate child directory for [path], or [rootPath] itself when
/// [path] is a direct file under the root.
String? firstLevelDirectoryUnderRoot(String path, String rootPath) {
  final normalizedRoot = normalizeFsPath(rootPath);
  if (normalizedRoot.isEmpty) return null;
  final normalizedPath = normalizeFsPath(path);
  if (!_isWithinRoot(normalizedPath, normalizedRoot)) return null;
  if (normalizedPath == normalizedRoot) return normalizedRoot;
  final relativePath = normalizedRoot == '/'
      ? normalizedPath.substring(1)
      : normalizedRoot.endsWith('/')
      ? normalizedPath.substring(normalizedRoot.length)
      : normalizedPath.substring(normalizedRoot.length + 1);
  if (relativePath.isEmpty) return normalizedRoot;
  final separator = relativePath.indexOf('/');
  if (separator == -1) {
    return normalizedRoot;
  }
  final firstSegment = relativePath.substring(0, separator);
  if (firstSegment.isEmpty) return normalizedRoot;
  return joinFsPath(normalizedRoot, firstSegment);
}

int _compareAiResultGroups(AiResultGroup a, AiResultGroup b) {
  final reviewDiff = b.reviewCount.compareTo(a.reviewCount);
  if (reviewDiff != 0) return reviewDiff;
  final sizeDiff = b.totalBytes.compareTo(a.totalBytes);
  if (sizeDiff != 0) return sizeDiff;
  return a.path.compareTo(b.path);
}

/// Ensures every first-level directory under [rootPath] has a group row (even
/// when all verdicts are `keep` and would otherwise be omitted from the list).
List<AiResultGroup> ensureFirstLevelDirectoryGroups(
  List<AiResultGroup> groups,
  String rootPath,
  Iterable<String> firstLevelDirectoryPaths,
) {
  final normalizedRoot = normalizeFsPath(rootPath);
  if (normalizedRoot.isEmpty) return groups;
  final byPath = {for (final group in groups) group.path: group};
  for (final raw in firstLevelDirectoryPaths) {
    final path = normalizeFsPath(raw);
    if (path == normalizedRoot) continue;
    if (!isUnderFsRoot(path, normalizedRoot)) continue;
    byPath.putIfAbsent(
      path,
      () => AiResultGroup._(
        path: path,
        items: const [],
        totalBytes: 0,
        safeCount: 0,
        reviewCount: 0,
        keepCount: 0,
      ),
    );
  }
  final out = byPath.values.toList()..sort(_compareAiResultGroups);
  return out;
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
