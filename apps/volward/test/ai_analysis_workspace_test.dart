import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_analysis_gateway.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/theme/volward_theme.dart';
import 'package:volward/volward_session.dart';
import 'package:volward/widgets/ai_analysis_workspace.dart';

const candidatePayload = '''
{
  "pre_classified": [],
  "unknown_candidates": [
    {
      "path": "/tmp/safe.cache",
      "size_bytes": 100,
      "is_dir": false
    }
  ],
  "estimated_input_tokens": 200,
  "has_existing_result": false,
  "truncated": false,
  "candidates_total_before_cap": 1,
  "result_cache_key": "cache-key",
  "root_path": "/home"
}
''';

class _FakeGateway implements AiAnalysisGateway {
  AiMode mode = AiMode.byok;
  AiProvider? provider;
  bool privacyAccepted = true;
  String? candidatesJson;
  final cache = <String, String>{};
  final deleteReports = <Map<String, dynamic>>[];
  final deleteCalls =
      <({List<String> targets, bool dryRun, bool rescanAfterDelete})>[];
  final candidateRequests = <String>[];

  @override
  Future<AiMode> getMode() async => mode;

  @override
  Future<AiProvider?> resolveProvider() async => provider;

  @override
  Future<bool> isPrivacyAccepted() async => privacyAccepted;

  @override
  Future<void> setPrivacyAccepted(bool value) async {
    privacyAccepted = value;
  }

  @override
  Future<String?> buildCandidates(String snapshotId) async {
    candidateRequests.add(snapshotId);
    return candidatesJson;
  }

  @override
  String? loadResult(String key) => cache[key];

  @override
  bool saveResult(String snapshotId, String resultJson) {
    cache[snapshotId] = resultJson;
    return true;
  }

  @override
  Future<Map<String, dynamic>> deleteEntries(
    List<String> targets, {
    bool dryRun = false,
    bool rescanAfterDelete = false,
  }) async {
    deleteCalls.add((
      targets: List.of(targets),
      dryRun: dryRun,
      rescanAfterDelete: rescanAfterDelete,
    ));
    return deleteReports.removeAt(0);
  }
}

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
    deleteCalls.add((
      targets: List.of(targets),
      dryRun: dryRun,
      rescan: rescanAfterDelete,
    ));
    return {'deleted_count': targets.length, 'freed_bytes': 32};
  }
}

Widget _workspaceShell(
  _FakeGateway gateway, {
  ValueChanged<bool>? onDeletingChanged,
  VoidCallback? onDeleteCompleted,
  VoidCallback? onExit,
  VoidCallback? onOpenSettings,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: buildVolwardTheme(brightness: Brightness.light),
    home: Scaffold(
      body: AiAnalysisWorkspace(
        snapshotId: 'snapshot-1',
        targetLabel: 'Home',
        gateway: gateway,
        onExit: onExit ?? () {},
        onOpenSettings: onOpenSettings ?? () {},
        onDeletingChanged: onDeletingChanged ?? (_) {},
        onDeleteCompleted: onDeleteCompleted ?? () {},
      ),
    ),
  );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for the expected workspace phase');
}

