import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/capabilities/capability_models.dart';
import 'package:volward/capabilities/capability_result_cache.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/volward_session.dart';

void main() {
  group('capability result cache invalidation', () {
    test('identical requests hit; snapshot change invalidates', () async {
      final session = VolwardSession.test();
      var calls = 0;
      session.capabilityAnalyzeRunnerForTest = (snapshotId, _, __) {
        calls++;
        return jsonEncode({'result': _resultPayload(snapshotId)});
      };

      await session.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.largeFiles,
      );
      await session.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.largeFiles,
      );
      expect(calls, 1, reason: 'identical request hits the cache');

      session.setSnapshotForTest(_state('snapshot-2'));
      await session.analyzeCapability(
        snapshotId: 'snapshot-2',
        capability: Capability.largeFiles,
      );
      expect(calls, 2, reason: 'snapshot change must invalidate');
    });

    test('directory refresh invalidates cached results', () async {
      final session = VolwardSession.test();
      var calls = 0;
      session.capabilityAnalyzeRunnerForTest = (snapshotId, _, __) {
        calls++;
        return jsonEncode({'result': _resultPayload(snapshotId)});
      };

      await session.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.largeFiles,
      );
      session.updateSnapshotForTest(
        _state('snapshot-1'),
        affectedPrefix: '/root/Documents',
      );
      await session.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.largeFiles,
      );
      expect(calls, 2, reason: 'directory refresh must invalidate');
    });

    test('options are part of the cache key', () {
      final cache = CapabilityAnalysisCache();
      const optionsA = AnalysisOptions(rootPath: '');
      const optionsB = AnalysisOptions(
        rootPath: '',
        largeFileThresholdBytes: 100000000,
        largeFileThresholdPreset: LargeFileThresholdPreset.mb100,
      );

      expect(
        cache.key('s1', Capability.largeFiles, optionsA),
        isNot(cache.key('s1', Capability.largeFiles, optionsB)),
      );
    });

    test('analyzer and schema versions are part of the cache key', () {
      final cache = CapabilityAnalysisCache();
      const options = AnalysisOptions(rootPath: '');

      final versionA = cache.key(
        's1',
        Capability.largeFiles,
        options,
        analyzerVersion: 'large_files-v1',
      );
      final versionB = cache.key(
        's1',
        Capability.largeFiles,
        options,
        analyzerVersion: 'large_files-v2',
      );
      expect(versionA, isNot(versionB));

      final schemaA = cache.key(
        's1',
        Capability.largeFiles,
        options,
        schemaVersion: 1,
      );
      final schemaB = cache.key(
        's1',
        Capability.largeFiles,
        options,
        schemaVersion: 2,
      );
      expect(schemaA, isNot(schemaB));
    });
  });
}

ScanSnapshotState _state(String snapshotId) => ScanSnapshotState.fromWire({
  'snapshot_id': snapshotId,
  'entries': <Map<String, dynamic>>[],
  'stats': <String, dynamic>{},
});

Map<String, dynamic> _resultPayload(String snapshotId) => {
  'schema_version': 1,
  'capability': 'large_files',
  'snapshot_id': snapshotId,
  'root_path': '/root',
  'analyzer_version': 'large_files-v1',
  'generated_at_ms': 0,
  'capability_level': 'full_path',
  'summary': {
    'item_count': 0,
    'total_bytes': 0,
    'safe_count': 0,
    'review_count': 0,
    'kept_count': 0,
    'truncated': false,
  },
  'groups': <Map<String, dynamic>>[],
  'next_cursor': null,
  'deletion_plan': {
    'snapshot_id': snapshotId,
    'target_count': 0,
    'target_bytes': 0,
    'targets': <String>[],
    'blocked_targets': <String>[],
    'requires_confirmation': true,
  },
  'warnings': <String>[],
};
