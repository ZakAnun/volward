import 'ai_provider.dart';
import 'ai_result_groups.dart';
import '../scan_tree.dart';

/// One first-level directory (or scan root) rollup for the conclusions page.
class AiDirectoryConclusion {
  const AiDirectoryConclusion({
    required this.path,
    required this.displayLabel,
    required this.safeBytes,
    required this.reviewCount,
    required this.keepCount,
    required this.shareOfSafePct,
    required this.reasonHighlights,
  });

  final String path;
  final String displayLabel;
  final int safeBytes;
  final int reviewCount;
  final int keepCount;

  /// Share of total reclaimable bytes across all directories (0–100).
  final double shareOfSafePct;
  final List<String> reasonHighlights;
}

/// Deterministic rollup shown before the full results list (P1).
class AiAnalysisConclusionOverview {
  const AiAnalysisConclusionOverview({
    required this.targetLabel,
    required this.rootPath,
    required this.safeBytes,
    required this.reviewCount,
    required this.keepCount,
    required this.analyzedItemCount,
    required this.analyzedTotalBytes,
    required this.rootSizeBytes,
    required this.shareOfRootPct,
    required this.truncated,
    required this.fullCoverage,
    required this.directories,
  });

  final String targetLabel;
  final String rootPath;
  final int safeBytes;
  final int reviewCount;
  final int keepCount;
  final int analyzedItemCount;
  final int analyzedTotalBytes;

  /// Scan root size when known; otherwise sum of sized verdict paths.
  final int rootSizeBytes;

  /// [safeBytes] / [rootSizeBytes] when denominator &gt; 0.
  final double? shareOfRootPct;
  final bool truncated;
  final bool fullCoverage;
  final List<AiDirectoryConclusion> directories;
}

class AiResultOverviewBuildInput {
  const AiResultOverviewBuildInput({
    required this.targetLabel,
    required this.rootPath,
    required this.verdicts,
    required this.sizeByPath,
    this.rootSizeBytesHint,
    this.truncated = false,
    this.fullCoverage = false,
    this.maxDirectories = 8,
    this.isPendingReview,
    this.analyzedItemCountOverride,
    this.analyzedTotalBytesOverride,
  });

  final String targetLabel;
  final String rootPath;
  final Iterable<AiVerdict> verdicts;
  final Map<String, int> sizeByPath;
  final int? rootSizeBytesHint;
  final bool truncated;
  final bool fullCoverage;
  final int maxDirectories;
  final bool Function(AiVerdict verdict)? isPendingReview;
  final int? analyzedItemCountOverride;
  final int? analyzedTotalBytesOverride;
}

int estimateGroupSafeBytes(AiResultGroup group, Map<String, int> sizeByPath) {
  var fromItems = 0;
  var visibleSafe = 0;
  for (final item in group.items) {
    if (item.verdict != 'safe_to_remove') continue;
    visibleSafe++;
    fromItems += sizeByPath[item.path] ?? 0;
  }
  if (group.safeCount <= 0) return 0;
  if (visibleSafe >= group.safeCount) return fromItems;
  if (visibleSafe > 0) {
    return (fromItems * group.safeCount / visibleSafe).round();
  }
  final classified = group.safeCount + group.reviewCount + group.keepCount;
  if (classified <= 0 || group.totalBytes <= 0) return 0;
  return (group.totalBytes * group.safeCount / classified).round();
}

