import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_analysis_gateway.dart';
import 'package:volward/ai/ai_contract.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/ai/byok_ai_provider.dart';
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

class _UsageByokProvider extends ByokAiProvider {
  _UsageByokProvider(this.verdicts)
    : super(apiKey: 'sk-test', contract: _FakeUsageContract());

  final List<AiVerdict> verdicts;

  @override
  Future<List<AiVerdict>> analyze(List<AiCandidate> candidates) async {
    lastTokenUsage = const ByokTokenUsage(
      promptTokens: 321,
      completionTokens: 45,
      totalTokens: 366,
    );
    return verdicts;
  }
}

class _IncompleteUsageByokProvider extends ByokAiProvider {
  _IncompleteUsageByokProvider(this.verdicts)
    : super(apiKey: 'sk-test', contract: _FakeUsageContract());

  final List<AiVerdict> verdicts;

  @override
  bool get hasReliableTokenUsage => false;

  @override
  Future<List<AiVerdict>> analyze(List<AiCandidate> candidates) async {
    lastTokenUsage = const ByokTokenUsage(
      promptTokens: 640,
      completionTokens: 120,
      totalTokens: 760,
    );
    return verdicts;
  }
}

class _PartialUsageFailureByokProvider extends ByokAiProvider {
  _PartialUsageFailureByokProvider()
    : super(apiKey: 'sk-test', contract: _FakeUsageContract());

  @override
  Future<List<AiVerdict>> analyze(List<AiCandidate> candidates) async {
    lastTokenUsage = const ByokTokenUsage(
      promptTokens: 120,
      completionTokens: 20,
      totalTokens: 140,
    );
    throw Exception('api_error:500');
  }
}

class _EstimatedPartialUsageFailureByokProvider extends ByokAiProvider {
  _EstimatedPartialUsageFailureByokProvider()
    : super(apiKey: 'sk-test', contract: _FakeUsageContract());

  @override
  bool get hasReliableTokenUsage => false;

  @override
  Future<List<AiVerdict>> analyze(List<AiCandidate> candidates) async {
    lastTokenUsage = const ByokTokenUsage(
      promptTokens: 500,
      completionTokens: 100,
      totalTokens: 600,
    );
    throw Exception('api_error:500');
  }
}

class _FakeUsageContract implements AiContract {
  @override
  int batchSize() => 40;

  @override
  String buildRequestJson(List<AiCandidate> batch) => '{}';

  @override
  List<AiVerdict> parseResponseJson(
    String responseBody,
    List<AiCandidate> batch,
  ) => const [];

