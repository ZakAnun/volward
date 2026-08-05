import 'snapshot_query.dart';

class SnapshotViewCache<T> {
  SnapshotViewCache({this.capacity = 64}) : assert(capacity > 0);

  final int capacity;
  final _values = <SnapshotQueryKey, T>{};

  T? operator [](SnapshotQueryKey key) {
    final value = _values.remove(key);
    if (value != null) _values[key] = value;
    return value;
  }

  void operator []=(SnapshotQueryKey key, T value) {
    _values.remove(key);
    _values[key] = value;
    while (_values.length > capacity) {
      _values.remove(_values.keys.first);
    }
  }

  /// True when the cache contains an entry for [key].
  bool containsKey(SnapshotQueryKey key) => _values.containsKey(key);

  /// Returns a cached entry without updating the LRU order.
  T? peek(SnapshotQueryKey key) => _values[key];

  /// Returns the most recently inserted entry whose [SnapshotQueryKey.path]
  /// matches [path], ignoring version/snapshotId. Useful as a stale fallback
  /// while an async re-query is in flight (avoids a blank-frame flicker).
  T? latestForPath(String path) {
    for (final entry in _values.entries.toList().reversed) {
      if (entry.key.path == path) return entry.value;
    }
    return null;
  }

  void invalidatePath(String path) {
    _values.removeWhere((key, _) {
      final keyPath = key.path;
      return keyPath == path || keyPath.startsWith('$path/');
    });
  }

  void clear() => _values.clear();
}
