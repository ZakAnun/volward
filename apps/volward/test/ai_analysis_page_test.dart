import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_analysis_gateway.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai_analysis_page.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/volward_session.dart';

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
  test('production gateway delegates snapshot-scoped native operations', () async {
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

  group('AiCandidate / AiVerdict fromJson', () {
    test('AiCandidate round-trip via fromJson/toJson', () {
      final raw = {
        'path': '/Users/x/Projects/old-app/node_modules',
        'size_bytes': 47185920,
        'is_dir': true,
        'child_count': 2847,
        'extension': null,
      };
      final c = AiCandidate.fromJson(raw);
      expect(c.path, raw['path']);
      expect(c.sizeBytes, 47185920);
      expect(c.isDir, isTrue);
      expect(c.childCount, 2847);
      expect(c.extension, isNull);

      final encoded = c.toJson();
      expect(encoded['path'], c.path);
      expect(encoded['size_bytes'], c.sizeBytes);
      expect(encoded['is_dir'], isTrue);
      expect(encoded['child_count'], 2847);
      expect(encoded.containsKey('extension'), isFalse);

      final again = AiCandidate.fromJson(encoded);
      expect(again.path, c.path);
      expect(again.sizeBytes, c.sizeBytes);
      expect(again.isDir, c.isDir);
      expect(again.childCount, c.childCount);
    });

    test('AiCandidate fromJson with extension', () {
      final c = AiCandidate.fromJson({
        'path': '/tmp/foo.xyz',
        'size_bytes': 12,
        'is_dir': false,
        'extension': '.xyz',
      });
      expect(c.extension, '.xyz');
      expect(c.toJson()['extension'], '.xyz');
    });

    test('AiCandidate carries member_paths for aggregates', () {
      final c = AiCandidate.fromJson({
        'path': '/Users/x/big_dir',
        'size_bytes': 2500,
        'is_dir': true,
        'child_count': 25,
        'member_paths': ['/Users/x/big_dir/a.dat', '/Users/x/big_dir/b.dat'],
      });
      expect(c.memberPaths, hasLength(2));
      expect(c.memberPaths.first, '/Users/x/big_dir/a.dat');
      expect(c.toJson()['member_paths'], c.memberPaths);
    });

    test('AiCandidate without member_paths defaults to empty', () {
      final c = AiCandidate.fromJson({
        'path': '/tmp/foo.xyz',
        'size_bytes': 12,
        'is_dir': false,
      });
      expect(c.memberPaths, isEmpty);
      expect(c.toJson().containsKey('member_paths'), isFalse);
    });

    test('AiVerdict fromJson', () {
      final v = AiVerdict.fromJson({
        'path': '/Users/x/weird.cache',
        'verdict': 'safe_to_remove',
        'confidence': 'high',
        'reason': 'build cache',
      });
      expect(v.path, '/Users/x/weird.cache');
      expect(v.verdict, 'safe_to_remove');
      expect(v.confidence, 'high');
      expect(v.reason, 'build cache');
    });
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
    expect(find.text('AI Disk Analysis'), findsOneWidget);
  });
}
