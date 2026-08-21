import 'dart:math' as math;

import 'scan_snapshot_state.dart';
import 'scan_tree.dart';
import 'storage_overview.dart';

const homeNamedCategoryOrder = ['Cache', 'Temp', 'Media', 'System'];
const homeOtherCategoryName = 'Other';

/// How many "largest items" the summary carries.
///
/// The dashboard renders fewer than this (see `_largestItemCount` in
/// `storage_steward_home.dart`); the extra rows are headroom for a caller that
/// wants a longer list, not rows anyone is expected to see today.
const homeLargestItemLimit = 5;

int? _finiteInt(Object? value) {
  return value is num && value.isFinite ? value.toInt() : null;
}

int? _nonNegativeInt(int? value) {
  return value != null && value >= 0 ? value : null;
}

bool _sameFsPath(String left, String right) {
  final normalizedLeft = ScanTreeBuilder.normalizeRoot(left);
  final normalizedRight = ScanTreeBuilder.normalizeRoot(right);
  return isUnderFsRoot(normalizedLeft, normalizedRight) &&
      isUnderFsRoot(normalizedRight, normalizedLeft);
}

bool _isWindowsDrivePath(String path) {
  if (path.length < 3 || path[1] != ':' || path[2] != '/') return false;
  final driveLetter = path.codeUnitAt(0);
  return (driveLetter >= 65 && driveLetter <= 90) ||
      (driveLetter >= 97 && driveLetter <= 122);
}

bool _isWindowsDriveRoot(String path) {
  return path.length == 3 && _isWindowsDrivePath(path);
}

bool _isWindowsStylePath(String path) {
  return _isWindowsDrivePath(path) || path.startsWith('//');
}

bool _hasUsableCapacity(StorageVolumeInfo? volume) {
  final total = volume?.totalBytes;
  final available = volume?.availableBytes;
  return total != null &&
      total > 0 &&
      available != null &&
      available >= 0 &&
      available <= total;
}

bool _volumeContainsPath(StorageVolumeInfo volume, String normalizedPath) {
  final normalizedRoot = ScanTreeBuilder.normalizeRoot(volume.rootPath);
  return isUnderFsRoot(normalizedPath, normalizedRoot);
}

class StorageHomeCategorySummary {
  const StorageHomeCategorySummary({required this.name, required this.count});

  final String name;
  final int count;
}

