import 'package:flutter_test/flutter_test.dart';
import 'package:volward/capabilities/capability_models.dart';

void main() {
  test('parses and serializes a versioned large-files result', () {
    final result = CapabilityAnalysisResult.fromJson(_resultPayload());

    expect(result.schemaVersion, 1);
    expect(result.capability, Capability.largeFiles);
    expect(result.capabilityLevel, CapabilityLevel.fullPath);
    expect(result.groups.single.items.single.id, 'entry-42');
    expect(result.groups.single.defaultExpanded, isTrue);
    expect(result.toJson(), _resultPayload());
  });

  test('accepts absent optional result and item fields', () {
    final payload = _resultPayload()
      ..remove('next_cursor')
      ..['groups'] = [
        {
          ..._resultPayload()['groups'][0] as Map<String, dynamic>,
          'items': [
            {
                ...((_resultPayload()['groups'][0]
                                as Map<String, dynamic>)['items']
                            as List<dynamic>)
                        .single
                    as Map<String, dynamic>,
                'modified_at_ms': null,
                'delete_target': null,
              }
              ..remove('modified_at_ms')
              ..remove('delete_target')
              ..remove('preview'),
          ],
        },
      ];

    final result = CapabilityAnalysisResult.fromJson(payload);
    final item = result.groups.single.items.single;
    expect(result.nextCursor, isNull);
    expect(item.modifiedAtMs, isNull);
    expect(item.deleteTarget, isNull);
    expect(item.preview, isNull);
  });

  test('keeps unknown recommendation values and stable item IDs', () {
    final payload = _resultPayload();
    final item =
        ((payload['groups'] as List<dynamic>).single
                as Map<String, dynamic>)['items']
            as List<dynamic>;
    (item.single as Map<String, dynamic>)['recommendation'] = 'future_value';

    final parsed = CapabilityAnalysisResult.fromJson(
      payload,
    ).groups.single.items.single;
    expect(parsed.id, 'entry-42');
    expect(parsed.recommendation, Recommendation.unknown);
    expect(parsed.recommendationValue, 'future_value');
    expect(parsed.copyWith(displayName: 'renamed').id, 'entry-42');
    expect(parsed.toJson()['recommendation'], 'future_value');
  });

  test('reports malformed fields with capability context', () {
    final payload = _resultPayload();
    final item =
        ((payload['groups'] as List<dynamic>).single
                as Map<String, dynamic>)['items']
            as List<dynamic>;
    (item.single as Map<String, dynamic>)['size_bytes'] = 'not-a-byte-count';

    expect(
      () => CapabilityAnalysisResult.fromJson(payload),
      throwsA(
        isA<FormatException>()
            .having(
              (error) => error.message,
              'message',
              contains('large_files'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('size_bytes'),
            ),
      ),
    );
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