void main() {
  test(
    'production gateway delegates snapshot-scoped native operations',
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
    },
  );

  group('AiCandidate / AiVerdict fromJson', () {
    test('AiCandidate round-trip via fromJson/toJson', () {
      final raw = {
        'path': '/Users/x/Projects/old-app/node_modules',
        'size_bytes': 47185920,
        'is_dir': true,
        'child_count': 2847,
        'extension': null,
      };
      final candidate = AiCandidate.fromJson(raw);
      expect(candidate.path, raw['path']);
      expect(candidate.sizeBytes, 47185920);
      expect(candidate.isDir, isTrue);
      expect(candidate.childCount, 2847);
      expect(candidate.extension, isNull);

      final encoded = candidate.toJson();
      expect(encoded['path'], candidate.path);
      expect(encoded['size_bytes'], candidate.sizeBytes);
      expect(encoded['is_dir'], isTrue);
      expect(encoded['child_count'], 2847);
      expect(encoded.containsKey('extension'), isFalse);

      final again = AiCandidate.fromJson(encoded);
      expect(again.path, candidate.path);
      expect(again.sizeBytes, candidate.sizeBytes);
      expect(again.isDir, candidate.isDir);
      expect(again.childCount, candidate.childCount);
    });

    test('AiCandidate fromJson with extension', () {
      final candidate = AiCandidate.fromJson({
        'path': '/tmp/foo.xyz',
        'size_bytes': 12,
        'is_dir': false,
        'extension': '.xyz',
      });
      expect(candidate.extension, '.xyz');
      expect(candidate.toJson()['extension'], '.xyz');
    });

    test('AiCandidate carries member_paths for aggregates', () {
      final candidate = AiCandidate.fromJson({
        'path': '/Users/x/big_dir',
        'size_bytes': 2500,
        'is_dir': true,
        'child_count': 25,
        'member_paths': ['/Users/x/big_dir/a.dat', '/Users/x/big_dir/b.dat'],
      });
      expect(candidate.memberPaths, hasLength(2));
      expect(candidate.memberPaths.first, '/Users/x/big_dir/a.dat');
      expect(candidate.toJson()['member_paths'], candidate.memberPaths);
    });

    test('AiCandidate without member_paths defaults to empty', () {
      final candidate = AiCandidate.fromJson({
        'path': '/tmp/foo.xyz',
        'size_bytes': 12,
        'is_dir': false,
      });
      expect(candidate.memberPaths, isEmpty);
      expect(candidate.toJson().containsKey('member_paths'), isFalse);
    });

    test('AiVerdict fromJson', () {
      final verdict = AiVerdict.fromJson({
        'path': '/Users/x/weird.cache',
        'verdict': 'safe_to_remove',
        'confidence': 'high',
        'reason': 'build cache',
      });
      expect(verdict.path, '/Users/x/weird.cache');
      expect(verdict.verdict, 'safe_to_remove');
      expect(verdict.confidence, 'high');
      expect(verdict.reason, 'build cache');
    });
  });

  testWidgets('workspace bootstraps inline without Scaffold or AppBar', (
    tester,
  ) async {
    final gateway = _FakeGateway()
      ..candidatesJson = jsonEncode({
        'pre_classified': const [],
        'unknown_candidates': const [],
        'estimated_input_tokens': 200,
        'has_existing_result': false,
        'truncated': false,
        'candidates_total_before_cap': 0,
        'result_cache_key': 'cache-key',
        'root_path': '/home',
      });

    await tester.pumpWidget(_workspaceShell(gateway));
    await _pumpUntilFound(tester, find.byKey(AiAnalysisWorkspace.settingsKey));

    expect(find.byKey(AiAnalysisWorkspace.workspaceKey), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AiAnalysisWorkspace.workspaceKey),
        matching: find.byType(Scaffold),
      ),
      findsNothing,
    );
    expect(find.byType(AppBar), findsNothing);
    expect(gateway.candidateRequests, ['snapshot-1']);
  });

  testWidgets('cached result choices stay inline during bootstrap', (
    tester,
  ) async {
    final payload = Map<String, dynamic>.from(
      jsonDecode(candidatePayload) as Map,
    )..['has_existing_result'] = true;
    final gateway = _FakeGateway()
      ..candidatesJson = jsonEncode(payload)
      ..cache['cache-key'] = '{"entries":[]}';

    await tester.pumpWidget(_workspaceShell(gateway));
    await _pumpUntilFound(
      tester,
      find.byKey(AiAnalysisWorkspace.loadPreviousKey),
    );

    expect(find.byKey(AiAnalysisWorkspace.loadPreviousKey), findsOneWidget);
    expect(find.byKey(AiAnalysisWorkspace.analyzeAgainKey), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
