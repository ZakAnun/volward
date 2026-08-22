import 'dart:async';
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

const verdicts = [
  AiVerdict(
    path: '/tmp/safe.cache',
    verdict: 'safe_to_remove',
    confidence: 'high',
    reason: 'Rebuildable cache',
  ),
  AiVerdict(
    path: '/tmp/review.log',
    verdict: 'review_needed',
    confidence: 'medium',
    reason: 'Old log with uncertain ownership',
  ),
  AiVerdict(
    path: '/tmp/keep.db',
    verdict: 'keep',
    confidence: 'high',
    reason: 'Application data',
  ),
];

class _ResultProvider implements AiProvider {
  _ResultProvider(this.verdicts, {this.quota});

  final List<AiVerdict> verdicts;
  final AiQuotaInfo? quota;
  int analyzeCalls = 0;

  @override
  Future<List<AiVerdict>> analyze(List<AiCandidate> candidates) async {
    analyzeCalls++;
    return verdicts;
  }

  @override
  Future<AiQuotaInfo?> queryQuota() async => quota;
}

class _ThrowingProvider implements AiProvider {
  const _ThrowingProvider(this.error);

  final Object error;

  @override
  Future<List<AiVerdict>> analyze(List<AiCandidate> candidates) async =>
      throw error;

  @override
  Future<AiQuotaInfo?> queryQuota() async => null;
}

String _candidatePayload({
  List<Map<String, Object?>> preClassified = const [],
  List<Map<String, Object?>> unknownCandidates = const [
    {'path': '/tmp/safe.cache', 'size_bytes': 100, 'is_dir': false},
    {'path': '/tmp/review.log', 'size_bytes': 200, 'is_dir': false},
    {'path': '/tmp/keep.db', 'size_bytes': 300, 'is_dir': false},
  ],
  int estimatedTokens = 640,
  bool hasExistingResult = true,
  bool truncated = false,
  int candidatesBeforeCap = 3,
}) {
  return jsonEncode({
    'pre_classified': preClassified,
    'unknown_candidates': unknownCandidates,
    'estimated_input_tokens': estimatedTokens,
    'has_existing_result': hasExistingResult,
    'truncated': truncated,
    'candidates_total_before_cap': candidatesBeforeCap,
    'result_cache_key': 'cache-key',
    'root_path': '/home',
  });
}

