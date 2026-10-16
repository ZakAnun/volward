import 'dart:io';

/// In-memory cache of native candidate build results keyed by [snapshotId].
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

  String? peekRaw(String snapshotId) {
    final raw = _rawBySnapshot[snapshotId];
    if (raw == null) return null;
    final path = _spillPathOf(raw);
    if (path != null && !File(path).existsSync()) {
      _rawBySnapshot.remove(snapshotId);
      return null;
    }
    return raw;
  }

  void putRaw(String snapshotId, String raw) {
    if (raw.isEmpty || raw.startsWith('error:')) return;
    final previous = _rawBySnapshot[snapshotId];
    _rawBySnapshot[snapshotId] = raw;
    if (previous != null && previous != raw) _deleteSpill(previous);
  }

  void clear(String snapshotId) {
    final previous = _rawBySnapshot.remove(snapshotId);
    if (previous != null) _deleteSpill(previous);
  }

  /// Returns cached raw payload or runs [load] once per snapshot in flight.
  Future<String?> loadOrReuse(
    String snapshotId,
    Future<String?> Function() load,
  ) {
    final cached = peekRaw(snapshotId);
    if (cached != null) {
      return Future<String?>.value(cached);
    }
    final existing = _inFlight[snapshotId];
    if (existing != null) return existing;
    final future = load();
    _inFlight[snapshotId] = future;
    return future.whenComplete(() => _inFlight.remove(snapshotId)).then((raw) {
      if (raw != null && raw.isNotEmpty) {
        putRaw(snapshotId, raw);
      }
      return raw;
    });
  }

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
