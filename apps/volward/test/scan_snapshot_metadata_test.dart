import 'package:flutter_test/flutter_test.dart';
import 'package:volward/scan_entry_record.dart';
import 'package:volward/scan_snapshot_state.dart';

void main() {
  group('snapshot metadata decoding', () {
    test('ScanEntryRecord parses mtime and preserves existing fields', () {
      final entry = ScanEntryRecord.fromWire({
        'id': 'e1',
        'display_name': 'a.bin',
        'path_or_uri': '/root/a.bin',
        'size_bytes': 10,
        'category': 'Cache',
        'deletable': true,
        'modified_at_ms': 1700000000000,
      });

      expect(entry.modifiedAtMs, 1700000000000);
      expect(entry.id, 'e1');
      expect(entry.displayName, 'a.bin');
      expect(entry.sizeBytes, 10);
      expect(entry.category, 'Cache');
      expect(entry.deletable, isTrue);
      expect(entry.toWire()['modified_at_ms'], 1700000000000);
    });

    test('ScanEntryRecord treats missing metadata as null', () {
      final entry = ScanEntryRecord.fromWire({
        'id': 'e2',
        'display_name': 'b.txt',
        'path_or_uri': '/root/b.txt',
        'size_bytes': 5,
        'category': 'Unknown',
        'deletable': false,
      });

      expect(entry.modifiedAtMs, isNull);
      expect(entry.toWire().containsKey('modified_at_ms'), isFalse);
      expect(entry.pathOrUri, '/root/b.txt');
    });

    test('ScanSnapshotState round-trips entries with metadata', () {
      final state = ScanSnapshotState.fromWire({
        'snapshot_id': 'snapshot-1',
        'entries': [
          {
            'id': 'e1',
            'display_name': 'cache.bin',
            'path_or_uri': '/root/cache.bin',
            'size_bytes': 40,
            'category': 'Cache',
            'deletable': true,
            'modified_at_ms': 1700000000000,
          },
        ],
        'stats': {},
      });

      final entries = state.materializeEntries();
      expect(entries, hasLength(1));
      expect(entries.single.modifiedAtMs, 1700000000000);
      expect(entries.single.id, 'e1');
      expect(state.snapshotId, 'snapshot-1');
    });
  });
}
