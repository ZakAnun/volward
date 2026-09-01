import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/capabilities/capability_models.dart';
import 'package:volward/volward_session.dart';

void main() {
  group('similar photo analysis result', () {
    test('decodes grouped photos with metadata evidence', () async {
      final session = VolwardSession.test();
      session.capabilityAnalyzeRunnerForTest = (_, __, ___) =>
          jsonEncode({'result': _similarPhotosPayload()});

      final result = await session.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.similarPhotos,
        options: const AnalysisOptions(
          rootPath: '',
          similarityPreset: SimilarityPreset.loose,
        ),
      );

      expect(result.capability, Capability.similarPhotos);
      expect(result.summary.itemCount, 3);
      expect(result.summary.keptCount, 1);
      expect(result.summary.reviewCount, 2);
      final items = result.groups.single.items;
      final kept = items.singleWhere((item) => item.recommendation == Recommendation.keep);
      expect(kept.deleteTarget, isNull);
      expect(
        kept.evidence.any((evidence) => evidence.startsWith('width:')),
        isTrue,
      );
      expect(
        kept.evidence.any((evidence) => evidence.startsWith('ahash:')),
        isTrue,
      );
      expect(
        kept.evidence.any((evidence) => evidence == 'preset:loose'),
        isTrue,
      );
      expect(result.deletionPlan.targetCount, 2);
      expect(result.deletionPlan.requiresConfirmation, isTrue);
    });

    test('decode failures stay review-only without targets', () async {
      final payload = _similarPhotosPayload();
      (payload['groups'] as List<dynamic>).first['items'] = [
        {
          'id': '/photos/corrupt.png',
          'path': '/photos/corrupt.png',
          'display_name': 'corrupt.png',
          'size_bytes': 10,
          'is_directory': false,
          'modified_at_ms': null,
          'recommendation': 'review_needed',
          'confidence': 'low',
          'reason': 'similar_photo_decode_failed',
          'evidence': ['decode_failure:decode_failed'],
          'delete_target': null,
          'preview': {'kind': 'image', 'locatable': true},
        },
      ];
      (payload['deletion_plan'] as Map<String, dynamic>)
        ..['target_count'] = 0
        ..['target_bytes'] = 0
        ..['targets'] = <String>[];
      final session = VolwardSession.test();
      session.capabilityAnalyzeRunnerForTest = (_, __, ___) =>
          jsonEncode({'result': payload});

      final result = await session.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.similarPhotos,
      );

      final corrupt = result.groups.single.items.single;
      expect(corrupt.recommendation, Recommendation.reviewNeeded);
      expect(corrupt.deleteTarget, isNull);
      expect(result.deletionPlan.targetCount, 0);
    });
  });
}

Map<String, dynamic> _similarPhotosPayload() => {
  'schema_version': 1,
  'capability': 'similar_photos',
  'snapshot_id': 'snapshot-1',
  'root_path': '/photos',
  'analyzer_version': 'similar_photos-v1',
  'generated_at_ms': 0,
  'capability_level': 'full_path',
  'summary': {
    'item_count': 3,
    'total_bytes': 3000,
    'safe_count': 0,
    'review_count': 2,
    'kept_count': 1,
    'truncated': false,
  },
  'groups': [
    {
      'group_id': 'group:/photos',
      'group_path': '/photos',
      'title': 'photos',
      'item_count': 3,
      'total_bytes': 3000,
      'safe_count': 0,
      'review_count': 2,
      'kept_count': 1,
      'default_expanded': false,
      'items': [
        {
          'id': '/photos/original.png',
          'path': '/photos/original.png',
          'display_name': 'original.png',
          'size_bytes': 1000,
          'is_directory': false,
          'modified_at_ms': 1700000000000,
          'recommendation': 'keep',
          'confidence': 'medium',
          'reason': 'similar_photo',
          'evidence': [
            'size_bytes:1000',
            'width:64',
            'height:64',
            'ahash:0000000000000000',
            'preset:loose',
            'preset_version:1',
            'modified_at_ms:1700000000000',
          ],
          'delete_target': null,
          'preview': {'kind': 'image', 'locatable': true},
        },
        {
          'id': '/photos/resized.png',
          'path': '/photos/resized.png',
          'display_name': 'resized.png',
          'size_bytes': 1000,
          'is_directory': false,
          'modified_at_ms': null,
          'recommendation': 'review_needed',
          'confidence': 'medium',
          'reason': 'similar_photo',
          'evidence': ['width:32', 'height:32', 'ahash:0000000000000001'],
          'delete_target': '/photos/resized.png',
          'preview': {'kind': 'image', 'locatable': true},
        },
        {
          'id': '/photos/rotated.png',
          'path': '/photos/rotated.png',
          'display_name': 'rotated.png',
          'size_bytes': 1000,
          'is_directory': false,
          'modified_at_ms': null,
          'recommendation': 'review_needed',
          'confidence': 'medium',
          'reason': 'similar_photo',
          'evidence': ['width:64', 'height:64', 'ahash:0000000000000002'],
          'delete_target': '/photos/rotated.png',
          'preview': {'kind': 'image', 'locatable': true},
        },
      ],
    },
  ],
  'next_cursor': null,
  'deletion_plan': {
    'snapshot_id': 'snapshot-1',
    'target_count': 2,
    'target_bytes': 2000,
    'targets': ['/photos/resized.png', '/photos/rotated.png'],
    'blocked_targets': [],
    'requires_confirmation': true,
  },
  'warnings': [],
};