  @override
  String upstreamEndpoint() => 'https://example.test/v1/chat';
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
  String rootPath = '/tmp',
}) {
  return jsonEncode({
    'pre_classified': preClassified,
    'unknown_candidates': unknownCandidates,
    'estimated_input_tokens': estimatedTokens,
    'has_existing_result': hasExistingResult,
    'truncated': truncated,
    'candidates_total_before_cap': candidatesBeforeCap,
    'result_cache_key': 'cache-key',
    'root_path': rootPath,
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
  final byokUsageRecords =
      <({int input, int output, int total, bool estimated, bool partial})>[];

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
  Future<ByokTokenUsageTotals> recordByokTokenUsage({
    required int inputTokens,
    required int outputTokens,
    required int totalTokens,
    required bool estimated,
    required bool partial,
  }) async {
    byokUsageRecords.add((
      input: inputTokens,
      output: outputTokens,
      total: totalTokens,
      estimated: estimated,
      partial: partial,
    ));
    return ByokTokenUsageTotals(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTokens: totalTokens,
      analysisCount: byokUsageRecords.length,
      estimatedAnalysisCount: byokUsageRecords.where((e) => e.estimated).length,
      partialAnalysisCount: byokUsageRecords.where((e) => e.partial).length,
      updatedAtMs: 1,
    );
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
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
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
  Locale locale = const Locale('en'),
}) async {
  gateway
    ..candidatesJson = candidatesJson ?? _candidatePayload()
    ..provider = _ResultProvider(result);
  await tester.pumpWidget(
    _workspaceShell(
      gateway,
      onDeletingChanged: onDeletingChanged,
      onDeleteCompleted: onDeleteCompleted,
      locale: locale,
    ),
  );
  await _pumpUntilFound(
    tester,
    find.byKey(AiAnalysisWorkspace.analyzeAgainKey),
  );
  await tester.tap(find.byKey(AiAnalysisWorkspace.analyzeAgainKey));
  await tester.pumpAndSettle();
}

Finder _resultGroup(String path) {
  return find.byKey(ValueKey<String>('ai-result-group:$path'));
}

Finder _resultItem(String path) {
  return find.byKey(ValueKey<String>('ai-result-item:$path'));
}

Future<void> _expandGroup(WidgetTester tester, String path) async {
  await tester.tap(_resultGroup(path));
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
      "member_paths": ["/tmp/build-output/a.o", "/tmp/build-output/b.o"],
      "delete_target": "volward-ai-aggregate:v1:/tmp/build-output"
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

    test('AiCandidate carries an opaque aggregate delete target', () {
      final candidate = AiCandidate.fromJson({
        'path': '/Users/x/big_dir',
        'size_bytes': 2500,
        'is_dir': true,
        'child_count': 25,
        'member_paths': ['/Users/x/big_dir/a.dat'],
        'delete_target': 'volward-ai-aggregate:v1:/Users/x/big_dir',
      });
      expect(candidate.memberPaths, ['/Users/x/big_dir/a.dat']);
      expect(
        candidate.deleteTarget,
        'volward-ai-aggregate:v1:/Users/x/big_dir',
      );
      expect(candidate.toJson()['delete_target'], candidate.deleteTarget);
    });

    test('AiCandidate without member_paths defaults to empty', () {
      final candidate = AiCandidate.fromJson({
        'path': '/tmp/foo.xyz',
        'size_bytes': 12,
        'is_dir': false,
        'cleanup_source': 'ai_tool_cache',
        'cleanup_hint': 123,
        'retention_days': 30.0,
      });
      expect(candidate.memberPaths, isEmpty);
      expect(candidate.cleanupSource, 'ai_tool_cache');
      expect(candidate.cleanupHint, '123');
      expect(candidate.retentionDays, 30);
      expect(candidate.toJson().containsKey('member_paths'), isFalse);
    });

    test('AiVerdict fromJson', () {
      final verdict = AiVerdict.fromJson({
        'path': '/Users/x/weird.cache',
        'verdict': 'safe_to_remove',
        'confidence': 'high',
        'reason': 'build cache',
        'cleanup_source': 'ai_tool_cache',
        'cleanup_hint': 'Known cache',
        'retention_days': 30.0,
      });
      expect(verdict.path, '/Users/x/weird.cache');
      expect(verdict.verdict, 'safe_to_remove');
      expect(verdict.confidence, 'high');
      expect(verdict.reason, 'build cache');
      expect(verdict.cleanupSource, 'ai_tool_cache');
      expect(verdict.cleanupHint, 'Known cache');
      expect(verdict.retentionDays, 30);
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
      expect(validGateway.byokUsageRecords, isEmpty);

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

  testWidgets('loaded results merge partial cleanup metadata from candidates', (
    tester,
  ) async {
    final gateway = _FakeGateway()
      ..candidatesJson = _candidatePayload(
        unknownCandidates: const [
          {
            'path': '/Users/x/Library/Application Support/Cursor/CachedData/a',
            'size_bytes': 100,
            'is_dir': false,
            'cleanup_source': 'ai_tool_cache',
            'cleanup_hint': 'Known AI/editor cache',
            'retention_days': 30,
          },
        ],
        candidatesBeforeCap: 1,
      )
      ..cache['cache-key'] = jsonEncode({
        'root_path': '/Users/x',
        'entries': [
          {
            'path': '/Users/x/Library/Application Support/Cursor/CachedData/a',
            'size_bytes': 100,
            'verdict': 'safe_to_remove',
            'confidence': 'high',
            'reason': 'Rebuildable cache',
            'cleanup_source': 'ai_tool_cache',
          },
        ],
      });

    await tester.pumpWidget(_workspaceShell(gateway));
    await _pumpUntilFound(
      tester,
      find.byKey(AiAnalysisWorkspace.loadPreviousKey),
    );
    await tester.tap(find.byKey(AiAnalysisWorkspace.loadPreviousKey));
    await tester.pumpAndSettle();
    expect(_resultGroup('/Users/x/Library'), findsOneWidget);

    expect(find.textContaining('AI tool cache/temp'), findsOneWidget);
    expect(find.textContaining('Review after 30 days'), findsOneWidget);
    expect(find.textContaining('Known AI/editor cache'), findsOneWidget);
  });

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
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _openResults(
      tester,
      _FakeGateway(),
      candidatesJson: _candidatePayload(
        preClassified: const [
          {
            'path': '/tmp/local-keep.db',
            'size_bytes': 400,
            'confidence': 'high',
            'reason': 'Application data',
            'deletable': false,
          },
        ],
      ),
    );
    expect(_resultGroup('/tmp'), findsOneWidget);
    expect(find.text('/tmp/safe.cache'), findsNothing);
    expect(find.text('/tmp/review.log'), findsNothing);
    expect(find.text('/tmp/keep.db'), findsNothing);
    expect(find.text('/tmp/local-keep.db'), findsNothing);
    expect(find.text('1 item selected · 100 B'), findsOneWidget);

    await _expandGroup(tester, '/tmp');
    expect(find.text('/tmp/keep.db'), findsOneWidget);
    expect(find.text('/tmp/local-keep.db'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('/tmp/local-keep.db'),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );

    await tester.tap(_resultItem('/tmp/safe.cache'));
    await tester.pumpAndSettle();
    expect(find.text('0 items selected · 0 B'), findsOneWidget);
  });

  testWidgets('BYOK result persists provider-reported token usage', (
    tester,
  ) async {
    final gateway = _FakeGateway()
      ..provider = _UsageByokProvider(verdicts)
      ..candidatesJson = _candidatePayload();
    await tester.pumpWidget(_workspaceShell(gateway));
    await _pumpUntilFound(
      tester,
      find.byKey(AiAnalysisWorkspace.analyzeAgainKey),
    );

    await tester.tap(find.byKey(AiAnalysisWorkspace.analyzeAgainKey));
    await tester.pumpAndSettle();

    final result = jsonDecode(gateway.cache['snapshot-1']!) as Map;
    expect(result['token_usage'], {'input': 321, 'output': 45});
    expect(result['credits_used'], 0);
    expect(gateway.byokUsageRecords, [
      (input: 321, output: 45, total: 366, estimated: false, partial: false),
    ]);
  });

  testWidgets('BYOK falls back to estimates when usage is incomplete', (
    tester,
  ) async {
    final gateway = _FakeGateway()
      ..provider = _IncompleteUsageByokProvider(verdicts)
      ..candidatesJson = _candidatePayload();
    await tester.pumpWidget(_workspaceShell(gateway));
    await _pumpUntilFound(
      tester,
      find.byKey(AiAnalysisWorkspace.analyzeAgainKey),
    );

    await tester.tap(find.byKey(AiAnalysisWorkspace.analyzeAgainKey));
    await tester.pumpAndSettle();

    final result = jsonDecode(gateway.cache['snapshot-1']!) as Map;
    expect(result['token_usage'], {'input': 640, 'output': 120});
    expect(result['credits_used'], 0);
    expect(gateway.byokUsageRecords, [
      (input: 640, output: 120, total: 760, estimated: true, partial: false),
    ]);
  });

  testWidgets('BYOK failure records usage from completed batches', (
    tester,
  ) async {
    final gateway = _FakeGateway()
      ..provider = _PartialUsageFailureByokProvider()
      ..candidatesJson = _candidatePayload();
    await tester.pumpWidget(_workspaceShell(gateway));
    await _pumpUntilFound(
      tester,
      find.byKey(AiAnalysisWorkspace.analyzeAgainKey),
    );

    await tester.tap(find.byKey(AiAnalysisWorkspace.analyzeAgainKey));
    await tester.pumpAndSettle();

    expect(gateway.cache, isEmpty);
    expect(gateway.byokUsageRecords, [
      (input: 120, output: 20, total: 140, estimated: false, partial: true),
    ]);
  });

  testWidgets('BYOK failure marks estimated completed usage as partial', (
    tester,
  ) async {
    final gateway = _FakeGateway()
      ..provider = _EstimatedPartialUsageFailureByokProvider()
      ..candidatesJson = _candidatePayload();
    await tester.pumpWidget(_workspaceShell(gateway));
    await _pumpUntilFound(
      tester,
      find.byKey(AiAnalysisWorkspace.analyzeAgainKey),
    );

    await tester.tap(find.byKey(AiAnalysisWorkspace.analyzeAgainKey));
    await tester.pumpAndSettle();

    expect(gateway.cache, isEmpty);
    expect(gateway.byokUsageRecords, [
      (input: 500, output: 100, total: 600, estimated: true, partial: true),
    ]);
  });

  testWidgets('review requires an explicit decision before selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _FakeGateway();
    await _openResults(
      tester,
      gateway,
      result: const [
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
          path: '/tmp/review-2.log',
          verdict: 'review_needed',
          confidence: 'medium',
          reason: 'Different uncertain log',
        ),
        AiVerdict(
          path: '/tmp/keep.db',
          verdict: 'keep',
          confidence: 'high',
          reason: 'Application data',
        ),
      ],
      candidatesJson: _candidatePayload(
        unknownCandidates: const [
          {'path': '/tmp/safe.cache', 'size_bytes': 100, 'is_dir': false},
          {'path': '/tmp/review.log', 'size_bytes': 200, 'is_dir': false},
          {'path': '/tmp/review-2.log', 'size_bytes': 50, 'is_dir': false},
          {'path': '/tmp/keep.db', 'size_bytes': 300, 'is_dir': false},
        ],
      ),
    );

    expect(_resultGroup('/tmp'), findsOneWidget);
    expect(find.text('/tmp/review.log'), findsNothing);
    await _expandGroup(tester, '/tmp');
    expect(
      find.descendant(
        of: _resultGroup('/tmp'),
        matching: find.text(
          '4 items · 650 B · Safe 1 · Review 2 · Keep 1 · Selected 1',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text('2 pending review items are excluded until you decide.'),
      findsOneWidget,
    );

    expect(find.text('Add to cleanup'), findsNothing);
    expect(find.text('Keep this item'), findsNothing);

    await tester.tap(_resultItem('/tmp/review.log'));
    await tester.pumpAndSettle();

    expect(find.text('Add to cleanup'), findsOneWidget);
    expect(find.text('Keep this item'), findsOneWidget);
    expect(find.text('1 item selected · 100 B'), findsOneWidget);

    await tester.tap(find.text('Add to cleanup'));
    await tester.pumpAndSettle();
    expect(find.text('2 items selected · 300 B'), findsOneWidget);
    expect(find.textContaining('300 B'), findsWidgets);
    expect(
      find.descendant(
        of: _resultGroup('/tmp'),
        matching: find.textContaining('Safe 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _resultGroup('/tmp'),
        matching: find.textContaining('Review 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _resultGroup('/tmp'),
        matching: find.textContaining('Keep 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _resultGroup('/tmp'),
        matching: find.textContaining('Selected 2'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('1 pending review item is excluded until you decide.'),
      findsOneWidget,
    );

    await tester.tap(_resultItem('/tmp/review-2.log'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep this item').last);
    await tester.pumpAndSettle();
    expect(find.text('2 items selected · 300 B'), findsOneWidget);
    expect(find.textContaining('300 B'), findsWidgets);
    expect(
      find.descendant(
        of: _resultGroup('/tmp'),
        matching: find.textContaining('Safe 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _resultGroup('/tmp'),
        matching: find.textContaining('Review 0'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _resultGroup('/tmp'),
        matching: find.textContaining('Keep 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _resultGroup('/tmp'),
        matching: find.textContaining('Selected 2'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('0 pending review items are excluded until you decide.'),
      findsOneWidget,
    );

    await tester.tap(_resultItem('/tmp/safe.cache'));
    await tester.pumpAndSettle();
    expect(find.text('1 item selected · 200 B'), findsOneWidget);

    expect(
      find.byKey(const Key('ai-item-toggle:/tmp/review.log')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('ai-item-toggle:/tmp/review-2.log')),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.text('/tmp/keep.db'),
        matching: find.byType(Checkbox),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(AiAnalysisWorkspace.deleteKey));
    await tester.pump();
    expect(gateway.deleteCalls.single.targets, contains('/tmp/review.log'));
    expect(
      gateway.deleteCalls.single.targets,
      isNot(contains('/tmp/review-2.log')),
    );
  });

  testWidgets('selection summary tracks count and bytes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _openResults(tester, _FakeGateway());
    await _expandGroup(tester, '/tmp');
    await tester.tap(_resultItem('/tmp/review.log'));
    await tester.pumpAndSettle();
    expect(find.text('Add to cleanup'), findsOneWidget);
    await tester.tap(find.text('Add to cleanup'));
    await tester.pumpAndSettle();
    expect(find.text('2 items selected · 300 B'), findsOneWidget);
  });

  testWidgets('safe group selection stays scoped to the exact visible group', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _FakeGateway()
      ..deleteReports.add({
        'deleted_count': 1,
        'freed_bytes': 40,
        'failed_paths': const [],
      });
    await _openResults(
      tester,
      gateway,
      result: const [
        AiVerdict(
          path: '/tmp/group-a/safe-a.cache',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'Build cache',
        ),
        AiVerdict(
          path: '/tmp/group-a/review-a.log',
          verdict: 'review_needed',
          confidence: 'medium',
          reason: 'Needs review',
        ),
        AiVerdict(
          path: '/tmp/group-a/keep-a.db',
          verdict: 'keep',
          confidence: 'high',
          reason: 'Data file',
        ),
        AiVerdict(
          path: '/tmp/group-b/safe-b.cache',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'Build cache',
        ),
        AiVerdict(
          path: '/tmp/group-b/review-b.log',
          verdict: 'review_needed',
          confidence: 'medium',
          reason: 'Needs review',
        ),
        AiVerdict(
          path: '/tmp/group-b/keep-b.db',
          verdict: 'keep',
          confidence: 'high',
          reason: 'Data file',
        ),
      ],
      candidatesJson: _candidatePayload(
        unknownCandidates: const [
          {
            'path': '/tmp/group-a/safe-a.cache',
            'size_bytes': 100,
            'is_dir': false,
          },
          {
            'path': '/tmp/group-a/review-a.log',
            'size_bytes': 50,
            'is_dir': false,
          },
          {'path': '/tmp/group-a/keep-a.db', 'size_bytes': 25, 'is_dir': false},
          {
            'path': '/tmp/group-b/safe-b.cache',
            'size_bytes': 40,
            'is_dir': false,
          },
          {
            'path': '/tmp/group-b/review-b.log',
            'size_bytes': 60,
            'is_dir': false,
          },
          {'path': '/tmp/group-b/keep-b.db', 'size_bytes': 30, 'is_dir': false},
        ],
      ),
    );

    expect(
      find.byKey(const Key('ai-group-toggle:/tmp/group-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('ai-group-toggle:/tmp/group-b')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('ai-item-toggle:/tmp/group-a/review-a.log')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('ai-item-toggle:/tmp/group-b/review-b.log')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('ai-item-toggle:/tmp/group-a/keep-a.db')),
      findsNothing,
    );
    expect(_resultItem('/tmp/group-a/safe-a.cache'), findsNothing);
    expect(_resultItem('/tmp/group-b/safe-b.cache'), findsNothing);

    await _expandGroup(tester, '/tmp/group-a');
    await _expandGroup(tester, '/tmp/group-b');

    await tester.tap(
      find.byKey(const Key('ai-item-toggle:/tmp/group-a/safe-a.cache')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const Key('ai-item-toggle:/tmp/group-a/safe-a.cache')),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const Key('ai-item-toggle:/tmp/group-b/safe-b.cache')),
          )
          .value,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('ai-group-toggle:/tmp/group-a')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const Key('ai-item-toggle:/tmp/group-a/safe-a.cache')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const Key('ai-item-toggle:/tmp/group-b/safe-b.cache')),
          )
          .value,
      isTrue,
    );

    await tester.tap(find.byKey(AiAnalysisWorkspace.deleteKey));
    await tester.pump();
    expect(
      gateway.deleteCalls.single.targets,
      unorderedEquals(const [
        '/tmp/group-a/safe-a.cache',
        '/tmp/group-b/safe-b.cache',
      ]),
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-group-toggle:/tmp/group-a')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const Key('ai-item-toggle:/tmp/group-a/safe-a.cache')),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const Key('ai-item-toggle:/tmp/group-b/safe-b.cache')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('results keep local preclassified selections visible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _openResults(
      tester,
      _FakeGateway(),
      candidatesJson: _candidatePayload(
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
      ),
    );

    expect(find.textContaining('3 items selected'), findsOneWidget);
    expect(find.textContaining('200 B'), findsWidgets);
    expect(
      find.text('1 pending review item is excluded until you decide.'),
      findsOneWidget,
    );
    expect(find.text('/tmp/local-1.cache'), findsNothing);
    expect(find.text('/tmp/local-2.cache'), findsNothing);

    await _expandGroup(tester, '/tmp');

    expect(find.text('/tmp/local-1.cache'), findsOneWidget);
    expect(find.text('/tmp/local-2.cache'), findsOneWidget);
    expect(find.textContaining('5 items · 700 B'), findsOneWidget);

    await tester.tap(_resultItem('/tmp/local-1.cache'));
    await tester.pumpAndSettle();
    expect(find.text('2 items selected · 160 B'), findsOneWidget);
    expect(find.textContaining('5 items · 700 B'), findsOneWidget);
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

      expect(find.text('1 item selected · 300 B'), findsOneWidget);
      expect(_resultGroup('/tmp/build-output'), findsOneWidget);
      await tester.tap(find.byKey(AiAnalysisWorkspace.deleteKey));
      await _pumpUntilFound(tester, find.byType(AlertDialog));

      expect(gateway.deleteCalls.single.dryRun, isTrue);
      expect(gateway.deleteCalls.single.rescanAfterDelete, isFalse);
      expect(gateway.deleteCalls.single.targets, const [
        'volward-ai-aggregate:v1:/tmp/build-output',
      ]);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('1 item selected · 300 B'), findsOneWidget);
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

  testWidgets('wide results show one compact summary toolbar and action bar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    await _openResults(tester, _FakeGateway());

    expect(find.byKey(AiAnalysisWorkspace.summaryKey), findsOneWidget);
    expect(
      find.text(
        '3 analyzed · 600 B total · 1 safe · 1 pending review · 1 kept',
      ),
      findsOneWidget,
    );
    expect(find.text('Search path, reason, source, or hint'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('Recommended first'), findsNothing);
    expect(find.text('Show all results'), findsNothing);
    expect(find.text('Safe to remove'), findsNothing);
    expect(find.text('Review needed'), findsNothing);
    expect(find.text('Kept by AI'), findsNothing);
    expect(find.text('1 item selected · 100 B'), findsOneWidget);
    expect(
      find.text('1 pending review item is excluded until you decide.'),
      findsOneWidget,
    );
    expect(find.byKey(AiAnalysisWorkspace.deleteKey), findsOneWidget);
  });

  testWidgets('toolbar search filter and sort only change visible rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _openResults(
      tester,
      _FakeGateway(),
      result: const [
        AiVerdict(
          path: '/tmp/alpha-safe.cache',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'Safe alpha cache',
          cleanupSource: 'system_temp',
        ),
        AiVerdict(
          path: '/tmp/bravo-review.log',
          verdict: 'review_needed',
          confidence: 'medium',
          reason: 'Needs review',
          cleanupHint: 'owner unclear',
        ),
        AiVerdict(
          path: '/tmp/charlie-safe.cache',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'Safe charlie cache',
          cleanupSource: 'ai_generated_output',
        ),
      ],
      candidatesJson: _candidatePayload(
        unknownCandidates: const [
          {'path': '/tmp/alpha-safe.cache', 'size_bytes': 500, 'is_dir': false},
          {'path': '/tmp/bravo-review.log', 'size_bytes': 120, 'is_dir': false},
          {
            'path': '/tmp/charlie-safe.cache',
            'size_bytes': 300,
            'is_dir': false,
          },
        ],
      ),
    );

    await _expandGroup(tester, '/tmp');

    expect(find.text('2 items selected · 800 B'), findsOneWidget);
    expect(find.text('/tmp/alpha-safe.cache'), findsOneWidget);
    expect(find.text('/tmp/bravo-review.log'), findsOneWidget);
    expect(find.text('/tmp/charlie-safe.cache'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('/tmp/bravo-review.log')).dy,
      lessThan(tester.getTopLeft(find.text('/tmp/alpha-safe.cache')).dy),
    );

    await tester.tap(find.text('Priority'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Size').last);
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('/tmp/alpha-safe.cache')).dy,
      lessThan(tester.getTopLeft(find.text('/tmp/bravo-review.log')).dy),
    );
    expect(
      tester.getTopLeft(find.text('/tmp/bravo-review.log')).dy,
      greaterThan(tester.getTopLeft(find.text('/tmp/charlie-safe.cache')).dy),
    );

    await tester.enterText(find.byType(TextField), 'owner unclear');
    await tester.pumpAndSettle();
    expect(find.text('/tmp/alpha-safe.cache'), findsNothing);
    expect(find.text('/tmp/bravo-review.log'), findsOneWidget);
    expect(find.text('/tmp/charlie-safe.cache'), findsNothing);
    expect(find.text('2 items selected · 800 B'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selected').last);
    await tester.pumpAndSettle();

    expect(find.text('/tmp/alpha-safe.cache'), findsOneWidget);
    expect(find.text('/tmp/bravo-review.log'), findsNothing);
    expect(find.text('/tmp/charlie-safe.cache'), findsOneWidget);
  });

  testWidgets('results overview is concise until expanded', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final result = <AiVerdict>[
      for (var i = 0; i < 9; i++)
        AiVerdict(
          path: '/tmp/safe-$i.cache',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'Rebuildable cache',
        ),
      for (var i = 0; i < 2; i++)
        AiVerdict(
          path: '/tmp/review-$i.log',
          verdict: 'review_needed',
          confidence: 'medium',
          reason: 'Needs confirmation',
        ),
      const AiVerdict(
        path: '/tmp/keep.db',
        verdict: 'keep',
        confidence: 'high',
        reason: 'Application data',
      ),
    ];
    await _openResults(
      tester,
      _FakeGateway(),
      result: result,
      candidatesJson: _candidatePayload(
        unknownCandidates: [
          for (var i = 0; i < 9; i++)
            {'path': '/tmp/safe-$i.cache', 'size_bytes': 10, 'is_dir': false},
          for (var i = 0; i < 2; i++)
            {'path': '/tmp/review-$i.log', 'size_bytes': 10, 'is_dir': false},
          {'path': '/tmp/keep.db', 'size_bytes': 10, 'is_dir': false},
        ],
      ),
    );

    expect(
      find.text(
        '12 analyzed · 120 B total · 9 safe · 2 pending review · 1 kept',
      ),
      findsOneWidget,
    );
    expect(find.text('9 items selected · 90 B'), findsOneWidget);
    expect(
      find.text('2 pending review items are excluded until you decide.'),
      findsOneWidget,
    );
    expect(find.text('Show all results'), findsNothing);
    expect(_resultGroup('/tmp'), findsOneWidget);
    expect(find.text('/tmp/safe-8.cache'), findsNothing);

    await _expandGroup(tester, '/tmp');

    final resultsList = find.byKey(AiAnalysisWorkspace.resultsListKey);
    expect(
      find.descendant(
        of: resultsList,
        matching: find.text('/tmp/safe-8.cache'),
      ),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.descendant(
        of: resultsList,
        matching: find.text('/tmp/review-1.log'),
      ),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.descendant(of: resultsList, matching: find.text('/tmp/keep.db')),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('small result groups expand by default', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _openResults(
      tester,
      _FakeGateway(),
      result: const [
        AiVerdict(
          path: '/tmp/small-group/cache/a.bin',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'Rebuildable cache',
        ),
        AiVerdict(
          path: '/tmp/small-group/cache/b.bin',
          verdict: 'keep',
          confidence: 'high',
          reason: 'Application data',
        ),
      ],
    );

    expect(find.text('/tmp/small-group/cache/a.bin'), findsOneWidget);
    expect(find.text('/tmp/small-group/cache/b.bin'), findsOneWidget);
  });

  testWidgets('expanded results render grouped parent directories', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final result = <AiVerdict>[
      const AiVerdict(
        path: '/tmp/project-a/cache/a.bin',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'Cache A',
      ),
      const AiVerdict(
        path: '/tmp/project-b/cache/b.bin',
        verdict: 'safe_to_remove',
        confidence: 'high',
        reason: 'Cache B',
      ),
      const AiVerdict(
        path: '/tmp/project-a/review/log.txt',
        verdict: 'review_needed',
        confidence: 'medium',
        reason: 'Needs review',
      ),
      const AiVerdict(
        path: '/tmp/project-b/keep.db',
        verdict: 'keep',
        confidence: 'high',
        reason: 'User data',
      ),
    ];
    await _openResults(
      tester,
      _FakeGateway(),
      result: result,
      candidatesJson: _candidatePayload(
        unknownCandidates: const [
          {
            'path': '/tmp/project-a/cache/a.bin',
            'size_bytes': 10,
            'is_dir': false,
          },
          {
            'path': '/tmp/project-b/cache/b.bin',
            'size_bytes': 20,
            'is_dir': false,
          },
          {
            'path': '/tmp/project-a/review/log.txt',
            'size_bytes': 30,
            'is_dir': false,
          },
          {'path': '/tmp/project-b/keep.db', 'size_bytes': 40, 'is_dir': false},
        ],
      ),
    );

    final resultsList = find.byKey(AiAnalysisWorkspace.resultsListKey);
    expect(
      find.descendant(of: resultsList, matching: find.text('/tmp/project-a')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: resultsList, matching: find.text('/tmp/project-b')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: resultsList, matching: find.text('/tmp/project-a')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: resultsList, matching: find.text('/tmp/project-b')),
      findsOneWidget,
    );
    expect(find.text('/tmp/project-a/cache/a.bin'), findsOneWidget);
  });

  testWidgets('header stays pinned while results stream scrolls beneath it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final result = <AiVerdict>[
      for (var i = 0; i < 18; i++)
        AiVerdict(
          path: '/tmp/safe-$i.cache',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'Rebuildable cache',
        ),
    ];
    await _openResults(
      tester,
      _FakeGateway(),
      result: result,
      candidatesJson: _candidatePayload(
        unknownCandidates: [
          for (var i = 0; i < 18; i++)
            {'path': '/tmp/safe-$i.cache', 'size_bytes': 10, 'is_dir': false},
        ],
      ),
    );

    final backAction = find.byKey(AiAnalysisWorkspace.backKey);
    expect(find.text('Back to Overview'), findsOneWidget);
    expect(backAction, findsOneWidget);
    expect(tester.getSize(backAction).width, greaterThan(96));
    final expandedHeaderHeight = tester
        .getSize(find.byKey(AiAnalysisWorkspace.headerKey))
        .height;
    final summaryTopBeforeScroll = tester
        .getTopLeft(find.byKey(AiAnalysisWorkspace.summaryKey))
        .dy;
    final deleteTopBeforeScroll = tester
        .getTopLeft(find.byKey(AiAnalysisWorkspace.deleteKey))
        .dy;

    await _expandGroup(tester, '/tmp');
    expect(_resultItem('/tmp/safe-0.cache'), findsOneWidget);

    await tester.drag(
      find.byKey(AiAnalysisWorkspace.resultsListKey),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    final resultsScrollable = find.descendant(
      of: find.byKey(AiAnalysisWorkspace.resultsListKey),
      matching: find.byType(Scrollable),
    );
    final scrollableState = tester.state<ScrollableState>(
      resultsScrollable.first,
    );

    expect(find.text('Back to Overview'), findsOneWidget);
    expect(backAction, findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(AiAnalysisWorkspace.summaryKey)).dy,
      closeTo(summaryTopBeforeScroll, 12),
    );
    expect(
      tester.getTopLeft(find.byKey(AiAnalysisWorkspace.deleteKey)).dy,
      closeTo(deleteTopBeforeScroll, 12),
    );
    expect(
      tester.getSize(find.byKey(AiAnalysisWorkspace.headerKey)).height,
      lessThan(expandedHeaderHeight),
    );
    expect(scrollableState.position.pixels, greaterThan(0));
    expect(_resultItem('/tmp/safe-0.cache'), findsNothing);
    expect(find.text('18 items selected · 180 B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large results render as groups before item rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final result = <AiVerdict>[
      for (var index = 0; index < 10000; index++)
        AiVerdict(
          path: '/tmp/large-tree/group-${index % 3}/item-$index.cache',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'Rebuildable cache',
        ),
    ];
    await _openResults(
      tester,
      _FakeGateway(),
      result: result,
      candidatesJson: _candidatePayload(
        unknownCandidates: [
          for (var index = 0; index < 10000; index++)
            {
              'path': '/tmp/large-tree/group-${index % 3}/item-$index.cache',
              'size_bytes': 1024,
              'is_dir': false,
            },
        ],
      ),
    );

    expect(find.text('/tmp/large-tree'), findsOneWidget);
    expect(
      find.descendant(
        of: _resultGroup('/tmp/large-tree'),
        matching: find.textContaining('10000 items'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _resultGroup('/tmp/large-tree'),
        matching: find.textContaining('9.8 MB'),
      ),
      findsOneWidget,
    );
    expect(find.text('/tmp/large-tree/group-2/item-9998.cache'), findsNothing);
    expect(
      find.byKey(const ValueKey('ai-analysis-show-all-results')),
      findsNothing,
    );

    await _expandGroup(tester, '/tmp/large-tree');
    expect(find.text('/tmp/large-tree/group-2/item-9998.cache'), findsNothing);

    final resultsScrollable = find.descendant(
      of: find.byKey(AiAnalysisWorkspace.resultsListKey),
      matching: find.byType(Scrollable),
    );
    final scrollableState = tester.state<ScrollableState>(
      resultsScrollable.first,
    );
    scrollableState.position.jumpTo(scrollableState.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(
      find.text('/tmp/large-tree/group-2/item-9998.cache'),
      findsOneWidget,
    );
  });

  testWidgets('compact results stack summary toolbar stream and action bar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(719, 800);
    addTearDown(tester.view.reset);
    final result = <AiVerdict>[
      for (var i = 0; i < 18; i++)
        AiVerdict(
          path: '/tmp/compact-safe-$i.cache',
          verdict: 'safe_to_remove',
          confidence: 'high',
          reason: 'Rebuildable cache',
        ),
    ];
    await _openResults(
      tester,
      _FakeGateway(),
      result: result,
      candidatesJson: _candidatePayload(
        unknownCandidates: [
          for (var i = 0; i < 18; i++)
            {
              'path': '/tmp/compact-safe-$i.cache',
              'size_bytes': 10,
              'is_dir': false,
            },
        ],
      ),
    );

    final resultsList = find.byKey(AiAnalysisWorkspace.resultsListKey);
    expect(find.byKey(AiAnalysisWorkspace.summaryKey), findsOneWidget);
    expect(
      find.text(
        '18 analyzed · 180 B total · 18 safe · 0 pending review · 0 kept',
      ),
      findsOneWidget,
    );
    expect(find.text('Search path, reason, source, or hint'), findsOneWidget);
    expect(find.byKey(AiAnalysisWorkspace.deleteKey), findsOneWidget);
    await _expandGroup(tester, '/tmp');
    expect(_resultItem('/tmp/compact-safe-0.cache'), findsOneWidget);

    await tester.drag(resultsList, const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(find.byKey(AiAnalysisWorkspace.summaryKey), findsOneWidget);
    expect(find.text('Search path, reason, source, or hint'), findsOneWidget);
    expect(find.byKey(AiAnalysisWorkspace.deleteKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new result stream copy localizes in Chinese', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _openResults(tester, _FakeGateway(), locale: const Locale('zh'));

    expect(
      find.text('共分析 3 项 · 总计 600 B · 1 项安全 · 1 项待确认 · 1 项保留'),
      findsOneWidget,
    );
    expect(find.text('搜索路径、原因、来源或提示'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('优先级'), findsOneWidget);
    expect(find.text('已选择 1 项 · 100 B'), findsOneWidget);
    expect(find.text('1 项待确认内容在你决定前不会加入清理。'), findsOneWidget);
  });

  testWidgets('long paths expose tooltip and full semantic value', (
    tester,
  ) async {
    const longPath =
        '/Users/example/Library/Application Support/Very Long App/Cache/'
        'nested/folder/that/needs/the/full/path/cache.data';
    final semantics = tester.ensureSemantics();
    try {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
