/// In-memory cache of native candidate build results keyed by [snapshotId].
///
/// Survives Platform ↔ BYOK gateway swaps; cleared when the snapshot changes.
class AiCandidatesMaterializedCache {
  AiCandidatesMaterializedCache._();

  static final AiCandidatesMaterializedCache instance =
      AiCandidatesMaterializedCache._();

  final Map<String, String> _rawBySnapshot = {};
  final Map<String, Future<String?>> _inFlight = {};

  String? peekRaw(String snapshotId) => _rawBySnapshot[snapshotId];

  void putRaw(String snapshotId, String raw) {
    if (raw.isEmpty || raw.startsWith('error:')) return;
    _rawBySnapshot[snapshotId] = raw;
  }

  void clear(String snapshotId) => _rawBySnapshot.remove(snapshotId);

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
}
