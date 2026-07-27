import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/proto/snapshot_pb_decoder.dart';

// ---------------------------------------------------------------------------
// Minimal proto3 builder — constructs wire-format bytes for test fixtures.
// Field numbers must match proto/volward.proto exactly.
// ---------------------------------------------------------------------------

class _Proto3Builder {
  final _bytes = <int>[];

  /// Encodes a length-delimited string field.
  void string(int fieldNum, String value) {
    final encoded = utf8.encode(value);
    _varint((fieldNum << 3) | 2);
    _varint(encoded.length);
    _bytes.addAll(encoded);
  }

  /// Encodes a varint (int32/int64/bool/enum) field.
  void varint(int fieldNum, int value) {
    _varint(fieldNum << 3); // wire type 0
    _varint(value);
  }

  /// Encodes a length-delimited embedded message field.
  void embedded(int fieldNum, _Proto3Builder inner) {
    final innerBytes = inner.build();
    _varint((fieldNum << 3) | 2);
    _varint(innerBytes.length);
    _bytes.addAll(innerBytes);
  }

  void _varint(int value) {
    // Base-128 little-endian encoding; safe for non-negative int64 values.
    while (value > 0x7F) {
      _bytes.add((value & 0x7F) | 0x80);
      value >>= 7;
    }
    _bytes.add(value);
  }

  Uint8List build() => Uint8List.fromList(_bytes);
}

// Convenience factories for the three message types used in tests.
_Proto3Builder snap() => _Proto3Builder(); // StorageSnapshot
_Proto3Builder treeNode() => _Proto3Builder(); // ScanTreeNode
_Proto3Builder entryBuilder() => _Proto3Builder(); // StorageEntry

