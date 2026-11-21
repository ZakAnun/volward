import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef SnapshotStateFileResolver = Future<File?> Function();
typedef SnapshotStateReader = Future<String> Function(File file);
typedef SnapshotStateWriter = Future<void> Function(File file, String value);

/// Owns session-state persistence and its load idempotency.
class SnapshotPersistence {
  SnapshotPersistence({
    required this._stateFile,
    required this._readState,
    required this._writeState,
  });

  final SnapshotStateFileResolver _stateFile;
  final SnapshotStateReader _readState;
  final SnapshotStateWriter _writeState;

  bool _loaded = false;
  Future<void>? _loadFuture;
  Future<void> _writeTail = Future<void>.value();

  bool get loaded => _loaded;

  Future<Map<String, dynamic>?> load() async {
    final file = await _stateFile();
    if (file == null || !await file.exists()) return null;
    final raw = await _readState(file);
    if (raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  Future<void> loadIfNeeded(Future<void> Function() load) {
    if (_loaded) return Future<void>.value();
    final inFlight = _loadFuture;
    if (inFlight != null) return inFlight;
    final future = load()
        .then<void>((_) {
          _loaded = true;
        })
        .whenComplete(() {
          _loadFuture = null;
        });
    _loadFuture = future;
    return future;
  }

  Future<void> persist(Map<String, dynamic> state) {
    final operation = _writeTail.then((_) => _persistNow(state));
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> _persistNow(Map<String, dynamic> state) async {
    final file = await _stateFile();
    if (file == null) return;
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await _writeState(temp, jsonEncode(state));
    await temp.rename(file.path);
  }
}
