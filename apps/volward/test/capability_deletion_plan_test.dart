import 'package:flutter_test/flutter_test.dart';
import 'package:volward/capabilities/capability_models.dart';

void main() {
  group('capability deletion plan contract', () {
    test('parses targets, blocked paths and snapshot binding', () {
      final plan = DeletionPlan.fromJson(
        {
          'snapshot_id': 'snapshot-1',
          'target_count': 2,
          'target_bytes': 300,
          'targets': ['/root/a.bin', '/root/b.bin'],
          'blocked_targets': ['/System/x.bin'],
          'requires_confirmation': true,
        },
        capability: 'duplicate_files',
        fieldPrefix: 'deletion_plan',
      );

      expect(plan.snapshotId, 'snapshot-1');
      expect(plan.targetCount, 2);
      expect(plan.targetBytes, 300);
      expect(plan.targets, ['/root/a.bin', '/root/b.bin']);
      expect(plan.blockedTargets, ['/System/x.bin']);
      expect(plan.requiresConfirmation, isTrue);
    });

    test('rejects plans without mandatory confirmation', () {
      expect(
        () => DeletionPlan.fromJson(
          {
            'snapshot_id': 'snapshot-1',
            'target_count': 0,
            'target_bytes': 0,
            'targets': <String>[],
            'blocked_targets': <String>[],
            'requires_confirmation': false,
          },
          capability: 'cleanup_candidates',
          fieldPrefix: 'deletion_plan',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('requires_confirmation'),
          ),
        ),
      );
    });

    test('keeps blocked targets separate from deletable targets', () {
      final plan = DeletionPlan.fromJson(
        {
          'snapshot_id': 'snapshot-1',
          'target_count': 1,
          'target_bytes': 100,
          'targets': ['/root/cache.bin'],
          'blocked_targets': ['/System/password.db'],
          'requires_confirmation': true,
        },
        capability: 'browser_privacy',
        fieldPrefix: 'deletion_plan',
      );

      expect(plan.targets.single, '/root/cache.bin');
      expect(plan.blockedTargets.single, '/System/password.db');
      expect(plan.targets, isNot(contains(plan.blockedTargets.single)));
    });
  });
}