/// Rollup from pre-grouped results (accurate counts without materializing every item).
AiAnalysisConclusionOverview buildAiAnalysisConclusionOverviewFromGroups(
  AiResultOverviewBuildInput input,
  Iterable<AiResultGroup> groups,
) {
  final normalizedRoot = normalizeFsPath(input.rootPath);
  final pendingReview = input.isPendingReview ?? (_) => true;
  var safeBytes = 0;
  var reviewCount = 0;
  var keepCount = 0;
  var analyzedTotalBytes = 0;
  var analyzedItemCount = 0;
  final directoryRows = <AiDirectoryConclusion>[];

  for (final group in groups) {
    final dirSafeBytes = estimateGroupSafeBytes(group, input.sizeByPath);
    safeBytes += dirSafeBytes;
    var dirReview = 0;
    for (final item in group.items) {
      if (item.verdict == 'review_needed' && pendingReview(item)) {
        dirReview++;
      }
    }
    reviewCount += dirReview;
    keepCount += group.keepCount;
    analyzedTotalBytes += group.totalBytes;
    analyzedItemCount += group.safeCount + group.reviewCount + group.keepCount;

    directoryRows.add(
      AiDirectoryConclusion(
        path: group.path,
        displayLabel: _displayLabelFor(
          group.path,
          normalizedRoot,
          input.targetLabel,
        ),
        safeBytes: dirSafeBytes,
        reviewCount: dirReview,
        keepCount: group.keepCount,
        shareOfSafePct: 0,
        reasonHighlights: extractReasonHighlights(
          group.items,
          input.sizeByPath,
        ),
      ),
    );
  }

  if (input.analyzedItemCountOverride != null &&
      input.analyzedItemCountOverride! > analyzedItemCount) {
    analyzedItemCount = input.analyzedItemCountOverride!;
  }
  if (input.analyzedTotalBytesOverride != null &&
      input.analyzedTotalBytesOverride! > analyzedTotalBytes) {
    analyzedTotalBytes = input.analyzedTotalBytesOverride!;
  }

  final directories =
      directoryRows
          .map(
            (dir) => AiDirectoryConclusion(
              path: dir.path,
              displayLabel: dir.displayLabel,
              safeBytes: dir.safeBytes,
              reviewCount: dir.reviewCount,
              keepCount: dir.keepCount,
              shareOfSafePct: safeBytes > 0
                  ? (dir.safeBytes / safeBytes) * 100.0
                  : 0.0,
              reasonHighlights: dir.reasonHighlights,
            ),
          )
          .toList()
        ..sort((a, b) {
          final safeDiff = b.safeBytes.compareTo(a.safeBytes);
          if (safeDiff != 0) return safeDiff;
          final reviewDiff = b.reviewCount.compareTo(a.reviewCount);
          if (reviewDiff != 0) return reviewDiff;
          return a.path.compareTo(b.path);
        });

  final cappedDirs = directories.length > input.maxDirectories
      ? directories.take(input.maxDirectories).toList(growable: false)
      : directories;

  final rootSizeBytes = _resolveRootSizeBytes(
    input.rootSizeBytesHint,
    input.sizeByPath,
    normalizedRoot,
  );
  final shareOfRootPct = rootSizeBytes > 0
      ? (safeBytes / rootSizeBytes) * 100.0
      : null;

  return AiAnalysisConclusionOverview(
    targetLabel: input.targetLabel,
    rootPath: input.rootPath,
    safeBytes: safeBytes,
    reviewCount: reviewCount,
    keepCount: keepCount,
    analyzedItemCount: analyzedItemCount,
    analyzedTotalBytes: analyzedTotalBytes,
    rootSizeBytes: rootSizeBytes,
    shareOfRootPct: shareOfRootPct,
    truncated: input.truncated,
    fullCoverage: input.fullCoverage,
    directories: cappedDirs,
  );
}

/// Builds the conclusions overview from the same verdict set as the detail list.
AiAnalysisConclusionOverview buildAiAnalysisConclusionOverview(
  AiResultOverviewBuildInput input,
) {
  final normalizedRoot = normalizeFsPath(input.rootPath);
  var safeBytes = 0;
  var reviewCount = 0;
  var keepCount = 0;
  var analyzedTotalBytes = 0;
  var analyzedItemCount = 0;
  final pendingReview = input.isPendingReview ?? (_) => true;

  for (final verdict in input.verdicts) {
    if (verdict.verdict == 'unanalyzed') continue;
    analyzedItemCount++;
    final bytes = input.sizeByPath[verdict.path] ?? 0;
    analyzedTotalBytes += bytes;
    switch (verdict.verdict) {
      case 'safe_to_remove':
        safeBytes += bytes;
        break;
      case 'review_needed':
        if (pendingReview(verdict)) reviewCount++;
        break;
      case 'keep':
        keepCount++;
        break;
    }
  }

  final rootSizeBytes = _resolveRootSizeBytes(
    input.rootSizeBytesHint,
    input.sizeByPath,
    normalizedRoot,
  );
  final shareOfRootPct = rootSizeBytes > 0
      ? (safeBytes / rootSizeBytes) * 100.0
      : null;

  final directoryVerdicts = <String, List<AiVerdict>>{};
  for (final verdict in input.verdicts) {
    if (verdict.verdict == 'unanalyzed') continue;
    final bucket = normalizedRoot.isEmpty
        ? _fallbackBucket(verdict.path)
        : (firstLevelDirectoryUnderRoot(verdict.path, normalizedRoot) ??
              normalizedRoot);
    directoryVerdicts.putIfAbsent(bucket, () => <AiVerdict>[]).add(verdict);
  }

  final directories =
      directoryVerdicts.entries.map((entry) {
        final path = entry.key;
        final items = entry.value;
        var dirSafeBytes = 0;
        var dirReview = 0;
        var dirKeep = 0;
        for (final item in items) {
          final bytes = input.sizeByPath[item.path] ?? 0;
          switch (item.verdict) {
            case 'safe_to_remove':
              dirSafeBytes += bytes;
              break;
            case 'review_needed':
              if (pendingReview(item)) dirReview++;
              break;
            case 'keep':
              dirKeep++;
              break;
          }
        }
        final shareOfSafe = safeBytes > 0
            ? (dirSafeBytes / safeBytes) * 100.0
            : 0.0;
        return AiDirectoryConclusion(
          path: path,
          displayLabel: _displayLabelFor(
            path,
            normalizedRoot,
            input.targetLabel,
          ),
          safeBytes: dirSafeBytes,
          reviewCount: dirReview,
          keepCount: dirKeep,
          shareOfSafePct: shareOfSafe,
          reasonHighlights: extractReasonHighlights(items, input.sizeByPath),
        );
      }).toList()..sort((a, b) {
        final safeDiff = b.safeBytes.compareTo(a.safeBytes);
        if (safeDiff != 0) return safeDiff;
        final reviewDiff = b.reviewCount.compareTo(a.reviewCount);
        if (reviewDiff != 0) return reviewDiff;
        return a.path.compareTo(b.path);
      });

  final capped = directories.length > input.maxDirectories
      ? directories.take(input.maxDirectories).toList(growable: false)
      : directories;

  return AiAnalysisConclusionOverview(
    targetLabel: input.targetLabel,
    rootPath: input.rootPath,
    safeBytes: safeBytes,
    reviewCount: reviewCount,
    keepCount: keepCount,
    analyzedItemCount: analyzedItemCount,
    analyzedTotalBytes: analyzedTotalBytes,
    rootSizeBytes: rootSizeBytes,
    shareOfRootPct: shareOfRootPct,
    truncated: input.truncated,
    fullCoverage: input.fullCoverage,
    directories: capped,
  );
}

