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

  void invalidatePath(String path) {
    _values.removeWhere((key, _) {
      final keyPath = key.path;
      return keyPath == path || keyPath.startsWith('$path/');
    });
  }

  void clear() => _values.clear();
}