class _FakeGateway implements AiAnalysisGateway {
  AiMode mode = AiMode.byok;
  AiProvider? provider;
  bool privacyAccepted = true;
  String? candidatesJson;
  final cache = <String, String>{};
  final deleteReports = <Map<String, dynamic>>[];
  final deleteResponses = <Future<Map<String, dynamic>>>[];
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
    String? snapshotId,
    bool dryRun = false,
    bool rescanAfterDelete = false,
  }) async {
    deleteCalls.add((
      targets: List.of(targets),
      dryRun: dryRun,
      rescanAfterDelete: rescanAfterDelete,
    ));
    if (!dryRun && deleteResponses.isNotEmpty) {
      return deleteResponses.removeAt(0);
    }
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
    String? expectedSnapshotId,
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

Future<void> _openResults(
  WidgetTester tester,
  _FakeGateway gateway, {
  List<AiVerdict> result = verdicts,
  String? candidatesJson,
  ValueChanged<bool>? onDeletingChanged,
  VoidCallback? onDeleteCompleted,
}) async {
  gateway
    ..candidatesJson = candidatesJson ?? _candidatePayload()
    ..provider = _ResultProvider(result);
  await tester.pumpWidget(
    _workspaceShell(
      gateway,
      onDeletingChanged: onDeletingChanged,
      onDeleteCompleted: onDeleteCompleted,
    ),
  );
  await _pumpUntilFound(
    tester,
    find.byKey(AiAnalysisWorkspace.analyzeAgainKey),
  );
  await tester.tap(find.byKey(AiAnalysisWorkspace.analyzeAgainKey));
  await tester.pumpAndSettle();
}

const _aggregateCandidates = '''
{
  "pre_classified": [],
  "unknown_candidates": [
    {
      "path": "/tmp/build-output",
      "size_bytes": 300,
      "is_dir": true,
      "member_paths": ["/tmp/build-output/a.o", "/tmp/build-output/b.o"]
    }
  ],
  "estimated_input_tokens": 12,
  "has_existing_result": true,
  "truncated": false,
  "candidates_total_before_cap": 1,
  "result_cache_key": "aggregate-cache-key",
  "root_path": "/tmp"
}
''';

const _aggregateVerdict = [
  AiVerdict(
    path: '/tmp/build-output',
    verdict: 'safe_to_remove',
    confidence: 'high',
    reason: 'Build output',
  ),
];

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

    test(
      'AiCandidate keeps complete delete members separate from bounded members',
      () {
        final candidate = AiCandidate.fromJson({
          'path': '/Users/x/big_dir',
          'size_bytes': 2500,
          'is_dir': true,
          'member_paths': ['/Users/x/big_dir/a.dat'],
          'delete_member_paths': [
            '/Users/x/big_dir/a.dat',
            '/Users/x/big_dir/b.dat',
          ],
        });
        expect(candidate.memberPaths, ['/Users/x/big_dir/a.dat']);
        expect(candidate.deleteMemberPaths, hasLength(2));
        expect(
          candidate.toJson()['delete_member_paths'],
          candidate.deleteMemberPaths,
        );
      },
    );

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

  testWidgets('precheck shows local unknown token truncation and quota data', (
    tester,
  ) async {
    final gateway = _FakeGateway()
      ..mode = AiMode.platform
      ..provider = _ResultProvider(
        const [],
        quota: const AiQuotaInfo(creditsRemaining: 7, creditsTotal: 20),
      )
      ..candidatesJson = _candidatePayload(
        preClassified: const [
          {
            'path': '/tmp/local-1.cache',
            'size_bytes': 40,
            'confidence': 'high',
            'reason': 'Local cache',
            'deletable': true,
          },
          {
            'path': '/tmp/local-2.cache',
            'size_bytes': 60,
            'confidence': 'high',
            'reason': 'Local cache',
            'deletable': true,
          },
        ],
        truncated: true,
        candidatesBeforeCap: 12,
      );

    await tester.pumpWidget(_workspaceShell(gateway));
    await _pumpUntilFound(
      tester,
      find.byKey(AiAnalysisWorkspace.analyzeAgainKey),
    );

    expect(find.textContaining('2 items pre-identified'), findsOneWidget);
    expect(find.textContaining('3 items will be sent'), findsOneWidget);
    expect(find.textContaining('640 tokens'), findsOneWidget);
    expect(find.textContaining('largest of 12 items'), findsOneWidget);
    expect(find.textContaining('balance 7'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.value == 'Pre-check, step 2 of 5',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'valid cache loads inline and invalid cache remains in precheck',
    (tester) async {
      final validGateway = _FakeGateway()
        ..candidatesJson = _candidatePayload()
        ..cache['cache-key'] = jsonEncode({
          'entries': [
            {
              'path': '/tmp/safe.cache',
              'size_bytes': 100,
              'verdict': 'safe_to_remove',
              'confidence': 'high',
              'reason': 'Rebuildable cache',
            },
          ],
        });
      await tester.pumpWidget(_workspaceShell(validGateway));
      await _pumpUntilFound(
        tester,
        find.byKey(AiAnalysisWorkspace.loadPreviousKey),
      );
      await tester.tap(find.byKey(AiAnalysisWorkspace.loadPreviousKey));
      await tester.pumpAndSettle();
      expect(find.byKey(AiAnalysisWorkspace.resultsListKey), findsOneWidget);

      final invalidGateway = _FakeGateway()
        ..candidatesJson = _candidatePayload()
        ..cache['cache-key'] = 'not-json';
      await tester.pumpWidget(_workspaceShell(invalidGateway));
      await _pumpUntilFound(
        tester,
        find.byKey(AiAnalysisWorkspace.loadPreviousKey),
      );
      await tester.tap(find.byKey(AiAnalysisWorkspace.loadPreviousKey));
      await tester.pumpAndSettle();
      expect(find.byKey(AiAnalysisWorkspace.analyzeAgainKey), findsOneWidget);
      expect(
        find.text('Could not load the previous AI result.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('privacy decline stays in precheck and accept starts analysis', (
    tester,
  ) async {
    final provider = _ResultProvider(verdicts);
    final gateway = _FakeGateway()
      ..privacyAccepted = false
      ..provider = provider
      ..candidatesJson = _candidatePayload();
    await tester.pumpWidget(_workspaceShell(gateway));
    await _pumpUntilFound(
      tester,
      find.byKey(AiAnalysisWorkspace.analyzeAgainKey),
    );

    await tester.tap(find.byKey(AiAnalysisWorkspace.analyzeAgainKey));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(provider.analyzeCalls, 0);
    expect(find.byKey(AiAnalysisWorkspace.analyzeAgainKey), findsOneWidget);

    await tester.tap(find.byKey(AiAnalysisWorkspace.analyzeAgainKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();
    expect(provider.analyzeCalls, 1);
    expect(find.byKey(AiAnalysisWorkspace.resultsListKey), findsOneWidget);
  });

  testWidgets('analysis groups verdicts and keep items cannot be selected', (
    tester,
  ) async {
    await _openResults(tester, _FakeGateway());
    expect(find.text('Safe to Remove (1)'), findsOneWidget);
    expect(find.text('Review Needed (1)'), findsOneWidget);
    expect(find.text('Keep (1)'), findsOneWidget);
    expect(find.text('1 selected · 100 B'), findsOneWidget);

    await tester.tap(find.text('/tmp/keep.db'));
    await tester.pump();
    expect(find.text('1 selected · 100 B'), findsOneWidget);
  });

  testWidgets('selection summary tracks count and bytes', (tester) async {
    await _openResults(tester, _FakeGateway());
    await tester.tap(find.widgetWithText(CheckboxListTile, '/tmp/review.log'));
    await tester.pump();
    expect(find.text('2 selected · 300 B'), findsOneWidget);
  });

  testWidgets(
    'aggregate members are dry-run targets and cancel preserves selection',
    (tester) async {
      final gateway = _FakeGateway()
        ..deleteReports.add({
          'deleted_count': 2,
          'freed_bytes': 300,
          'failed_paths': const [],
        });
      await _openResults(
        tester,
        gateway,
        result: _aggregateVerdict,
        candidatesJson: _aggregateCandidates,
      );

      expect(find.text('1 selected · 300 B'), findsOneWidget);
      await tester.tap(find.byKey(AiAnalysisWorkspace.deleteKey));
      await _pumpUntilFound(tester, find.byType(AlertDialog));

      expect(gateway.deleteCalls.single.dryRun, isTrue);
      expect(gateway.deleteCalls.single.rescanAfterDelete, isFalse);
      expect(gateway.deleteCalls.single.targets, const [
        '/tmp/build-output/a.o',
        '/tmp/build-output/b.o',
      ]);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected · 300 B'), findsOneWidget);
      expect(gateway.deleteCalls, hasLength(1));
    },
  );

  testWidgets(
    'real deletion locks only after confirmation and always unlocks',
    (tester) async {
      final deleteGate = Completer<Map<String, dynamic>>();
      final gateway = _FakeGateway()
        ..deleteReports.add({
          'deleted_count': 1,
          'freed_bytes': 100,
          'failed_paths': const [],
        })
        ..deleteResponses.add(deleteGate.future);
      final deleting = <bool>[];
      await _openResults(tester, gateway, onDeletingChanged: deleting.add);

      await tester.tap(find.byKey(AiAnalysisWorkspace.deleteKey));
      await _pumpUntilFound(tester, find.byType(AlertDialog));
      expect(deleting, isEmpty);
      expect(gateway.deleteCalls, hasLength(1));
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pump();
      expect(deleting, [true]);
      expect(gateway.deleteCalls.last.dryRun, isFalse);
      expect(gateway.deleteCalls.last.rescanAfterDelete, isTrue);

      deleteGate.complete({
        'deleted_count': 1,
        'freed_bytes': 100,
        'failed_paths': const [],
      });
      await tester.pumpAndSettle();
      expect(deleting, [true, false]);
    },
  );

  testWidgets('complete deletion requests rescan and returns to overview', (
    tester,
  ) async {
    final gateway = _FakeGateway()
      ..deleteReports.add({
        'deleted_count': 1,
        'freed_bytes': 100,
        'failed_paths': const [],
      })
      ..deleteReports.add({
        'deleted_count': 1,
        'freed_bytes': 300,
        'failed_paths': const [],
      });
    final deleting = <bool>[];
    var completed = 0;
    await _openResults(
      tester,
      gateway,
      onDeletingChanged: deleting.add,
      onDeleteCompleted: () => completed++,
    );

    await tester.tap(find.byKey(AiAnalysisWorkspace.deleteKey));
    await _pumpUntilFound(tester, find.byType(AlertDialog));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(gateway.deleteCalls.last.rescanAfterDelete, isTrue);
    expect(deleting, [true, false]);
    expect(completed, 1);
  });

  testWidgets('partial deletion stays open with retry and freed bytes', (
    tester,
  ) async {
    final gateway = _FakeGateway()
      ..deleteReports.add({
        'deleted_count': 1,
        'freed_bytes': 300,
        'failed_paths': const [],
      })
      ..deleteReports.add({
        'deleted_count': 1,
        'freed_bytes': 150,
        'failed_paths': ['/tmp/review.log'],
      })
      ..deleteReports.add({
        'deleted_count': 1,
        'freed_bytes': 150,
        'failed_paths': ['/tmp/review.log'],
      });
    await _openResults(tester, gateway);

    await tester.tap(find.byKey(AiAnalysisWorkspace.deleteKey));
    await _pumpUntilFound(tester, find.byType(AlertDialog));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.byKey(AiAnalysisWorkspace.workspaceKey), findsOneWidget);
    expect(
      find.text('1 items could not be removed · 150 B freed'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Return to Overview'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(gateway.deleteCalls.last.dryRun, isTrue);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('late delete completion after exit does not invoke callbacks', (
    tester,
  ) async {
    final deleteGate = Completer<Map<String, dynamic>>();
    final gateway = _FakeGateway()
      ..deleteReports.add({
        'deleted_count': 1,
        'freed_bytes': 100,
        'failed_paths': const [],
      })
      ..deleteResponses.add(deleteGate.future);
    var completed = 0;
    var changes = 0;
    await _openResults(
      tester,
      gateway,
      onDeletingChanged: (_) => changes++,
      onDeleteCompleted: () => completed++,
    );

    await tester.tap(find.byKey(AiAnalysisWorkspace.deleteKey));
    await _pumpUntilFound(tester, find.byType(AlertDialog));
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(changes, 1);

    await tester.pumpWidget(const SizedBox());
    deleteGate.complete({
      'deleted_count': 1,
      'freed_bytes': 100,
      'failed_paths': const [],
    });
    await tester.pumpAndSettle();
    expect(completed, 0);
    expect(changes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing key zero quota and expired session link to Settings', (
    tester,
  ) async {
    var settingsCalls = 0;
    final missingKeyGateway = _FakeGateway()
      ..candidatesJson = _candidatePayload();
    await tester.pumpWidget(
      _workspaceShell(missingKeyGateway, onOpenSettings: () => settingsCalls++),
    );
    await _pumpUntilFound(tester, find.byKey(AiAnalysisWorkspace.settingsKey));
    await tester.tap(find.byKey(AiAnalysisWorkspace.settingsKey));

    final zeroQuotaGateway = _FakeGateway()
      ..mode = AiMode.platform
      ..provider = _ResultProvider(
        const [],
        quota: const AiQuotaInfo(creditsRemaining: 0, creditsTotal: 20),
      )
      ..candidatesJson = _candidatePayload();
    await tester.pumpWidget(
      _workspaceShell(zeroQuotaGateway, onOpenSettings: () => settingsCalls++),
    );
    await _pumpUntilFound(tester, find.byKey(AiAnalysisWorkspace.settingsKey));
    await tester.tap(find.byKey(AiAnalysisWorkspace.settingsKey));

    final expiredGateway = _FakeGateway()
      ..provider = _ThrowingProvider(StateError('session_expired'))
      ..candidatesJson = _candidatePayload();
    await tester.pumpWidget(
      _workspaceShell(expiredGateway, onOpenSettings: () => settingsCalls++),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(AiAnalysisWorkspace.analyzeAgainKey),
    );
    await tester.tap(find.byKey(AiAnalysisWorkspace.analyzeAgainKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AiAnalysisWorkspace.settingsKey));
    expect(settingsCalls, 3);
  });

  const errors = {
    'request_timeout': 'The AI request timed out. Try again.',
    'rate_limited_after_retries': 'The AI service is busy. Try again shortly.',
    'network_error': 'Could not reach the AI service. Check your connection.',
  };
  for (final error in errors.entries) {
    testWidgets('normalizes ${error.key} inline', (tester) async {
      final gateway = _FakeGateway()
        ..candidatesJson = _candidatePayload()
        ..provider = _ThrowingProvider(StateError(error.key));
      await tester.pumpWidget(_workspaceShell(gateway));
      await _pumpUntilFound(
        tester,
        find.byKey(AiAnalysisWorkspace.analyzeAgainKey),
      );
      await tester.tap(find.byKey(AiAnalysisWorkspace.analyzeAgainKey));
      await tester.pumpAndSettle();
      expect(find.text(error.value), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  }

  const configurationErrors = {
    'invalid_api_key': 'No API Key — configure in Settings',
    'empty_api_key': 'No API Key — configure in Settings',
    'ai_contract_unavailable':
        'The installed native library is out of date. Please update Volward to use AI analysis.',
  };
  for (final error in configurationErrors.entries) {
    testWidgets('configuration ${error.key} exposes Settings', (tester) async {
      final gateway = _FakeGateway()
        ..candidatesJson = _candidatePayload()
        ..provider = _ThrowingProvider(StateError(error.key));
      await tester.pumpWidget(_workspaceShell(gateway));
      await _pumpUntilFound(
        tester,
        find.byKey(AiAnalysisWorkspace.analyzeAgainKey),
      );
      await tester.tap(find.byKey(AiAnalysisWorkspace.analyzeAgainKey));
      await _pumpUntilFound(
        tester,
        find.byKey(AiAnalysisWorkspace.settingsKey),
      );
      expect(find.text(error.value), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });
  }

  testWidgets('wide results use list and stable side summary', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    await _openResults(tester, _FakeGateway());

    final listRect = tester.getRect(
      find.byKey(AiAnalysisWorkspace.resultsListKey),
    );
    final summaryRect = tester.getRect(
      find.byKey(AiAnalysisWorkspace.summaryKey),
    );
    expect(summaryRect.left, greaterThanOrEqualTo(listRect.right));
    expect(summaryRect.width, 260);
  });

  testWidgets('compact results place summary above the internal list', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(719, 800);
    addTearDown(tester.view.reset);
    await _openResults(tester, _FakeGateway());

    final listRect = tester.getRect(
      find.byKey(AiAnalysisWorkspace.resultsListKey),
    );
    final summaryRect = tester.getRect(
      find.byKey(AiAnalysisWorkspace.summaryKey),
    );
    expect(summaryRect.bottom, lessThanOrEqualTo(listRect.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long paths expose tooltip and full semantic value', (
    tester,
  ) async {
    const longPath =
        '/Users/example/Library/Application Support/Very Long App/Cache/'
        'nested/folder/that/needs/the/full/path/cache.data';
    final semantics = tester.ensureSemantics();
    try {
      await _openResults(
        tester,
        _FakeGateway(),
        result: const [
          AiVerdict(
            path: longPath,
            verdict: 'safe_to_remove',
            confidence: 'high',
            reason: 'Rebuildable cache',
          ),
        ],
      );

      final tooltip = find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == longPath,
      );
      expect(tooltip, findsOneWidget);
      final semanticsNode = tester.getSemantics(find.text(longPath));
      expect(semanticsNode.value, longPath);
    } finally {
      semantics.dispose();
    }
  });
}