/// Picks representative [reason] strings from analysis verdicts (no extra AI).
List<String> extractReasonHighlights(
  Iterable<AiVerdict> items,
  Map<String, int> sizeByPath, {
  int maxSafeReasons = 2,
  int maxReviewReasons = 1,
}) {
  final safeItems = items
      .where((v) => v.verdict == 'safe_to_remove' && v.reason.trim().isNotEmpty)
      .toList(growable: false);
  final reviewItems = items
      .where((v) => v.verdict == 'review_needed' && v.reason.trim().isNotEmpty)
      .toList(growable: false);

  final weightByReason = <String, int>{};
  for (final verdict in safeItems) {
    final reason = verdict.reason.trim();
    weightByReason[reason] =
        (weightByReason[reason] ?? 0) + (sizeByPath[verdict.path] ?? 0);
  }
  final rankedSafe = weightByReason.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final highlights = <String>[
    for (final entry in rankedSafe.take(maxSafeReasons)) entry.key,
  ];

  if (maxReviewReasons > 0 && reviewItems.isNotEmpty) {
    reviewItems.sort(
      (a, b) => (sizeByPath[b.path] ?? 0).compareTo(sizeByPath[a.path] ?? 0),
    );
    final reason = reviewItems.first.reason.trim();
    if (reason.isNotEmpty && !highlights.contains(reason)) {
      highlights.add(reason);
    }
  }

  return highlights;
}

int _resolveRootSizeBytes(
  int? hint,
  Map<String, int> sizeByPath,
  String normalizedRoot,
) {
  if (hint != null && hint > 0) return hint;
  if (normalizedRoot.isEmpty) {
    return sizeByPath.values.fold<int>(0, (sum, value) => sum + value);
  }
  var total = 0;
  for (final entry in sizeByPath.entries) {
    if (isUnderFsRoot(entry.key, normalizedRoot)) {
      total += entry.value;
    }
  }
  return total;
}

String _fallbackBucket(String path) {
  final parent = parentFsPath(normalizeFsPath(path));
  return parent.isEmpty ? normalizeFsPath(path) : parent;
}

String _displayLabelFor(
  String path,
  String normalizedRoot,
  String targetLabel,
) {
  final normalizedPath = normalizeFsPath(path);
  if (normalizedRoot.isNotEmpty && normalizedPath == normalizedRoot) {
    return targetLabel.isNotEmpty ? targetLabel : normalizedPath;
  }
  final segments = normalizedPath.split('/').where((s) => s.isNotEmpty);
  if (segments.isNotEmpty) {
    final base = segments.last;
    if (base.isNotEmpty) return base;
  }
  return targetLabel.isNotEmpty ? targetLabel : normalizedPath;
}
