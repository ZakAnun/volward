import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_analysis_gateway.dart';
import 'package:volward/capabilities/capability_models.dart';
import 'package:volward/volward_session.dart';

void main() {
  group('ProductionAiAnalysisGateway capability analysis', () {
    test('returns typed results and caches identical requests', () async {
      final session = VolwardSession.test();
      var calls = 0;
      session.capabilityAnalyzeRunnerForTest = (_, __, ___) {
        calls++;
        return jsonEncode({'result': _resultPayload()});
      };
      final gateway = ProductionAiAnalysisGateway(session: session);

      final first = await gateway.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.largeFiles,
      );
      final second = await gateway.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.largeFiles,
      );

      expect(first.groups.single.items.single.id, 'entry-42');
      expect(second.groups.single.items.single.id, 'entry-42');
      expect(calls, 1, reason: 'identical request must hit the cache');
    });

    test('different options bypass the cache entry', () async {
      final session = VolwardSession.test();
      var calls = 0;
      session.capabilityAnalyzeRunnerForTest = (_, __, ___) {
        calls++;
        return jsonEncode({'result': _resultPayload()});
      };
      final gateway = ProductionAiAnalysisGateway(session: session);

      await gateway.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.largeFiles,
      );
      await gateway.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.largeFiles,
        options: const AnalysisOptions(
          rootPath: '',
          largeFileThresholdBytes: 100000000,
          largeFileThresholdPreset: LargeFileThresholdPreset.mb100,
        ),
      );

      expect(calls, 2);
    });

    test('cursor requests always hit the analyzer', () async {
      final session = VolwardSession.test();
      var calls = 0;
      session.capabilityAnalyzeRunnerForTest = (_, __, ___) {
        calls++;
        return jsonEncode({'result': _resultPayload()});
      };
      final gateway = ProductionAiAnalysisGateway(session: session);

      await gateway.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.largeFiles,
        options: const AnalysisOptions(rootPath: '', cursor: 'cursor-a'),
      );
      await gateway.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.largeFiles,
        options: const AnalysisOptions(rootPath: '', cursor: 'cursor-a'),
      );

      expect(calls, 2, reason: 'paginated pages are never cached');
    });
  });
}

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
      'group_id': 'group:/Users/me/Downloads/project/zip',
      'group_path': '/Users/me/Downloads/project',
      'title': 'project · zip',
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
          'evidence': ['size_bytes:50000000'],
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
