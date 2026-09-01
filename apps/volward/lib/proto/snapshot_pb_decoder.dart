/// Decodes a proto3-encoded `StorageSnapshot` (from `proto/volward.proto`)
/// into the same `Map<String, dynamic>` shape that `jsonDecode` produces from
/// the JSON wire format.  The caller just reads bytes from a `.pb` file and
/// passes them here — it does not need to know whether JSON or protobuf is
/// on disk.
///
/// No package dependencies — only `dart:convert` and `dart:typed_data`.
library;

import 'dart:convert';
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Decodes proto3 bytes for a `StorageSnapshot` message.
///
/// Returns `null` when [bytes] is empty or the bytes are malformed.
Map<String, dynamic>? decodeSnapshotPb(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  try {
    return _decodeSnapshot(_ProtoReader(bytes, 0, bytes.length));
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Message decoders — field numbers mirror proto/volward.proto exactly
// ---------------------------------------------------------------------------

Map<String, dynamic> _decodeSnapshot(_ProtoReader r) {
  final entries = <Map<String, dynamic>>[];
  final warnings = <String>[];
  var snapshotId = '';
  var scannedAtMs = 0;
  var capability = 'FullPath';
  var volumeTotal = 0;
  var volumeUsed = 0;
  var reclaimable = 0;
  Map<String, dynamic>? tree;
  Map<String, dynamic>? stats;

  while (!r.isDone) {
    final tag = r.readVarint();
    final fieldNum = tag >> 3;
    final wireType = tag & 7;
    switch (fieldNum) {
      case 1:
        snapshotId = r.readString(); // string snapshot_id
      case 2:
        scannedAtMs = r.readVarint(); // int64 scanned_at_ms
      case 3:
        capability = _capability(r.readVarint()); // CapabilityLevel capability
      case 4:
        volumeTotal = r.readVarint(); // uint64 volume_total_bytes
      case 5:
        volumeUsed = r.readVarint(); // uint64 volume_used_bytes
      case 6:
        reclaimable = r.readVarint(); // uint64 reclaimable_estimate_bytes
      case 7:
        entries.add(_decodeEntry(r.readLenSlice())); // repeated StorageEntry
      case 8:
        tree = _decodeTreeNode(r.readLenSlice()); // ScanTreeNode tree
      case 9:
        stats = _decodeStats(r.readLenSlice()); // ScanStats stats
      case 10:
        warnings.add(r.readString()); // repeated string warnings
      default:
        r.skipField(wireType);
    }
  }

  return {
    'snapshot_id': snapshotId,
    'scanned_at_ms': scannedAtMs,
    'capability': capability,
    'volume_total_bytes': volumeTotal,
    'volume_used_bytes': volumeUsed,
    'reclaimable_estimate_bytes': reclaimable,
    'entries': entries,
    'tree': tree,
    'stats': stats,
    'warnings': warnings,
  };
}

Map<String, dynamic> _decodeEntry(_ProtoReader r) {
  var id = '';
  var displayName = '';
  var pathOrUri = '';
  var sizeBytes = 0;
  var category = 'Unknown';
  var riskLevel = 'Low';
  var sourceType = 'Directory';
  var deletable = false;
  var reason = '';
  int? modifiedAtMs;

  while (!r.isDone) {
    final tag = r.readVarint();
    final fieldNum = tag >> 3;
    final wireType = tag & 7;
    switch (fieldNum) {
      case 1:
        id = r.readString(); // string id
      case 2:
        displayName = r.readString(); // string display_name
      case 3:
        pathOrUri = r.readString(); // string path_or_uri
      case 4:
        sizeBytes = r.readVarint(); // uint64 size_bytes
      case 5:
        category = _entryCategory(r.readVarint()); // EntryCategory category
      case 6:
        riskLevel = _riskLevel(r.readVarint()); // RiskLevel risk_level
      case 7:
        sourceType = _sourceType(r.readVarint()); // SourceType source_type
      case 8:
        deletable = r.readVarint() != 0; // bool deletable
      case 9:
        reason = r.readString(); // string reason
      case 10:
        modifiedAtMs = r.readVarint(); // optional int64 modified_at_ms
      default:
        r.skipField(wireType);
    }
  }

  return {
    'id': id,
    'display_name': displayName,
    'path_or_uri': pathOrUri,
    'size_bytes': sizeBytes,
    'category': category,
    'risk_level': riskLevel,
    'source_type': sourceType,
    'deletable': deletable,
    'reason': reason,
    if (modifiedAtMs != null) 'modified_at_ms': modifiedAtMs,
  };
}

Map<String, dynamic> _decodeTreeNode(_ProtoReader r) {
  var name = '';
  var path = '';
  var isDir = false;
  var sizeBytes = 0;
  String? entryId; // optional string — absent when null
  final children = <Map<String, dynamic>>[];
  var scanned = false;
  var peekScanned = false;

  while (!r.isDone) {
    final tag = r.readVarint();
    final fieldNum = tag >> 3;
    final wireType = tag & 7;
    switch (fieldNum) {
      case 1:
        name = r.readString(); // string name
      case 2:
        path = r.readString(); // string path
      case 3:
        isDir = r.readVarint() != 0; // bool is_dir
      case 4:
        sizeBytes = r.readVarint(); // uint64 size_bytes
      case 5:
        entryId = r.readString(); // optional string entry_id
      case 6:
        children.add(
          _decodeTreeNode(r.readLenSlice()),
        ); // repeated ScanTreeNode
      case 7:
        scanned = r.readVarint() != 0; // bool scanned (client-only)
      case 8:
        peekScanned = r.readVarint() != 0; // bool peek_scanned (client-only)
      default:
        r.skipField(wireType);
    }
  }

  return {
    'name': name,
    'path': path,
    'is_dir': isDir,
    'size_bytes': sizeBytes,
    // Omit entry_id entirely when absent, matching JSON's null behaviour.
    if (entryId != null) 'entry_id': entryId,
    'children': children,
    'scanned': scanned,
    // Use camelCase to match the key written by _replaceNodeAtPath in
    // scan_snapshot_merge.dart and read by _pickMoreComplete.  Only include
    // it when true — same convention as the in-memory merge path.
    if (peekScanned) 'peekScanned': true,
  };
}

Map<String, dynamic> _decodeStats(_ProtoReader r) {
  var pathsSeen = 0;
  var dirsSeen = 0;
  var filesSeen = 0;
  var filesInSnapshot = 0;
  var pathsSkipped = 0;
  var truncated = false;
  String? incompleteReason; // optional string

  while (!r.isDone) {
    final tag = r.readVarint();
    final fieldNum = tag >> 3;
    final wireType = tag & 7;
    switch (fieldNum) {
      case 1:
        pathsSeen = r.readVarint(); // uint64 paths_seen
      case 2:
        dirsSeen = r.readVarint(); // uint64 dirs_seen
      case 3:
        filesSeen = r.readVarint(); // uint64 files_seen
      case 4:
        filesInSnapshot = r.readVarint(); // uint64 files_in_snapshot
      case 5:
        pathsSkipped = r.readVarint(); // uint64 paths_skipped
      case 6:
        truncated = r.readVarint() != 0; // bool truncated
      case 7:
        incompleteReason = r.readString(); // optional string incomplete_reason
      default:
        r.skipField(wireType);
    }
  }

  return {
    'paths_seen': pathsSeen,
    'dirs_seen': dirsSeen,
    'files_seen': filesSeen,
    'files_in_snapshot': filesInSnapshot,
    'paths_skipped': pathsSkipped,
    'truncated': truncated,
    if (incompleteReason != null) 'incomplete_reason': incompleteReason,
  };
}

// ---------------------------------------------------------------------------
// Enum mappers — proto integer → serde variant name (must match Rust model.rs)
// ---------------------------------------------------------------------------

String _capability(int v) {
  return const {1: 'FullPath', 2: 'AppStatsOnly', 3: 'GuidedOnly'}[v] ??
      'FullPath';
}

String _entryCategory(int v) {
  return const {
        1: 'Cache',
        2: 'Temp',
        3: 'Media',
        4: 'AppData',
        5: 'Orphan',
        6: 'Duplicate',
        7: 'System',
        8: 'Unknown',
        9: 'BuildArtifact',
      }[v] ??
      'Unknown';
}

String _riskLevel(int v) {
  return const {1: 'Low', 2: 'Medium', 3: 'High'}[v] ?? 'Low';
}

String _sourceType(int v) {
  return const {1: 'Directory', 2: 'File', 3: 'Volume', 4: 'Application'}[v] ??
      'Directory';
}

// ---------------------------------------------------------------------------
// Proto3 binary reader
// ---------------------------------------------------------------------------

class _ProtoReader {
  _ProtoReader(this._data, this._pos, this._end);

  final Uint8List _data;
  int _pos;
  final int _end;

  bool get isDone => _pos >= _end;

  /// Reads a base-128 varint (up to 64-bit two's-complement).
  ///
  /// Dart's `int` is 64-bit signed on all native targets, so we use plain
  /// bitwise OR — values that exceed INT64_MAX would wrap, but file sizes,
  /// timestamps, and counts that appear in a snapshot never approach that range.
  int readVarint() {
    var result = 0;
    var shift = 0;
    for (var i = 0; i < 10; i++) {
      final b = _data[_pos++];
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) return result;
      shift += 7;
    }
    return result; // 10-byte varint fully consumed
  }

  /// Reads a length-prefixed UTF-8 string.
  String readString() {
    final len = readVarint();
    final view = Uint8List.view(_data.buffer, _data.offsetInBytes + _pos, len);
    _pos += len;
    return utf8.decode(view);
  }

  /// Reads the length prefix and returns a sub-reader scoped to that span.
  _ProtoReader readLenSlice() {
    final len = readVarint();
    final start = _pos;
    _pos += len;
    return _ProtoReader(_data, start, start + len);
  }

  /// Skips a field value given its wire type.
  void skipField(int wireType) {
    switch (wireType) {
      case 0: // varint — consume bytes until the high bit is clear
        while (_data[_pos++] & 0x80 != 0) {}
      case 1: // 64-bit fixed
        _pos += 8;
      case 2: // length-delimited — skip the payload
        _pos += readVarint();
      case 5: // 32-bit fixed
        _pos += 4;
      default:
        throw StateError('snapshot_pb_decoder: unknown wire type $wireType');
    }
  }
}
