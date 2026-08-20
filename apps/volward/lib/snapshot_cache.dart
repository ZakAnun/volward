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
    return cacheDirForPlatform(
      environment: Platform.environment,
      isMacOS: Platform.isMacOS,
      isWindows: Platform.isWindows,
      isLinux: Platform.isLinux,
      systemTempPath: Directory.systemTemp.path,
    );
  }

  @visibleForTesting
  static Directory cacheDirForPlatform({
    required Map<String, String> environment,
    required bool isMacOS,
    required bool isWindows,
    required bool isLinux,
    required String systemTempPath,
  }) {
    final override = environment['VOLWARD_CACHE_DIR'];
    if (override != null && override.isNotEmpty) {
      return Directory(override);
    }
    if (isMacOS) {
      final home = environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory(
          _joinPath(home, 'Library/Application Support/Volward'),
        );
      }
    }
    if (isWindows) {
      final appData = environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return Directory(_joinPath(appData, 'Volward', windows: true));
      }
      final localAppData = environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return Directory(_joinPath(localAppData, 'Volward', windows: true));
      }
      final profile = environment['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) {
        return Directory(
          _joinPath(profile, r'AppData\Roaming\Volward', windows: true),
        );
      }
    }
    if (isLinux) {
      final xdgDataHome = environment['XDG_DATA_HOME'];
      if (xdgDataHome != null && xdgDataHome.isNotEmpty) {
        return Directory(_joinPath(xdgDataHome, 'volward'));
      }
      final home = environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory(_joinPath(home, '.local/share/volward'));
      }
    }
    return Directory(_joinPath(systemTempPath, 'volward', windows: isWindows));
  }

  static String _joinPath(String base, String child, {bool windows = false}) {
    final separator = windows ? r'\' : '/';
    if (base.endsWith('/') || base.endsWith(r'\')) return '$base$child';
    return '$base$separator$child';
  }

  static bool invalidatesPrefix({
    required String cachedPath,
    required int cachedVersion,
    required String affectedPrefix,
    required int updateVersion,
  }) {
    final matchesPrefix = cachedPath == affectedPrefix ||
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

    if (preferred != null) {
      return preferredPath;
    }
    return bestPath;
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
    final valueStart = _jsonFieldValueStart(jsonHeader, field);
    if (valueStart == null ||
        valueStart >= jsonHeader.length ||
        jsonHeader.codeUnitAt(valueStart) != 0x22) {
      return null;
    }
    var escaped = false;
    for (var index = valueStart + 1; index < jsonHeader.length; index++) {
      final code = jsonHeader.codeUnitAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (code == 0x5c) {
        escaped = true;
        continue;
      }
      if (code == 0x22) {
        final raw = jsonHeader.substring(valueStart, index + 1);
        try {
          return jsonDecode(raw) as String?;
        } catch (_) {
          return raw.substring(1, raw.length - 1);
        }
      }
    }
    return null;
  }

  static int? _extractJsonIntField(String jsonHeader, String field) {
    final valueStart = _jsonFieldValueStart(jsonHeader, field);
    if (valueStart == null) return null;
    var end = valueStart;
    while (end < jsonHeader.length) {
      final code = jsonHeader.codeUnitAt(end);
      if (code < 0x30 || code > 0x39) break;
      end++;
    }
    if (end == valueStart) return null;
    return int.tryParse(jsonHeader.substring(valueStart, end));
  }

  static int? _jsonFieldValueStart(String jsonHeader, String field) {
    final key = '"$field"';
    final keyIndex = jsonHeader.indexOf(key);
    if (keyIndex < 0) return null;
    final colonIndex = jsonHeader.indexOf(':', keyIndex + key.length);
    if (colonIndex < 0) return null;
    var valueStart = colonIndex + 1;
    while (valueStart < jsonHeader.length) {
      final code = jsonHeader.codeUnitAt(valueStart);
      if (code != 0x20 && code != 0x09 && code != 0x0a && code != 0x0d) {
        break;
      }
      valueStart++;
    }
    return valueStart;
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
