import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI workspace keeps behavior and rendering responsibilities bounded', () {
    final workspace = File(
      'lib/features/ai_coverage/ai_analysis_workspace.dart',
    );
    final controller = File(
      'lib/features/ai_coverage/controllers/ai_analysis_workspace_page_controller.dart',
    );

    expect(workspace.readAsLinesSync().length, lessThan(1000));
    expect(workspace.readAsStringSync(), isNot(contains('part of')));

    final controllerText = controller.readAsStringSync();
    expect(controllerText, contains('class AiAnalysisWorkspacePageController'));
    expect(controllerText, isNot(contains('BuildContext')));
    expect(controllerText, isNot(contains('_activeContext')));
    expect(controllerText, isNot(contains("part '")));
    expect(controllerText, isNot(contains('package:flutter/material.dart')));
    expect(controllerText, isNot(contains('package:flutter/rendering.dart')));
    expect(controllerText, contains('Future<void> runBootstrap()'));
    expect(controllerText, contains('quickBootstrap(this)'));
    expect(
      controllerText,
      contains('Future<void> startFullCoverageAnalysis()'),
    );
    expect(controllerText, contains('Future<void> refreshVerdictsInternal('));
    expect(controllerText, contains('Future<void> deleteSelected()'));

    expect(
      File(
        'lib/features/ai_coverage/controllers/ai_analysis_workspace_page_view_part.dart',
      ).existsSync(),
      isFalse,
    );

    const viewFiles = <String>[
      'lib/features/ai_coverage/views/ai_analysis_activity_view.dart',
      'lib/features/ai_coverage/views/ai_analysis_precheck_view.dart',
      'lib/features/ai_coverage/views/ai_analysis_purchase_view.dart',
      'lib/features/ai_coverage/views/ai_analysis_overview_view.dart',
      'lib/features/ai_coverage/views/ai_analysis_results_view.dart',
      'lib/features/ai_coverage/views/ai_analysis_detail_list_view.dart',
      'lib/features/ai_coverage/views/ai_analysis_scope_panel_view.dart',
      'lib/features/ai_coverage/views/ai_analysis_coverage_banner_view.dart',
      'lib/features/ai_coverage/views/ai_analysis_workspace_header.dart',
      'lib/features/ai_coverage/views/ai_analysis_workspace_page_view.dart',
      'lib/features/ai_coverage/views/ai_analysis_workspace_body_view.dart',
      'lib/features/ai_coverage/views/ai_analysis_review_item_view.dart',
    ];
    for (final path in viewFiles) {
      final text = File(path).readAsStringSync();
      expect(text, isNot(contains('page_controller')), reason: path);
    }

    final pageView = File(
      'lib/features/ai_coverage/views/ai_analysis_workspace_page_view.dart',
    );
    expect(
      pageView.readAsStringSync(),
      contains('class AiAnalysisWorkspacePageView'),
    );
    final bodyView = File(
      'lib/features/ai_coverage/views/ai_analysis_workspace_body_view.dart',
    );
    expect(
      bodyView.readAsStringSync(),
      contains('class AiAnalysisWorkspaceBodyView'),
    );

    final featureText = Directory('lib/features/ai_coverage')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    for (final singleton in [
      'Analytics.instance',
      'AiSettingsStore.instance',
      'PlatformAuthStore.instance',
      'AiCoverageCoordinator.instance',
      'AiCandidatesMaterializedCache.instance',
    ]) {
      expect(featureText, isNot(contains(singleton)));
    }
  });
}
