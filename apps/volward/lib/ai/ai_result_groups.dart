import 'dart:collection';
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
    required this.localSafeCount,
    required this.aiSafeCount,
    required this.localKeepCount,
    required this.aiKeepCount,
  });

  final String path;
  final List<AiVerdict> items;
  final int totalBytes;
  final int safeCount;
  final int reviewCount;
  final int keepCount;
  final int localSafeCount;
  final int aiSafeCount;
  final int localKeepCount;
  final int aiKeepCount;
}

class _GroupBuilder {
  _GroupBuilder(this.path);

  final String path;
  final List<AiVerdict> items = <AiVerdict>[];
  int totalBytes = 0;
  int safeCount = 0;
  int reviewCount = 0;
  int keepCount = 0;
  int localSafeCount = 0;
  int aiSafeCount = 0;
  int localKeepCount = 0;
  int aiKeepCount = 0;
  int unanalyzedCount = 0;

  void add(AiVerdict item, int bytes) {
    items.add(item);
    totalBytes += bytes;
    switch (item.verdict) {
      case 'safe_to_remove':
        safeCount++;
        if (isLocalRuleVerdict(item)) {
          localSafeCount++;
        } else {
          aiSafeCount++;
        }
        break;
      case 'review_needed':
        reviewCount++;
        break;
      case 'unanalyzed':
        unanalyzedCount++;
        break;
      default:
        keepCount++;
        if (item.verdict == 'keep') {
          if (isLocalRuleVerdict(item)) {
            localKeepCount++;
          } else {
            aiKeepCount++;
          }
        }
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
      localSafeCount: localSafeCount,
      aiSafeCount: aiSafeCount,
      localKeepCount: localKeepCount,
      aiKeepCount: aiKeepCount,
    );
  }
}

extension AiResultGroupDisplayCap on AiResultGroup {
  /// Keeps aggregate counts but limits in-memory items for UI list work.
  AiResultGroup withDisplayItemCap(int maxItems, Map<String, int> sizeByPath) {
    if (maxItems <= 0 || items.length <= maxItems) return this;
    final ranked = [...items]
      ..sort((a, b) {
        final sizeOrder = (sizeByPath[b.path] ?? 0).compareTo(
          sizeByPath[a.path] ?? 0,
        );
        if (sizeOrder != 0) return sizeOrder;
        return a.path.compareTo(b.path);
      });
    return AiResultGroup._(
      path: path,
      items: List.unmodifiable(ranked.take(maxItems).toList(growable: false)),
      totalBytes: totalBytes,
      safeCount: safeCount,
      reviewCount: reviewCount,
      keepCount: keepCount,
      localSafeCount: localSafeCount,
      aiSafeCount: aiSafeCount,
      localKeepCount: localKeepCount,
      aiKeepCount: aiKeepCount,
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

List<AiResultGroup> mergeUnanalyzedGroups(
  List<AiResultGroup> classified,
  List<AiResultGroup> pending,
) {
  final groups = {for (final group in classified) group.path: group};
  for (final group in pending) {
    final base = groups[group.path];
    groups[group.path] = base == null
        ? group
        : AiResultGroup._(
            path: base.path,
            items: _JoinedVerdicts(base.items, group.items),
            totalBytes: base.totalBytes + group.totalBytes,
            safeCount: base.safeCount,
            reviewCount: base.reviewCount,
            keepCount: base.keepCount,
            localSafeCount: base.localSafeCount,
            aiSafeCount: base.aiSafeCount,
            localKeepCount: base.localKeepCount,
            aiKeepCount: base.aiKeepCount,
          );
  }
  return groups.values.toList()..sort(_compareAiResultGroups);
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
        localSafeCount: 0,
        aiSafeCount: 0,
        localKeepCount: 0,
        aiKeepCount: 0,
      ),
    );
  }
  final out = byPath.values.toList()..sort(_compareAiResultGroups);
  return out;
}

bool isLocalRuleVerdict(AiVerdict verdict) =>
    verdict.classificationSource?.startsWith('local:') ?? false;

/// Caps each group's [AiResultGroup.items] for UI while preserving counts.
List<AiResultGroup> capAiResultGroupsForDisplay(
  List<AiResultGroup> groups,
  Map<String, int> sizeByPath, {
  int maxItemsPerGroup = 512,
}) {
  return groups
      .map((g) => g.withDisplayItemCap(maxItemsPerGroup, sizeByPath))
      .toList(growable: false);
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

class _JoinedVerdicts extends ListBase<AiVerdict> {
  _JoinedVerdicts(this.classified, this.pending);
  final List<AiVerdict> classified;
  final List<AiVerdict> pending;

  @override
  int get length => classified.length + pending.length;
  @override
  set length(int value) => throw UnsupportedError('Immutable result group');

  @override
  void operator []=(int index, AiVerdict value) =>
      throw UnsupportedError('Immutable result group');

  @override
  AiVerdict operator [](int index) => index < classified.length
      ? classified[index]
      : pending[index - classified.length];
}

List<AiVerdict> classifiedVerdictsForGroups(
  List<AiVerdict> verdicts,
  List<Map<String, dynamic>> preClassified,
) {
  final localSafe = _preClassifiedVerdicts(preClassified, true);
  final localKeep = _preClassifiedVerdicts(preClassified, false);
  final aiSafe = verdicts
      .where((verdict) => verdict.verdict == 'safe_to_remove')
      .toList();
  final aiPaths = verdicts.map((verdict) => verdict.path).toSet();
  return [
    ...localSafe.where((verdict) => !aiPaths.contains(verdict.path)),
    ...aiSafe,
    ...localKeep,
    ...verdicts.where((verdict) => verdict.verdict == 'review_needed'),
    ...verdicts.where((verdict) => verdict.verdict == 'keep'),
  ];
}

List<AiVerdict> _preClassifiedVerdicts(
  List<Map<String, dynamic>> preClassified,
  bool deletable,
) {
  final items = <AiVerdict>[];
  for (final entry in preClassified) {
    if ((entry['deletable'] == true) != deletable) continue;
    final path = entry['path'] as String? ?? '';
    if (path.isEmpty) continue;
    items.add(
      AiVerdict(
        path: path,
        verdict: deletable ? 'safe_to_remove' : 'keep',
        confidence: entry['confidence']?.toString() ?? 'high',
        reason: entry['reason']?.toString() ?? '',
        classificationSource: 'local:bootstrap',
      ),
    );
  }
  return items;
}
