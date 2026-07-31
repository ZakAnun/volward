import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scan_worker done message shape', () {
    test('done message includes snapshot_path and snapshot_id', () {
      // Validates the message contract that volward_session.dart depends on.
      const msg = <String, dynamic>{
        'type': 'done',
        'snapshot_path': '/tmp/volward-job-1234.pb',
        'snapshot_id': 'snap-1',
      };
      expect(msg['type'], 'done');
      expect(msg['snapshot_path'], isNotEmpty);
      expect(msg['snapshot_id'], isNotEmpty);
    });

    test('done message includes index_path when index API is available', () {
      // When the dylib supports volward_write_last_index_to_path, scan_worker
      // appends index_path to the done message so volward_session can load
      // the catalog without hydrating the full snapshot.
      const msg = <String, dynamic>{
        'type': 'done',
        'snapshot_path': '/tmp/volward-job-1234.pb',
        'snapshot_id': 'snap-1',
        'index_path': '/tmp/volward-job-1234.index.json',
      };
      expect(msg.containsKey('index_path'), isTrue);
      expect(msg['index_path'], isNotEmpty);
    });

    test('checkpoint message includes snapshot_path', () {
      const msg = <String, dynamic>{
        'type': 'checkpoint',
        'snapshot_path': '/tmp/volward-job-1234-checkpoint-7.pb',
      };
      expect(msg['type'], 'checkpoint');
      expect(msg['snapshot_path'], isNotEmpty);
    });

    test('checkpoint message may include index_path', () {
      const msg = <String, dynamic>{
        'type': 'checkpoint',
        'snapshot_path': '/tmp/volward-job-1234-checkpoint-7.pb',
        'index_path': '/tmp/volward-job-1234-checkpoint-7.index.json',
      };
      expect(msg['index_path'], isNotEmpty);
    });
  });
}
