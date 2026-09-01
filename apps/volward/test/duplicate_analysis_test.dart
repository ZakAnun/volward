import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/capabilities/capability_models.dart';
import 'package:volward/volward_session.dart';

void main() {
  group('duplicate analysis result', () {
    test('decodes keep and review items with hash evidence', () async {
      final session = VolwardSession.test();
      session.capabilityAnalyzeRunnerForTest = (_, __, ___) =>
          jsonEncode({'result': _duplicatePayload()});

      final result = await session.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.duplicateFiles,
      );

      expect(result.capability, Capability.duplicateFiles);
      expect(result.summary.itemCount, 2);
      expect(result.summary.keptCount, 1);
      expect(result.summary.reviewCount, 1);
      final items = result.groups.single.items;
      final kept = items.singleWhere((item) => item.recommendation == Recommendation.keep);
      final review = items.singleWhere(
        (item) => item.recommendation == Recommendation.reviewNeeded,
      );
      expect(kept.deleteTarget, isNull);
      expect(review.deleteTarget, review.path);
      expect(
        review.evidence.any((evidence) => evidence.startsWith('full_hash:')),
        isTrue,
      );
      expect(result.deletionPlan.targetCount, 1);
      expect(result.deletionPlan.requiresConfirmation, isTrue);
    });

    test('groups by direct child directory', () async {
      final session = VolwardSession.test();
      session.capabilityAnalyzeRunnerForTest = (_, __, ___) =>
          jsonEncode({'result': _duplicatePayload()});

      final result = await session.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.duplicateFiles,
      );

      expect(result.groups.single.groupPath, '/Users/me/Downloads');
      expect(result.groups.single.defaultExpanded, isTrue);
    });
  });
}

Map<String, dynamic> _duplicatePayload() => {
  'schema_version': 1,
  'capability': 'duplicate_files',
  'snapshot_id': 'snapshot-1',
  'root_path': '/Users/me/Downloads',
  'analyzer_version': 'duplicate_files-v1',
  'generated_at_ms': 0,
  'capability_level': 'full_path',
  'summary': {
    'item_count': 2,
    'total_bytes': 40,
    'safe_count': 0,
    'review_count': 1,
    'kept_count': 1,
    'truncated': false,
  },
  'groups': [
    {
      'group_id': 'group:/Users/me/Downloads',
      'group_path': '/Users/me/Downloads',
      'title': 'Downloads',
      'item_count': 2,
      'total_bytes': 40,
      'safe_count': 0,
      'review_count': 1,
      'kept_count': 1,
      'default_expanded': true,
      'items': [
        {
          'id': '/Users/me/Downloads/backup/b.bin',
          'path': '/Users/me/Downloads/backup/b.bin',
          'display_name': 'b.bin',
          'size_bytes': 20,
          'is_directory': false,
          'modified_at_ms': null,
          'recommendation': 'keep',
          'confidence': 'high',
          'reason': 'duplicate',
          'evidence': ['size_bytes:20', 'full_hash:abc123'],
          'delete_target': null,
          'preview': {'kind': 'file', 'locatable': true},
        },
        {
          'id': '/Users/me/Downloads/src/a.bin',
          'path': '/Users/me/Downloads/src/a.bin',
          'display_name': 'a.bin',
          'size_bytes': 20,
          'is_directory': false,
          'modified_at_ms': null,
          'recommendation': 'review_needed',
          'confidence': 'high',
          'reason': 'duplicate',
          'evidence': ['size_bytes:20', 'full_hash:abc123'],
          'delete_target': '/Users/me/Downloads/src/a.bin',
          'preview': {'kind': 'file', 'locatable': true},
        },
      ],
    },
  ],
  'next_cursor': null,
  'deletion_plan': {
    'snapshot_id': 'snapshot-1',
    'target_count': 1,
    'target_bytes': 20,
    'targets': ['/Users/me/Downloads/src/a.bin'],
    'blocked_targets': [],
    'requires_confirmation': true,
  },
  'warnings': [],
};
