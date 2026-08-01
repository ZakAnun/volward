import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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

  static bool invalidatesPrefix({
    required String cachedPath,
    required int cachedVersion,
    required String affectedPrefix,
    required int updateVersion,
  }) {
    final matchesPrefix =
        cachedPath == affectedPrefix ||
        cachedPath.startsWith('$affectedPrefix/');
    return matchesPrefix && cachedVersion <= updateVersion;
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
          ScanTreeBuilder.normalizeRoot(manifest['root']?.toString() ?? '') ==
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
      final header = _readManifestHeader(file);
      final root = _extractJsonStringField(header, 'root');
      final snapshotPath = _extractJsonStringField(header, 'snapshot_path');
      final scannedAt = _extractJsonIntField(header, 'scanned_at_ms');
      if (root != null || snapshotPath != null || scannedAt != null) {
        return <String, dynamic>{
          if (root != null) 'root': root,
          if (snapshotPath != null) 'snapshot_path': snapshotPath,
          if (scannedAt != null) 'scanned_at_ms': scannedAt,
        };
      }

      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static String _readManifestHeader(File file) {
    const maxHeaderBytes = 64 * 1024;
    final raf = file.openSync();
    try {
      final size = raf.lengthSync();
      final length = size < maxHeaderBytes ? size : maxHeaderBytes;
      final bytes = raf.readSync(length);
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      raf.closeSync();
    }
  }

  static String? _extractJsonStringField(String jsonHeader, String field) {
    final pattern = RegExp('"$field"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"');
    final match = pattern.firstMatch(jsonHeader);
    if (match == null) return null;
    try {
      return jsonDecode('"${match.group(1)}"') as String?;
    } catch (_) {
      return match.group(1);
    }
  }

  static int? _extractJsonIntField(String jsonHeader, String field) {
    final pattern = RegExp('"$field"\\s*:\\s*(\\d+)');
    final match = pattern.firstMatch(jsonHeader);
    return int.tryParse(match?.group(1) ?? '');
  }

  static String? _resolveSnapshotPath(
    String manifestFilePath,
    Map<String, dynamic> manifest,
  ) {
    final explicit = manifest['snapshot_path']?.toString();
    if (explicit != null &&
        explicit.isNotEmpty &&
        File(explicit).existsSync()) {
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
