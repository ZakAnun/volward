import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'scan_tree.dart';

/// Reads scan manifests / snapshots persisted by the Rust orchestrator.
abstract final class SnapshotCache {
  /// Overrides cache root in tests.
  @visibleForTesting
  static Directory? cacheDirForTest;

  static Directory cacheDir() {
    if (cacheDirForTest != null) return cacheDirForTest!;
    final override = Platform.environment['VOLWARD_CACHE_DIR'];
    if (override != null && override.isNotEmpty) {
      return Directory(override);
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return Directory('$home/Library/Application Support/Volward');
    }
    return Directory('${Directory.systemTemp.path}/volward');
  }

  /// Returns the newest on-disk snapshot file path, if any.
  static Future<String?> latestSnapshotPath({String? preferredRoot}) async {
    final manifestsDir = Directory('${cacheDir().path}/manifests');
    if (!await manifestsDir.exists()) return null;

    final preferred = preferredRoot != null
        ? ScanTreeBuilder.normalizeRoot(preferredRoot)
        : null;

    String? bestPath;
    var bestTime = -1;
    String? preferredPath;
    var preferredTime = -1;

    await for (final entity in manifestsDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final manifest = _readManifest(entity);
      if (manifest == null) continue;

      final snapshotPath = _resolveSnapshotPath(entity.path, manifest);
      if (snapshotPath == null) continue;

      final scannedAt = (manifest['scanned_at_ms'] as num?)?.toInt() ?? 0;
      if (scannedAt > bestTime) {
        bestTime = scannedAt;
        bestPath = snapshotPath;
      }

      if (preferred != null &&
          ScanTreeBuilder.normalizeRoot(
                manifest['root']?.toString() ?? '',
              ) ==
              preferred &&
          scannedAt > preferredTime) {
        preferredTime = scannedAt;
        preferredPath = snapshotPath;
      }
    }

    return preferredPath ?? bestPath;
  }

  static Map<String, dynamic>? _readManifest(File file) {
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static String? _resolveSnapshotPath(
    String manifestFilePath,
    Map<String, dynamic> manifest,
  ) {
    final explicit = manifest['snapshot_path']?.toString();
    if (explicit != null && explicit.isNotEmpty && File(explicit).existsSync()) {
      return explicit;
    }

    final hash = manifestFilePath
        .split(Platform.pathSeparator)
        .last
        .replaceFirst('.json', '');
    final fallback = File('${cacheDir().path}/snapshots/$hash.json');
    if (fallback.existsSync()) return fallback.path;
    return null;
  }
}
