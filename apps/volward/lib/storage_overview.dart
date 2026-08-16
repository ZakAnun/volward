import 'dart:math' as math;

import 'scan_tree.dart';

int? _intValue(Object? value) =>
    value is num && value.isFinite ? value.toInt() : null;

String? _requiredString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : value;
}

enum StorageDataFreshness { live, cached, unavailable }

enum StorageLocationKind {
  home,
  applications,
  downloads,
  documents,
  volume,
  custom;

  static StorageLocationKind fromWire(Object? value) {
    return StorageLocationKind.values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => StorageLocationKind.custom,
    );
  }
}

class StorageVolumeInfo {
  const StorageVolumeInfo({
    required this.id,
    required this.name,
    required this.rootPath,
    required this.totalBytes,
    required this.availableBytes,
    required this.freshness,
  });

  final String id;
  final String name;
  final String rootPath;
  final int? totalBytes;
  final int? availableBytes;
  final StorageDataFreshness freshness;

  int? get usedBytes {
    final total = totalBytes;
    final available = availableBytes;
    if (total == null || available == null || total <= 0 || available < 0) {
      return null;
    }
    return (total - available).clamp(0, total);
  }

  double? get usedFraction {
    final total = totalBytes;
    final used = usedBytes;
    if (total == null || used == null || total <= 0) return null;
    return (used / total).clamp(0, 1).toDouble();
  }

  static StorageVolumeInfo? fromChannel(Map<Object?, Object?> raw) {
    final id = _requiredString(raw['id']);
    final rootPath = _requiredString(raw['rootPath']);
    if (id == null || rootPath == null) return null;
    final total = _intValue(raw['totalBytes']);
    final available = _intValue(raw['availableBytes']);
    final validCapacity =
        total != null && total > 0 && available != null && available >= 0;
    return StorageVolumeInfo(
      id: id,
      name: raw['name']?.toString().trim().isNotEmpty == true
          ? raw['name'].toString()
          : rootPath,
      rootPath: rootPath,
      totalBytes: validCapacity ? total : null,
      availableBytes: validCapacity ? math.min(available, total) : null,
      freshness: StorageDataFreshness.live,
    );
  }
}

class StorageLocationInfo {
  const StorageLocationInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.kind,
    required this.volumeId,
  });

  final String id;
  final String name;
  final String path;
  final StorageLocationKind kind;
  final String volumeId;

  static StorageLocationInfo? fromChannel(Map<Object?, Object?> raw) {
    final id = _requiredString(raw['id']);
    final path = _requiredString(raw['path']);
    final volumeId = _requiredString(raw['volumeId']);
    if (id == null || path == null || volumeId == null) return null;
    return StorageLocationInfo(
      id: id,
      name: raw['name']?.toString() ?? '',
      path: path,
      kind: StorageLocationKind.fromWire(raw['kind']),
      volumeId: volumeId,
    );
  }
}

class StorageOverviewData {
  StorageOverviewData({
    required List<StorageVolumeInfo> volumes,
    required List<StorageLocationInfo> locations,
    this.selectedVolumeId,
    this.loading = false,
    this.errorCode,
  })  : volumes = List<StorageVolumeInfo>.unmodifiable(volumes),
        locations = List<StorageLocationInfo>.unmodifiable(locations);

  const StorageOverviewData._({
    required this.volumes,
    required this.locations,
    this.selectedVolumeId,
    this.loading = false,
    this.errorCode,
  });

  const StorageOverviewData.loading()
      : this._(
          volumes: const <StorageVolumeInfo>[],
          locations: const <StorageLocationInfo>[],
          selectedVolumeId: null,
          loading: true,
          errorCode: null,
        );

  const StorageOverviewData.unavailable([String? errorCode])
      : this._(
          volumes: const <StorageVolumeInfo>[],
          locations: const <StorageLocationInfo>[],
          selectedVolumeId: null,
          loading: false,
          errorCode: errorCode,
        );

  final List<StorageVolumeInfo> volumes;
  final List<StorageLocationInfo> locations;
  final String? selectedVolumeId;
  final bool loading;
  final String? errorCode;

  StorageVolumeInfo? get selectedVolume {
    for (final volume in volumes) {
      if (volume.id == selectedVolumeId) return volume;
    }
    return volumes.isEmpty ? null : volumes.first;
  }

  StorageVolumeInfo? volumeForPath(String path) {
    final normalized = ScanTreeBuilder.normalizeRoot(path);
    final candidates = volumes.where((volume) {
      final root = ScanTreeBuilder.normalizeRoot(volume.rootPath);
      return isUnderFsRoot(normalized, root);
    }).toList()
      ..sort((a, b) {
        final aRoot = ScanTreeBuilder.normalizeRoot(a.rootPath);
        final bRoot = ScanTreeBuilder.normalizeRoot(b.rootPath);
        return bRoot.length.compareTo(aRoot.length);
      });
    return candidates.isEmpty ? selectedVolume : candidates.first;
  }

  factory StorageOverviewData.fromChannel(Map<Object?, Object?> raw) {
    final rawVolumes = raw['volumes'];
    final rawLocations = raw['locations'];
    final volumes = (rawVolumes is List ? rawVolumes : const <Object?>[])
        .whereType<Map>()
        .map((item) => Map<Object?, Object?>.from(item))
        .map(StorageVolumeInfo.fromChannel)
        .whereType<StorageVolumeInfo>()
        .toList(growable: false);
    final volumeIds = volumes.map((volume) => volume.id).toSet();
    final locations = (rawLocations is List ? rawLocations : const <Object?>[])
        .whereType<Map>()
        .map((item) => Map<Object?, Object?>.from(item))
        .map(StorageLocationInfo.fromChannel)
        .whereType<StorageLocationInfo>()
        .where((location) => volumeIds.contains(location.volumeId))
        .toList(growable: false);
    return StorageOverviewData(
      volumes: volumes,
      locations: locations,
      selectedVolumeId: raw['selectedVolumeId']?.toString(),
    );
  }
}
