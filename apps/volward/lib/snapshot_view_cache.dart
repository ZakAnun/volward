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

  void invalidatePath(String path) {
    _values.removeWhere((key, _) {
      final keyPath = key.path;
      return keyPath == path || keyPath.startsWith('$path/');
    });
  }

  void clear() => _values.clear();
}
