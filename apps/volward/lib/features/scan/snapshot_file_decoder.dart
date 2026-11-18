import 'dart:convert';
import 'dart:io';

import '../../proto/snapshot_pb_decoder.dart';

Map<String, dynamic>? _decodeSnapshotJsonFile(String path) {
  final raw = File(path).readAsStringSync();
  final decoded = jsonDecode(raw);
  return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
}

/// Decodes a snapshot or checkpoint file, dispatching on the file extension.
///
/// `.pb`   → protobuf wire format (written by Rust via `write_snapshot_pb_atomic`)
/// anything else → JSON (legacy format)
///
/// Called from Isolate.run, so it must be a top-level function.
Map<String, dynamic>? decodeSnapshotFile(String path) {
  if (path.endsWith('.pb')) {
    final bytes = File(path).readAsBytesSync();
    return decodeSnapshotPb(bytes);
  }
  return _decodeSnapshotJsonFile(path);
}