void main() {
  group('decodeSnapshotPb', () {
    // -----------------------------------------------------------------------
    // Null / error paths
    // -----------------------------------------------------------------------

    test('empty bytes returns null', () {
      expect(decodeSnapshotPb(Uint8List(0)), isNull);
    });

    test('truncated bytes — length prefix claims more bytes than exist — returns null', () {
      // Tag 0x0A = field 1 LEN; then varint 0x14 = 20 bytes, but nothing follows.
      final truncated = Uint8List.fromList([0x0A, 0x14]);
      expect(decodeSnapshotPb(truncated), isNull);
    });

    test('garbage bytes return null without throwing', () {
      final garbage = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]);
      expect(decodeSnapshotPb(garbage), isNull);
    });

    // -----------------------------------------------------------------------
    // StorageSnapshot top-level fields
    // -----------------------------------------------------------------------

    test('minimal snapshot — only snapshot_id — decodes correctly', () {
      final b = snap()..string(1, 'snap-001');
      final result = decodeSnapshotPb(b.build());

      expect(result, isNotNull);
      expect(result!['snapshot_id'], 'snap-001');
      expect(result['entries'], isEmpty);
      expect(result['tree'], isNull);
      expect(result['warnings'], isEmpty);
    });

    test('scanned_at_ms and reclaimable_estimate_bytes decoded as int', () {
      final b = snap()
        ..string(1, 'snap-002')
        ..varint(2, 1_700_000_000_000) // int64 ms timestamp
        ..varint(6, 987_654_321); // reclaimable_estimate_bytes

      final result = decodeSnapshotPb(b.build())!;
      expect(result['scanned_at_ms'], 1_700_000_000_000);
      expect(result['reclaimable_estimate_bytes'], 987_654_321);
    });

    // -----------------------------------------------------------------------
    // ScanTreeNode (field 8)
    // -----------------------------------------------------------------------

    test('tree node — basic fields decoded correctly', () {
      final tree = treeNode()
        ..string(1, 'Documents') // name
        ..string(2, '/root/Documents') // path
        ..varint(3, 1) // is_dir = true
        ..varint(4, 512_000); // size_bytes

      final b = snap()
        ..string(1, 'snap-tree')
        ..embedded(8, tree);

      final result = decodeSnapshotPb(b.build())!;
      final t = result['tree'] as Map<String, dynamic>;

      expect(t['name'], 'Documents');
      expect(t['path'], '/root/Documents');
      expect(t['is_dir'], isTrue);
      expect(t['size_bytes'], 512_000);
      expect(t['scanned'], isFalse);
      expect(t['children'], isEmpty);
    });

    test('tree node — entry_id absent when field not set', () {
      // entry_id is `optional string` (field 5); proto3 omits absent optional
      // string fields, so the decoded Map must not contain the key at all.
      final tree = treeNode()
        ..string(1, 'dir')
        ..string(2, '/root/dir')
        ..varint(3, 1);

      final b = snap()..string(1, 's')..embedded(8, tree);
      final t = decodeSnapshotPb(b.build())!['tree'] as Map<String, dynamic>;

      expect(t.containsKey('entry_id'), isFalse);
    });

    test('tree node — entry_id present when field is set', () {
      final tree = treeNode()
        ..string(1, 'photo.jpg')
        ..string(2, '/root/photo.jpg')
        ..varint(3, 0) // is_dir = false
        ..varint(4, 2_048)
        ..string(5, 'entry-abc'); // entry_id

      final b = snap()..string(1, 's')..embedded(8, tree);
      final t = decodeSnapshotPb(b.build())!['tree'] as Map<String, dynamic>;

      expect(t['entry_id'], 'entry-abc');
    });

    test('tree node — nested children decoded recursively', () {
      final child = treeNode()
        ..string(1, 'child')
        ..string(2, '/root/child')
        ..varint(3, 1)
        ..varint(4, 100);

      final parent = treeNode()
        ..string(1, 'root')
        ..string(2, '/root')
        ..varint(3, 1)
        ..varint(4, 100)
        ..embedded(6, child); // field 6 = repeated children

      final b = snap()..string(1, 'snap-nested')..embedded(8, parent);
      final t = decodeSnapshotPb(b.build())!['tree'] as Map<String, dynamic>;

      final children = t['children'] as List;
      expect(children, hasLength(1));
      expect(children.first['path'], '/root/child');
      expect(children.first['name'], 'child');
    });

    // -----------------------------------------------------------------------
    // StorageEntry (field 7, repeated)
    // -----------------------------------------------------------------------

    test('StorageEntry — id, size_bytes, category decoded correctly', () {
      final e = entryBuilder()
        ..string(1, 'ent-1') // id
        ..string(2, 'Cache dir') // display_name
        ..string(3, '/Library/Caches/foo') // path_or_uri
        ..varint(4, 8_192) // size_bytes
        ..varint(5, 1) // category = Cache
        ..varint(6, 2) // risk_level = Medium
        ..varint(8, 1); // deletable = true

      final b = snap()
        ..string(1, 'snap-entry')
        ..embedded(7, e); // field 7 = entries

      final result = decodeSnapshotPb(b.build())!;
      final entries = result['entries'] as List;
      expect(entries, hasLength(1));

      final entry = entries.first as Map<String, dynamic>;
      expect(entry['id'], 'ent-1');
      expect(entry['display_name'], 'Cache dir');
      expect(entry['path_or_uri'], '/Library/Caches/foo');
      expect(entry['size_bytes'], 8_192);
      expect(entry['category'], 'Cache');
      expect(entry['risk_level'], 'Medium');
      expect(entry['deletable'], isTrue);
    });

    test('multiple StorageEntry fields accumulated in entries list', () {
      final e1 = entryBuilder()..string(1, 'a')..varint(5, 1); // Cache
      final e2 = entryBuilder()..string(1, 'b')..varint(5, 2); // Temp

      final b = snap()
        ..string(1, 'snap-multi')
        ..embedded(7, e1)
        ..embedded(7, e2);

      final entries = decodeSnapshotPb(b.build())!['entries'] as List;
      expect(entries, hasLength(2));
      expect(entries[0]['id'], 'a');
      expect(entries[1]['id'], 'b');
    });

    // -----------------------------------------------------------------------
    // Enum fallback values
    // -----------------------------------------------------------------------

    test('unknown category enum value falls back to "Unknown"', () {
      final e = entryBuilder()..string(1, 'x')..varint(5, 99);
      final b = snap()..string(1, 's')..embedded(7, e);
      final entry = (decodeSnapshotPb(b.build())!['entries'] as List).first;
      expect(entry['category'], 'Unknown');
    });

    test('unknown risk_level enum value falls back to "Low"', () {
      final e = entryBuilder()..string(1, 'x')..varint(6, 99);
      final b = snap()..string(1, 's')..embedded(7, e);
      final entry = (decodeSnapshotPb(b.build())!['entries'] as List).first;
      expect(entry['risk_level'], 'Low');
    });

    test('unknown capability enum value falls back to "FullPath"', () {
      final b = snap()..string(1, 's')..varint(3, 99); // capability = unknown
      expect(decodeSnapshotPb(b.build())!['capability'], 'FullPath');
    });

    // -----------------------------------------------------------------------
    // peekScanned — client-only field written by merge logic, never by Rust.
    // The decoder must NOT include 'peekScanned' for the default false value,
    // matching the convention in scan_snapshot_merge.dart (camelCase, only
    // present when true).
    // -----------------------------------------------------------------------

    test('peek_scanned field 8 false — peekScanned absent from decoded Map', () {
      // Rust writes peek_scanned=false by default; decoded Map must not
      // contain 'peekScanned' so merge logic treats the node as non-peeked.
      final tree = treeNode()
        ..string(1, 'dir')
        ..string(2, '/d')
        ..varint(3, 1)
        ..varint(8, 0); // peek_scanned = false

      final b = snap()..string(1, 's')..embedded(8, tree);
      final t = decodeSnapshotPb(b.build())!['tree'] as Map<String, dynamic>;

      expect(t.containsKey('peekScanned'), isFalse);
      expect(t.containsKey('peek_scanned'), isFalse);
    });

    test('peek_scanned field 8 true — peekScanned:true present in decoded Map', () {
      // If Rust ever starts persisting peek_scanned, the decoded Map must use
      // camelCase 'peekScanned' so _pickMoreComplete recognises it correctly.
      final tree = treeNode()
        ..string(1, 'dir')
        ..string(2, '/d')
        ..varint(3, 1)
        ..varint(8, 1); // peek_scanned = true

      final b = snap()..string(1, 's')..embedded(8, tree);
      final t = decodeSnapshotPb(b.build())!['tree'] as Map<String, dynamic>;

      expect(t['peekScanned'], isTrue);
      expect(t.containsKey('peek_scanned'), isFalse); // no stale snake_case key
    });
  });
}
