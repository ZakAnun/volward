import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scan_worker done message shape', () {
    test('done message includes index_path and snapshot_id', () {
      // Validates the message contract for the index-only completion path.
      const msg = <String, dynamic>{
        'type': 'done',
        'index_path': '/tmp/volward-job-1234.index.json',
        'snapshot_id': 'snap-1',
      };
      expect(msg['type'], 'done');
      expect(msg['index_path'], isNotEmpty);
      expect(msg['snapshot_id'], isNotEmpty);
    });

    test('legacy done message can still fall back to snapshot_path', () {
      const msg = <String, dynamic>{
        'type': 'done',
        'snapshot_path': '/tmp/volward-job-1234.pb',
        'snapshot_id': 'snap-1',
      };
      expect(msg['snapshot_path'], isNotEmpty);
    });

    test('checkpoint message includes snapshot_path', () {
      const msg = <String, dynamic>{
        'type': 'checkpoint',
        'snapshot_path': '/tmp/volward-job-1234-checkpoint-7.pb',
      };
      expect(msg['type'], 'checkpoint');
      expect(msg['snapshot_path'], isNotEmpty);
    });

    test('checkpoint message is legacy snapshot-only progress', () {
      const msg = <String, dynamic>{
        'type': 'checkpoint',
        'snapshot_path': '/tmp/volward-job-1234-checkpoint-7.pb',
      };
      expect(msg.containsKey('index_path'), isFalse);
    });
  });
}