/// One row in the home dashboard's "largest items" block.
class StorageHomeItem {
  const StorageHomeItem({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.isDirectory,
    required this.scanned,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final bool isDirectory;

  /// False when the size is a partial subtree total the scan has not finished
  /// walking. Callers render such sizes as approximate.
  final bool scanned;
}

class StorageHomeSummary {
  const StorageHomeSummary({
    required this.overview,
    required this.selectedLocation,
    required this.selectedVolume,
    required this.scanning,
    required this.hasCompletedScan,
    this.restoringSnapshot = false,
    this.reclaimableBytes,
    this.lastScannedAtMs,
    this.scanProgress,
    this.scanPhase,
    this.scannedBytes,
    this.categories = const [],
    this.largestItems = const [],
    this.pinnedCustomLocation,
    this.recentCustomLocations = const [],
  });

  final StorageOverviewData overview;
  final StorageLocationInfo? selectedLocation;
  final StorageVolumeInfo? selectedVolume;
  final bool scanning;
  final bool hasCompletedScan;

  /// True while a cached snapshot is being read back from disk.
  ///
  /// Restore also sets [scanning] so the dashboard reads as busy, but there is
  /// no scan to cancel and no progress to report — see [canCancelScan].
  final bool restoringSnapshot;
  final int? reclaimableBytes;
  final int? lastScannedAtMs;
  final double? scanProgress;
  final String? scanPhase;
  final int? scannedBytes;
  final List<StorageHomeCategorySummary> categories;
  final List<StorageHomeItem> largestItems;
  final StorageLocationInfo? pinnedCustomLocation;
  final List<StorageLocationInfo> recentCustomLocations;

  bool get hasUsableCapacity => _hasUsableCapacity(selectedVolume);

  /// Whether the primary action should offer to cancel.
  ///
  /// Guards the one place [scanning] is too broad: during a snapshot restore
  /// the dashboard is busy but nothing is cancellable, so offering "cancel"
  /// there produces a permanently disabled button.
  bool get canCancelScan => scanning && !restoringSnapshot;

  factory StorageHomeSummary.fromInputs({
    required StorageOverviewData overview,
    required String targetPath,
    required bool scanning,
    required double? scanProgress,
    bool restoringSnapshot = false,
    String? scanPhase,
    ScanSnapshotState? matchingSnapshot,
    List<ScanTreeNode> largestItemCandidates = const [],
    StorageLocationInfo? pinnedCustomLocation,
    List<StorageLocationInfo> recentCustomLocations = const [],
  }) {
    final normalizedTarget = targetPath.isEmpty
        ? ''
        : ScanTreeBuilder.normalizeRoot(targetPath);
    final snapshot = matchingSnapshot;
    final snapshotMatches =
        normalizedTarget.isNotEmpty &&
        snapshot != null &&
        _sameFsPath(snapshot.tree?.path ?? '', normalizedTarget);

    StorageLocationInfo? selectedLocation;
    if (normalizedTarget.isNotEmpty) {
      for (final location in overview.locations) {
        if (_sameFsPath(location.path, normalizedTarget)) {
          selectedLocation = location;
          break;
        }
      }
    }

    StorageVolumeInfo? selectedVolume;
    StorageVolumeInfo? volumeById(String? volumeId) {
      if (volumeId == null) return null;
      for (final volume in overview.volumes) {
        if (volume.id == volumeId) return volume;
      }
      return null;
    }

    if (normalizedTarget.isNotEmpty) {
      selectedVolume = volumeById(selectedLocation?.volumeId);
      if (selectedVolume == null) {
        final providerVolume = volumeById(overview.selectedVolumeId);
        if (providerVolume != null &&
            (!_isWindowsStylePath(normalizedTarget) ||
                _volumeContainsPath(providerVolume, normalizedTarget))) {
          selectedVolume = providerVolume;
        }
      }
      if (selectedVolume == null) {
        selectedVolume = overview.volumeForPath(normalizedTarget);
        if (selectedVolume != null &&
            !_volumeContainsPath(selectedVolume, normalizedTarget)) {
          selectedVolume = null;
        }
      }
      selectedLocation ??= StorageLocationInfo(
        id: 'custom:$normalizedTarget',
        name: rootDisplayNameFor(normalizedTarget),
        path: normalizedTarget,
        kind: StorageLocationKind.custom,
        volumeId: selectedVolume?.id ?? '',
      );
    }

    if (!_hasUsableCapacity(selectedVolume) && snapshotMatches) {
      final total = _finiteInt(snapshot.extraFields['volume_total_bytes']);
      final used = _finiteInt(snapshot.extraFields['volume_used_bytes']);
      if (total != null && total > 0 && used != null && used >= 0) {
        final boundedUsed = used.clamp(0, total);
        selectedVolume = StorageVolumeInfo(
          id: 'cached:$normalizedTarget',
          name: rootDisplayNameFor(normalizedTarget),
          rootPath: normalizedTarget,
          totalBytes: total,
          availableBytes: total - boundedUsed,
          freshness: StorageDataFreshness.cached,
        );
      }
    }

    final boundedProgress =
        scanning && scanProgress != null && scanProgress.isFinite
        ? math.min(scanProgress.clamp(0, 1), 0.99).toDouble()
        : null;

    final completedScan =
        snapshotMatches && snapshot.stats['scan_state']?.toString() == 'Done';
    final previewSnapshot =
        snapshotMatches && snapshot.snapshotId.startsWith('preview-');
    var reclaimableBytes = snapshotMatches
        ? _nonNegativeInt(snapshot.reclaimableEstimateBytes)
        : null;
    if (reclaimableBytes == 0 && (previewSnapshot || !completedScan)) {
      reclaimableBytes = null;
    }

    final largestItems = _deriveLargestItems(
      largestItemCandidates,
      snapshotMatches && !previewSnapshot,
    );

    final categories = <StorageHomeCategorySummary>[];
    if (snapshotMatches) {
      final counts = snapshot.categoryCounts;
      var namedSum = 0;
      var leftover = 0;
      for (final name in homeNamedCategoryOrder) {
        final count = counts[name] ?? 0;
        namedSum += count;
        if (count > 0) {
          categories.add(StorageHomeCategorySummary(name: name, count: count));
        }
      }
      for (final entry in counts.entries) {
        if (!homeNamedCategoryOrder.contains(entry.key) && entry.value > 0) {
          leftover += entry.value;
        }
      }
      final filesSeen =
          _nonNegativeInt(_finiteInt(snapshot.stats['files_seen'])) ?? 0;
      final total = [
        filesSeen,
        snapshot.filesInSnapshot,
        namedSum + leftover,
      ].fold<int>(0, math.max);
      if ((completedScan || filesSeen > 0) && total > namedSum) {
        categories.add(
          StorageHomeCategorySummary(
            name: homeOtherCategoryName,
            count: total - namedSum,
          ),
        );
      }
    }

    final treeBytes = snapshotMatches
        ? _nonNegativeInt(snapshot.tree?.sizeBytes)
        : null;
    final scannedBytes = treeBytes == 0 && !completedScan ? null : treeBytes;

    return StorageHomeSummary(
      overview: overview,
      selectedLocation: selectedLocation,
      selectedVolume: selectedVolume,
      scanning: scanning,
      restoringSnapshot: restoringSnapshot,
      hasCompletedScan: completedScan,
      reclaimableBytes: reclaimableBytes,
      lastScannedAtMs: snapshotMatches
          ? _nonNegativeInt(snapshot.scannedAtMs)
          : null,
      scanProgress: boundedProgress,
      scanPhase: scanning ? scanPhase : null,
      scannedBytes: scannedBytes,
      categories: List.unmodifiable(categories),
      largestItems: largestItems,
      pinnedCustomLocation: pinnedCustomLocation,
      recentCustomLocations: List.unmodifiable(recentCustomLocations),
    );
  }
}

String rootDisplayNameFor(String path) {
  final normalized = ScanTreeBuilder.normalizeRoot(path);
  if (normalized == '/' || _isWindowsDriveRoot(normalized)) {
    return normalized;
  }
  return lastPathSegment(normalized);
}

String formatStorageBytes(num? bytes) {
  if (bytes == null) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value.abs() >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || value == value.roundToDouble() ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

List<StorageHomeItem> _deriveLargestItems(
  List<ScanTreeNode> candidates,
  bool authoritative,
) {
  if (!authoritative || candidates.isEmpty) return const <StorageHomeItem>[];
  // `SnapshotQueryResult.directNodes` is `[...dirs, ...files]` — each group is
  // sorted, but there is no ordering across the two. Re-sort before slicing or
  // a 12 GB file renders below an 8 GB directory.
  final sorted = List<ScanTreeNode>.of(candidates)
    ..sort((a, b) => b.displayBytes.compareTo(a.displayBytes));
  return List.unmodifiable(<StorageHomeItem>[
    for (final node in sorted.take(homeLargestItemLimit))
      StorageHomeItem(
        name: node.name,
        path: node.path,
        sizeBytes: node.displayBytes,
        isDirectory: node.isDirectory,
        scanned: node.scanned,
      ),
  ]);
}
