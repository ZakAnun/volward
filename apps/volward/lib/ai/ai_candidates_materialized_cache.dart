import 'dart:io';

/// In-memory cache of native candidate build results keyed by owner and
/// [snapshotId]. Callers that omit [ownerId] keep the legacy snapshot-only key.
///
/// Survives Platform ↔ BYOK gateway swaps; cleared when the snapshot changes.
/// A `spill:<path>` entry owns its temp file: readers must not delete it, and
/// the file is removed when the entry is replaced or cleared.
class AiCandidatesMaterializedCache {
  AiCandidatesMaterializedCache._();

  static final AiCandidatesMaterializedCache instance =
      AiCandidatesMaterializedCache._();

  static const _spillPrefix = 'spill:';

  final Map<String, String> _rawBySnapshot = {};
  final Map<String, Future<String?>> _inFlight = {};

  String? peekRaw(String snapshotId, {String? ownerId}) {
    final key = _cacheKey(snapshotId, ownerId);
    final raw = _rawBySnapshot[key];
    if (raw == null) return null;
    final path = _spillPathOf(raw);
    if (path != null && !File(path).existsSync()) {
      _rawBySnapshot.remove(key);
      return null;
    }
    return raw;
  }

  void putRaw(String snapshotId, String raw, {String? ownerId}) {
    if (raw.isEmpty || raw.startsWith('error:')) return;
    final key = _cacheKey(snapshotId, ownerId);
    final previous = _rawBySnapshot[key];
    _rawBySnapshot[key] = raw;
    if (previous != null && previous != raw) _deleteSpill(previous);
  }

  void clear(String snapshotId, {String? ownerId}) {
    if (ownerId == null) {
      clearSnapshot(snapshotId);
      return;
    }
    final key = _cacheKey(snapshotId, ownerId);
    final previous = _rawBySnapshot.remove(key);
    if (previous != null) _deleteSpill(previous);
  }

  /// Clears the snapshot for every owner, including the legacy bare-snapshot
  /// cache entry.
  void clearSnapshot(String snapshotId) {
    final suffix = ':snapshot:$snapshotId';
    final keys = _rawBySnapshot.keys
        .where((key) => key == snapshotId || key.endsWith(suffix))
        .toList(growable: false);
    for (final key in keys) {
      final previous = _rawBySnapshot.remove(key);
      if (previous != null) _deleteSpill(previous);
    }
  }

  /// Returns cached raw payload or runs [load] once per snapshot in flight.
  Future<String?> loadOrReuse(
    String snapshotId,
    Future<String?> Function() load, {
    String? ownerId,
  }) {
    final key = _cacheKey(snapshotId, ownerId);
    final cached = peekRaw(snapshotId, ownerId: ownerId);
    if (cached != null) {
      return Future<String?>.value(cached);
    }
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final future = load();
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key)).then((raw) {
      if (raw != null && raw.isNotEmpty) {
        putRaw(snapshotId, raw, ownerId: ownerId);
      }
      return raw;
    });
  }

  static String _cacheKey(String snapshotId, String? ownerId) =>
      ownerId == null ? snapshotId : 'owner:$ownerId:snapshot:$snapshotId';

  static String? _spillPathOf(String raw) =>
      raw.startsWith(_spillPrefix) ? raw.substring(_spillPrefix.length) : null;

  static void _deleteSpill(String raw) {
    final path = _spillPathOf(raw);
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Temp dir cleanup is best-effort.
    }
  }
}
