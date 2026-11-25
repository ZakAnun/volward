import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/ai_result_groups.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_state.dart';

void main() {
  test('results state defensively copies enriched collections', () {
    final groups = <AiResultGroup>[];
    final visible = <AiWorkspaceVisibleResultGroup>[];
    final limits = <String, int>{'a': 1};
    final expandedReview = <String>{'p'};

    final state = AiWorkspaceResultsState(
      groups: groups,
      visibleGroups: visible,
      expandedGroupItemLimits: limits,
      expandedReviewPaths: expandedReview,
    );

    groups.add(_group('/x'));
    visible.add(
      AiWorkspaceVisibleResultGroup(
        group: _group('/y'),
        items: const [],
        totalBytes: 1,
        actionableCount: 0,
      ),
    );
    limits['b'] = 2;
    expandedReview.add('q');

    expect(state.groups, isEmpty);
    expect(state.visibleGroups, isEmpty);
    expect(state.expandedGroupItemLimits, {'a': 1});
    expect(state.expandedReviewPaths, {'p'});
  });

  test('visible result group preserves its payload', () {
    final group = _group('/downloads');
    final visible = AiWorkspaceVisibleResultGroup(
      group: group,
      items: const [],
      totalBytes: 42,
      actionableCount: 3,
    );

    expect(visible.group.path, '/downloads');
    expect(visible.totalBytes, 42);
    expect(visible.actionableCount, 3);
  });
}

AiResultGroup _group(String path) {
  return _GroupFactory.group(path);
}

class _GroupFactory {
  _GroupFactory._();

  static AiResultGroup group(String path) {
    // AiResultGroup has a private constructor, so build it through the
    // public grouping API with one safe-to-remove item.
    return groupAiResults(
      [
        AiVerdict(
          path: '$path/file',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'test',
        ),
      ],
      {'$path/file': 10},
    ).first;
  }
}
