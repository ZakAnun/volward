import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/capabilities/capability_models.dart';
import 'package:volward/volward_session.dart';

void main() {
  group('platform capability fallback', () {
    test('decodes GuidedOnly results with warnings and blocked targets', () async {
      final session = VolwardSession.test();
      session.capabilityAnalyzeRunnerForTest = (_, __, ___) =>
          jsonEncode({'result': _guidedOnlyPayload()});

      final result = await session.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.browserPrivacy,
      );

      expect(result.capabilityLevel, CapabilityLevel.guidedOnly);
      expect(result.warnings, contains(contains('running')));
      expect(result.deletionPlan.targetCount, 0);
      expect(result.deletionPlan.blockedTargets, isNotEmpty);
      expect(result.summary.reviewCount, result.summary.itemCount);
    });

    test('decodes FullPath application results with keep + residual targets', () async {
      final session = VolwardSession.test();
      session.capabilityAnalyzeRunnerForTest = (_, __, ___) =>
          jsonEncode({'result': _applicationsPayload()});

      final result = await session.analyzeCapability(
        snapshotId: 'snapshot-1',
        capability: Capability.applications,
      );

      expect(result.capabilityLevel, CapabilityLevel.fullPath);
      final kept = result.groups
          .expand((group) => group.items)
          .singleWhere((item) => item.recommendation == Recommendation.keep);
      expect(
        kept.evidence.any((evidence) => evidence.startsWith('uninstall_hint:')),
        isTrue,
      );
      expect(result.deletionPlan.targetCount, 1);
      expect(result.deletionPlan.targets.single, endsWith('Application Support/Example'));
    });
  });
}

Map<String, dynamic> _guidedOnlyPayload() => {
  'schema_version': 1,
  'capability': 'browser_privacy',
  'snapshot_id': 'snapshot-1',
  'root_path': '/',
  'analyzer_version': 'browser_privacy-v1',
  'generated_at_ms': 0,
  'capability_level': 'guided_only',
  'summary': {
    'item_count': 1,
    'total_bytes': 0,
    'safe_count': 0,
    'review_count': 1,
    'kept_count': 0,
    'truncated': false,
  },
  'groups': [
    {
      'group_id': 'group:/',
      'group_path': '/',
      'title': '',
      'item_count': 1,
      'total_bytes': 0,
      'safe_count': 0,
      'review_count': 1,
      'kept_count': 0,
      'default_expanded': true,
      'items': [
        {
          'id': '/db/Databases',
          'path': '/db/Databases',
          'display_name': 'Databases',
          'size_bytes': 0,
          'is_directory': true,
          'modified_at_ms': null,
          'recommendation': 'review_needed',
          'confidence': 'medium',
          'reason': 'browser:databases',
          'evidence': ['category:databases', 'estimated_bytes:0', 'guided_only'],
          'delete_target': null,
          'preview': {'kind': 'directory', 'locatable': true},
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
    'blocked_targets': ['/db/Login Data'],
    'requires_confirmation': true,
  },
  'warnings': ['Chrome is running; browser data changes may be in flight'],
};

Map<String, dynamic> _applicationsPayload() => {
  'schema_version': 1,
  'capability': 'applications',
  'snapshot_id': 'snapshot-1',
  'root_path': '/',
  'analyzer_version': 'applications-v1',
  'generated_at_ms': 0,
  'capability_level': 'full_path',
  'summary': {
    'item_count': 2,
    'total_bytes': 0,
    'safe_count': 0,
    'review_count': 1,
    'kept_count': 1,
    'truncated': false,
  },
  'groups': [
    {
      'group_id': 'group:/',
      'group_path': '/',
      'title': '',
      'item_count': 2,
      'total_bytes': 0,
      'safe_count': 0,
      'review_count': 1,
      'kept_count': 1,
      'default_expanded': false,
      'items': [
        {
          'id': '/Applications/Example.app',
          'path': '/Applications/Example.app',
          'display_name': 'Example',
          'size_bytes': 0,
          'is_directory': true,
          'modified_at_ms': null,
          'recommendation': 'keep',
          'confidence': 'high',
          'reason': 'application',
          'evidence': ['confidence:high', 'uninstall_hint:open -R /Applications/Example.app'],
          'delete_target': null,
          'preview': {'kind': 'directory', 'locatable': true},
        },
        {
          'id': '/Library/Application Support/Example',
          'path': '/Library/Application Support/Example',
          'display_name': 'Example',
          'size_bytes': 0,
          'is_directory': true,
          'modified_at_ms': null,
          'recommendation': 'review_needed',
          'confidence': 'medium',
          'reason': 'application_residual',
          'evidence': ['owned_by:Example', 'confidence:medium'],
          'delete_target': '/Library/Application Support/Example',
          'preview': {'kind': 'directory', 'locatable': true},
        },
      ],
    },
  ],
  'next_cursor': null,
  'deletion_plan': {
    'snapshot_id': 'snapshot-1',
    'target_count': 1,
    'target_bytes': 0,
    'targets': ['/Library/Application Support/Example'],
    'blocked_targets': [],
    'requires_confirmation': true,
  },
  'warnings': [],
};
