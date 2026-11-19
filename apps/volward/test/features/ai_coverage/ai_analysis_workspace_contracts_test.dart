import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/coverage_verdict_store.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_presenter.dart';
import 'package:volward/features/ai_coverage/views/ai_analysis_workspace_view_state.dart';

void main() {
  test('results state defensively copies collections', () {
    final selected = <String>{'a'};
    final decisions = <String, WorkspaceReviewDecision>{
      'a': WorkspaceReviewDecision.include,
    };
    final verdicts = <AiVerdict>[
      const AiVerdict(
        path: '/tmp/a',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'r',
      ),
    ];
    final expanded = <String>{'group-a'};

    final state = AiWorkspaceResultsState(
      selectedPaths: selected,
      reviewDecisions: decisions,
      verdicts: verdicts,
      expandedGroupPaths: expanded,
    );

    selected.add('b');
    decisions['b'] = WorkspaceReviewDecision.keep;
    verdicts.add(
      const AiVerdict(
        path: '/tmp/b',
        verdict: 'keep',
        confidence: 'high',
        reason: 'r',
      ),
    );
    expanded.add('group-b');

    expect(state.selectedPaths, {'a'});
    expect(state.reviewDecisions, {'a': WorkspaceReviewDecision.include});
    expect(state.verdicts.length, 1);
    expect(state.verdicts.single.path, '/tmp/a');
    expect(state.expandedGroupPaths, {'group-a'});
  });

  test('coverage state defensively copies verdict rows', () {
    final rows = <CoverageVerdict>[
      const CoverageVerdict(
        path: '/tmp/a',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'r',
        coverageSource: 'full',
        sizeBytes: 1,
      ),
    ];

    final state = AiWorkspaceCoverageState(verdictRows: rows);
    rows.add(
      const CoverageVerdict(
        path: '/tmp/b',
        verdict: 'keep',
        confidence: 'high',
        reason: 'r',
        coverageSource: 'full',
        sizeBytes: 2,
      ),
    );

    expect(state.verdictRows.length, 1);
    expect(state.verdictRows.single.path, '/tmp/a');
  });

  test('delete state defensively copies retry targets', () {
    final retryTargets = <String>['/tmp/a'];
    final state = AiWorkspaceDeleteState(retryTargets: retryTargets);
    retryTargets.add('/tmp/b');

    expect(state.retryTargets, ['/tmp/a']);
  });

  test('view state copyWith replaces only the requested section', () {
    final state = AiAnalysisWorkspaceViewState();
    final updated = state.copyWith(
      results: AiWorkspaceResultsState(selectedPaths: {'/tmp/a'}),
    );

    expect(updated.results.selectedPaths, {'/tmp/a'});
    expect(identical(updated.bootstrap, state.bootstrap), isTrue);
    expect(identical(updated.overview, state.overview), isTrue);
  });

  test('presenter keeps UI effects outside controllers', () {
    final presenter = FakeWorkspacePresenter();

    presenter.showToast('saved');

    expect(presenter.messages, ['saved']);
  });

  test('view state does not import controller implementations', () {
    final source = File(
      'lib/features/ai_coverage/views/ai_analysis_workspace_view_state.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('controllers/')));
    expect(source, isNot(contains('BuildContext')));
  });
}

class FakeWorkspacePresenter implements AiAnalysisWorkspacePresenter {
  final List<String> messages = <String>[];

  @override
  Future<bool> confirm({
    required String title,
    required String message,
  }) async => true;

  @override
  Future<int?> promptCredits({
    required int? currentValue,
    required int? estimate,
  }) async => estimate;

  @override
  Future<String?> promptText({
    required String title,
    String? initialValue,
  }) async => initialValue;

  @override
  void showToast(String message) => messages.add(message);

  @override
  void openSettings() {}

  @override
  void openDetailPage(String path) {}

  @override
  Future<void> copyText(String value) async {}

  @override
  void exitWorkspace() {}

  @override
  void schedulePostFrame(void Function() callback) => callback();
}
