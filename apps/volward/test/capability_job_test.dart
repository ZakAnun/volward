import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/capabilities/capability_models.dart';
import 'package:volward/volward_session.dart';

void main() {
  group('VolwardSession capability API', () {
    test('analyzeCapability decodes a typed result from the bridge', () async {
      final session = VolwardSession.test();
      session.capabilityAnalyzeRunnerForTest =
          (snapshotId, capability, optionsJson) {
            expect(snapshotId, 'snapshot-1');
            expect(capability, 'large_files');
            expect(jsonDecode(optionsJson)['page_size'], 100);
            return jsonEncode({'result': _resultPayload()});
          };

      final result = await session.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.largeFiles,
      );

      expect(result.schemaVersion, 1);
      expect(result.capability, Capability.largeFiles);
      expect(result.snapshotId, 'snapshot-1');
      expect(result.groups.single.items.single.id, 'entry-42');
    });

    test(
      'analyzeCapability surfaces structured errors as StateError',
      () async {
        final session = VolwardSession.test();
        session.capabilityAnalyzeRunnerForTest = (_, __, ___) => jsonEncode({
          'error': {
            'code': 'unsupported_capability',
            'message': 'capability is not implemented',
            'capability': 'large_files',
            'snapshot_id': 'snapshot-1',
          },
        });

        await expectLater(
          session.analyzeCapability(
            snapshotId: 'snapshot-1',
            capability: Capability.largeFiles,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('unsupported_capability'),
            ),
          ),
        );
      },
    );

    test(
      'analyzeCapability reports malformed responses with capability',
      () async {
        final session = VolwardSession.test();
        session.capabilityAnalyzeRunnerForTest = (_, __, ___) => 'not-json';

        await expectLater(
          session.analyzeCapability(
            snapshotId: 'snapshot-1',
            capability: Capability.largeFiles,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('large_files'),
            ),
          ),
        );
      },
    );

    test('startCapabilityAnalysis returns the job id', () {
      final session = VolwardSession.test();
      session.capabilityStartRunnerForTest =
          (snapshotId, capability, optionsJson) {
            expect(snapshotId, 'snapshot-1');
            expect(capability, 'duplicate_files');
            return jsonEncode({'job_id': 'job-42'});
          };

      final jobId = session.startCapabilityAnalysis(
        snapshotId: 'snapshot-1',
        capability: Capability.duplicateFiles,
      );
      expect(jobId, 'job-42');
    });

    test('startCapabilityAnalysis rejects error envelopes', () {
      final session = VolwardSession.test();
      session.capabilityStartRunnerForTest = (_, __, ___) => jsonEncode({
        'error': {'code': 'snapshot_mismatch', 'message': 'stale snapshot'},
      });

      expect(
        () => session.startCapabilityAnalysis(
          snapshotId: 'stale',
          capability: Capability.largeFiles,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('snapshot_mismatch'),
          ),
        ),
      );
    });

    test('getCapabilityJobStatus parses progress and result', () {
      final session = VolwardSession.test();
      session.capabilityStatusReaderForTest = (jobId) {
        expect(jobId, 'job-1');
        return jsonEncode(
          _statusPayload(phase: 'completed', result: _resultPayload()),
        );
      };

      final status = session.getCapabilityJobStatus('job-1');

      expect(status.progress.jobId, 'job-1');
      expect(status.progress.snapshotId, 'snapshot-1');
      expect(status.progress.phase, CapabilityAnalysisPhase.completed);
      expect(status.isTerminal, isTrue);
      expect(status.result, isNotNull);
      expect(status.result!.groups.single.items.single.id, 'entry-42');
    });

    test('getCapabilityJobStatus rejects error envelopes', () {
      final session = VolwardSession.test();
      session.capabilityStatusReaderForTest = (_) => jsonEncode({
        'error': {'code': 'job_not_found', 'message': 'no such job'},
      });

      expect(
        () => session.getCapabilityJobStatus('missing'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('job_not_found'),
          ),
        ),
      );
    });

    test('getCapabilityJobStatus reports malformed progress with context', () {
      final session = VolwardSession.test();
      final payload = _statusPayload()..['progress'] = 'broken';
      session.capabilityStatusReaderForTest = (_) => jsonEncode(payload);

      expect(
        () => session.getCapabilityJobStatus('job-1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('cancelCapabilityAnalysis passes through the bridge result', () {
      final session = VolwardSession.test();
      session.capabilityCancelRunnerForTest = (jobId) {
        expect(jobId, 'job-1');
        return true;
      };

      expect(session.cancelCapabilityAnalysis('job-1'), isTrue);
    });
  });

  group('watchCapabilityJob polling wrapper', () {
    test('yields progress and completes with the result', () async {
      final session = VolwardSession.test();
      final statuses = [
        _statusPayload(),
        _statusPayload(phase: 'inspecting'),
        _statusPayload(phase: 'completed', result: _resultPayload()),
      ];
      var reads = 0;
      session.capabilityStatusReaderForTest = (_) =>
          jsonEncode(statuses[reads++]);

      final phases = <String>[];
      await for (final progress in session.watchCapabilityJob('job-1')) {
        phases.add(progress.phase.wireValue);
      }

      expect(phases, ['preparing', 'inspecting', 'completed']);
      expect(reads, 3);
    });

    test('completes without a result when cancelled', () async {
      final session = VolwardSession.test();
      final statuses = [
        _statusPayload(),
        _statusPayload(phase: 'inspecting', cancelled: true),
      ];
      var reads = 0;
      session.capabilityStatusReaderForTest = (_) =>
          jsonEncode(statuses[reads++]);

      final phases = <String>[];
      await for (final progress in session.watchCapabilityJob('job-1')) {
        phases.add(progress.phase.wireValue);
      }

      expect(phases, ['preparing', 'inspecting']);
      expect(reads, 2);
    });
  });
}

Map<String, dynamic> _statusPayload({
  String phase = 'preparing',
  bool cancelled = false,
  String? error,
  Map<String, dynamic>? result,
}) => {
  'progress': {
    'job_id': 'job-1',
    'snapshot_id': 'snapshot-1',
    'capability': 'large_files',
    'phase': phase,
    'processed': 0,
    'total': 10,
    'current_path': null,
    'cancelled': cancelled,
    'error': error,
  },
  'result': result,
};

Map<String, dynamic> _resultPayload() => {
  'schema_version': 1,
  'capability': 'large_files',
  'snapshot_id': 'snapshot-1',
  'root_path': '/Users/me/Downloads',
  'analyzer_version': 'large_files-v1',
  'generated_at_ms': 0,
  'capability_level': 'full_path',
  'summary': {
    'item_count': 1,
    'total_bytes': 50000000,
    'safe_count': 0,
    'review_count': 1,
    'kept_count': 0,
    'truncated': false,
  },
  'groups': [
    {
      'group_id': 'group:/Users/me/Downloads/project',
      'group_path': '/Users/me/Downloads/project',
      'title': 'project',
      'item_count': 1,
      'total_bytes': 50000000,
      'safe_count': 0,
      'review_count': 1,
      'kept_count': 0,
      'default_expanded': true,
      'items': [
        {
          'id': 'entry-42',
          'path': '/Users/me/Downloads/project/build.zip',
          'display_name': 'build.zip',
          'size_bytes': 50000000,
          'is_directory': false,
          'modified_at_ms': null,
          'recommendation': 'review_needed',
          'confidence': 'medium',
          'reason': 'large_file',
          'evidence': [],
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
