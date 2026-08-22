import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_analysis_gateway.dart';
import 'package:volward/ai_analysis_page.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/volward_session.dart';
import 'package:volward/widgets/ai_analysis_workspace.dart';

class _GatewaySession extends VolwardSession {
  _GatewaySession() : super.test();

  final deleteCalls = <({List<String> targets, bool dryRun, bool rescan})>[];
  String? loadedKey;
  String? savedSnapshotId;
  String? savedJson;

  @override
  Future<String?> buildAiCandidatesJsonAsync(String snapshotId) async =>
      '{"snapshot_id":"$snapshotId"}';

  @override
  String? loadAiResultJson(String snapshotId) {
    loadedKey = snapshotId;
    return '{"entries":[]}';
  }

  @override
  bool saveAiResultJson(String snapshotId, String resultJson) {
    savedSnapshotId = snapshotId;
    savedJson = resultJson;
    return true;
  }

  @override
  Future<Map<String, dynamic>> deleteEntries(
    List<String> targets, {
    bool dryRun = false,
    bool rescanAfterDelete = false,
    String? refreshPath,
    Map<String, String>? targetPathById,
  }) async {
    deleteCalls.add(
      (targets: List.of(targets), dryRun: dryRun, rescan: rescanAfterDelete),
    );
    return {'deleted_count': targets.length, 'freed_bytes': 32};
  }
}

void main() {
  test('production gateway delegates snapshot-scoped native operations',
      () async {
    final session = _GatewaySession();
    final gateway = ProductionAiAnalysisGateway(session: session);

    expect(await gateway.buildCandidates('snap-1'), contains('snap-1'));
    expect(gateway.loadResult('cache-1'), contains('entries'));
    expect(gateway.saveResult('snap-1', '{"entries":[]}'), isTrue);
    await gateway.deleteEntries(
      const ['/tmp/a'],
      dryRun: true,
      rescanAfterDelete: false,
    );

    expect(session.loadedKey, 'cache-1');
    expect(session.savedSnapshotId, 'snap-1');
    expect(session.savedJson, '{"entries":[]}');
    expect(session.deleteCalls.single.dryRun, isTrue);
    expect(session.deleteCalls.single.rescan, isFalse);
  });

  testWidgets('AiAnalysisPage smoke construct', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: buildVolwardTheme(brightness: Brightness.light),
        home: const AiAnalysisPage(snapshotId: 'test-snap-id'),
      ),
    );
    // First frame: loading (or error if session unavailable).
    await tester.pump();
    expect(find.byType(AiAnalysisPage), findsOneWidget);
    expect(find.byType(AiAnalysisWorkspace), findsOneWidget);
  });
}
