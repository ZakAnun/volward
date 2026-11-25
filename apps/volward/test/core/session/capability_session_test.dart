import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/capabilities/capability_models.dart';
import 'package:volward/core/session/capability_session.dart';

void main() {
  test(
    'capability cache and dispatch stay owned by CapabilitySession',
    () async {
      final session = CapabilitySession(() => null, () => true, () => null);
      var analyzeCalls = 0;
      session.capabilityAnalyzeRunnerForTest = (_, _, _) {
        analyzeCalls++;
        return jsonEncode({'result': _resultPayload()});
      };

      final first = await session.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.largeFiles,
      );
      final second = await session.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.largeFiles,
      );

      expect(first.groups.single.items.single.id, 'entry-42');
      expect(second.groups.single.items.single.id, 'entry-42');
      expect(analyzeCalls, 1);
    },
  );

  test('capability status and cancellation use the same owner', () {
    final session = CapabilitySession(() => null, () => true, () => null);
    session.capabilityStatusReaderForTest = (_) =>
        jsonEncode(_completedStatusPayload());
    session.capabilityCancelRunnerForTest = (_) => true;

    final status = session.getCapabilityJobStatus('job-1');

    expect(status.isTerminal, isTrue);
    expect(status.result?.groups.single.items.single.id, 'entry-42');
    expect(session.cancelCapabilityAnalysis('job-1'), isTrue);
  });
}

Map<String, dynamic> _completedStatusPayload() => {
  'progress': {
    'job_id': 'job-1',
    'snapshot_id': 'snapshot-1',
    'capability': 'large_files',
    'phase': 'completed',
    'processed': 1,
    'total': 1,
    'current_path': null,
    'cancelled': false,
    'error': null,
  },
  'result': _resultPayload(),
};

Map<String, dynamic> _resultPayload() => {
  'schema_version': 1,
  'capability': 'large_files',
  'snapshot_id': 'snapshot-1',
  'root_path': '/root',
  'analyzer_version': 'large_files-v1',
  'generated_at_ms': 0,
  'capability_level': 'full_path',
  'summary': {
    'item_count': 1,
    'total_bytes': 10,
    'safe_count': 0,
    'review_count': 1,
    'kept_count': 0,
    'truncated': false,
  },
  'groups': [
    {
      'group_id': 'group:/root',
      'group_path': '/root',
      'title': 'root',
      'item_count': 1,
      'total_bytes': 10,
      'safe_count': 0,
      'review_count': 1,
      'kept_count': 0,
      'default_expanded': true,
      'items': [
        {
          'id': 'entry-42',
          'path': '/root/a.bin',
          'display_name': 'a.bin',
          'size_bytes': 10,
          'is_directory': false,
          'modified_at_ms': null,
          'recommendation': 'review_needed',
          'confidence': 'medium',
          'reason': 'large_file',
          'evidence': ['size_bytes:10'],
          'delete_target': null,
          'preview': {'kind': 'file', 'locatable': true},
        },
      ],
    },
  ],
  'next_cursor': null,
  'deletion_plan': {
    'snapshot_id': 'snapshot-1',
    'target_count': 0,
    'target_bytes': 0,
    'targets': [],
    'blocked_targets': [],
    'requires_confirmation': true,
  },
  'warnings': [],
};
