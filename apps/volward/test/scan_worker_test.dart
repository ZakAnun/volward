import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/bridge/scan_worker.dart';

void main() {
  test('peek timeout waits for worker shutdown after cancellation', () async {
    final workerResult = Completer<String>();
    var cancelCount = 0;
    var completed = false;

    final result = waitForPeekWorkerResult(
      workerResult.future,
      timeout: const Duration(milliseconds: 10),
      cancel: () => cancelCount++,
    ).whenComplete(() => completed = true);

    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(cancelCount, 1);
    expect(completed, isFalse);

    workerResult.complete('cancelled');
    expect(await result, 'cancelled');
    expect(completed, isTrue);
  });

  test('peek snapshot uses the same stable ids in tree and entries', () {
    final snapshot = <String, dynamic>{
      'entries': <dynamic>[
        <String, dynamic>{
          'id': 'peek-job-1:/root/a.txt',
          'path_or_uri': '/root/a.txt',
        },
      ],
      'tree': <String, dynamic>{
        'path': '/root',
        'children': <dynamic>[
          <String, dynamic>{
            'path': '/root/a.txt',
            'entry_id': 'peek-job-1:/root/a.txt',
            'children': <dynamic>[],
          },
        ],
      },
    };

    stabilizePeekSnapshotEntryIds(snapshot);

    final entry = (snapshot['entries'] as List).single as Map;
    final tree = snapshot['tree'] as Map;
    final child = (tree['children'] as List).single as Map;
    expect(entry['id'], 'path:/root/a.txt');
    expect(child['entry_id'], entry['id']);
  });

  test('missing peek directory fails before starting a native engine', () async {
    final resultPort = ReceivePort();
    final cancelInitPort = ReceivePort();
    final isolate = await Isolate.spawn(
      volwardPeekScanIsolate,
      [
        resultPort.sendPort,
        '/definitely/missing/volward-peek-directory',
        cancelInitPort.sendPort,
      ],
    );

    final result = await resultPort.first as Map;
    expect(result['type'], 'error');
    expect(result['error'].toString(), contains('does not exist'));

    resultPort.close();
    cancelInitPort.close();
    isolate.kill(priority: Isolate.immediate);
  });
}
