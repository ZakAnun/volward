import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_analysis_gateway.dart';
import 'package:volward/ai/ai_provider.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/features/ai_coverage/ai_analysis_workspace_config.dart';
import 'package:volward/features/ai_coverage/controllers/ai_analysis_bootstrap_controller.dart';
import 'package:volward/features/ai_coverage/controllers/ai_analysis_workspace_controller.dart';

void main() {
  test('loads provider context and native candidate payload', () async {
    final gateway = _FakeGateway(
      mode: AiMode.byok,
      candidatesRaw:
          '{"pre_classified":[{"path":"/tmp/safe","size_bytes":10,'
          '"confidence":"high","deletable":true,"is_dir":false,'
          '"metadata":{"labels":["clean"]}}],'
          '"unknown_candidates":[{"path":"/tmp/unknown","size_bytes":20,'
          '"is_dir":false,"deletable":true,"delete_target":"target",'
          '"member_paths":["/tmp/member"]}],'
          '"estimated_input_tokens":30,"has_existing_result":true,'
          '"candidates_total_before_cap":4,"result_cache_key":"cache-a",'
          '"root_path":"/tmp"}',
    );
    final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
    final controller = AiAnalysisBootstrapController(
      page: _config(gateway),
      owner: owner,
    );

    await controller.initialize();

    expect(controller.mode, AiMode.byok);
    expect(controller.hasProvider, isFalse);
    expect(controller.bootstrapState.candidatesPending, isFalse);
    expect(controller.bootstrapState.hasExistingResult, isTrue);
    expect(controller.preClassified.single['path'], '/tmp/safe');
    expect(controller.unknown.single.path, '/tmp/unknown');
    expect(controller.sizeByPath, {'/tmp/safe': 10, '/tmp/unknown': 20});
    expect(controller.deleteTargetsByPath, {'/tmp/unknown': 'target'});
    expect(controller.initialSelectedPaths, {'/tmp/safe'});
    expect(controller.preClassifiedTotalCount, 1);
    expect(controller.unknownTotalCount, 4);
    expect(controller.resultCacheKey, 'cache-a');
    expect(controller.rootPath, '/tmp');

    expect(
      identical(controller.preClassified, controller.preClassified),
      isTrue,
    );
    expect(
      identical(controller.unknownByPath, controller.unknownByPath),
      isTrue,
    );
    expect(
      () => controller.preClassified.single['path'] = '/tmp/changed',
      throwsUnsupportedError,
    );
    final metadata =
        controller.preClassified.single['metadata'] as Map<String, dynamic>;
    expect(() => metadata['source'] = 'mutated', throwsUnsupportedError);
    final labels =
        controller.preClassified.single['metadata']['labels'] as List<dynamic>;
    expect(() => labels.add('mutated'), throwsUnsupportedError);
    final mappedUnknown = controller.unknownByPath['/tmp/unknown']!;
    expect(identical(mappedUnknown, controller.unknown.single), isTrue);
    expect(
      () => mappedUnknown.memberPaths[0] = '/tmp/changed',
      throwsUnsupportedError,
    );
  });

  test('stale bootstrap cannot publish after owner rebind', () async {
    final mode = Completer<AiMode>();
    final gateway = _FakeGateway(modeFuture: mode.future);
    final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
    final controller = AiAnalysisBootstrapController(
      page: _config(gateway),
      owner: owner,
    );

    final pending = controller.initialize();
    controller.rebind(
      'owner-b',
      page: _config(gateway, snapshotId: 'snapshot-b'),
    );
    mode.complete(AiMode.byok);
    await pending;

    expect(controller.mode, AiMode.off);
    expect(controller.candidatesRaw, isNull);
    expect(controller.unknown, isEmpty);
    expect(controller.precheckState.snapshotId, 'snapshot-b');
    expect(controller.bootstrapState.candidatesPending, isTrue);
  });

  test('late spill load cannot publish after owner rebind', () async {
    final loadedUnknown = Completer<List<AiCandidate>>();
    final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
    final gateway = _FakeGateway(candidatesRaw: _heavyCandidatesPayload());
    final controller = AiAnalysisBootstrapController(
      page: _config(gateway),
      owner: owner,
      unknownCandidatesSpillLoader: (_) => loadedUnknown.future,
    );

    await controller.initialize();
    expect(controller.unknownCandidatesSpillPath, isNotNull);
    expect(controller.unknown, isEmpty);

    final pending = controller.ensureUnknownCandidatesLoaded();
    controller.rebind(
      'owner-b',
      page: _config(gateway, snapshotId: 'snapshot-b'),
    );
    loadedUnknown.complete(const [
      AiCandidate(path: '/tmp/stale', sizeBytes: 9, isDir: false),
    ]);
    await pending;

    expect(controller.unknown, isEmpty);
    expect(controller.unknownByPath, isEmpty);
    expect(controller.unknownCandidatesSpillPath, isNull);
    controller.dispose();
  });

  test('previous result marks cached-result context', () async {
    final gateway = _FakeGateway(previousResultRaw: '{"entries":[]}');
    final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
    final controller = AiAnalysisBootstrapController(
      page: _config(gateway),
      owner: owner,
    );

    await controller.loadPreviousResult();

    expect(controller.previousResultRaw, '{"entries":[]}');
    expect(controller.bootstrapState.hasExistingResult, isTrue);
    expect(controller.bootstrapState.loadedFromCache, isTrue);
  });

  test('successful cached-result restore clears bootstrap error', () async {
    final gateway = _FakeGateway(
      candidatesRaw: 'not-json',
      previousResultRaw: '{"entries":[]}',
    );
    final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
    final controller = AiAnalysisBootstrapController(
      page: _config(gateway),
      owner: owner,
    );

    await controller.initialize();
    expect(controller.bootstrapState.error, isNotNull);

    await controller.loadPreviousResult();

    expect(controller.bootstrapState.loadedFromCache, isTrue);
    expect(controller.bootstrapState.hasExistingResult, isTrue);
    expect(controller.bootstrapState.error, isNull);
  });

  test('precheck refresh owns provider mode and platform credits', () async {
    final gateway = _FakeGateway(
      mode: AiMode.platform,
      provider: _FakeProvider(creditsRemaining: 37),
      candidatesRaw:
          '{"pre_classified":[],"unknown_candidates":[],'
          '"result_cache_key":"cache-a"}',
    );
    final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
    final controller = AiAnalysisBootstrapController(
      page: _config(gateway),
      owner: owner,
    );

    await controller.initialize();
    expect(controller.platformCredits, 37);

    gateway
      ..mode = AiMode.byok
      ..provider = null;

    expect(await controller.refreshPrecheckContext(), isTrue);
    expect(controller.mode, AiMode.byok);
    expect(controller.hasProvider, isFalse);
    expect(controller.platformCredits, isNull);
  });

  test(
    'candidate parse failure publishes owner error without candidates',
    () async {
      final gateway = _FakeGateway(candidatesRaw: 'not-json');
      final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
      final controller = AiAnalysisBootstrapController(
        page: _config(gateway),
        owner: owner,
      );

      await controller.initialize();

      expect(controller.bootstrapState.candidatesPending, isFalse);
      expect(controller.bootstrapState.error, contains('FormatException'));
      expect(controller.unknown, isEmpty);
      expect(controller.preClassified, isEmpty);
    },
  );
}

String _heavyCandidatesPayload() {
  return jsonEncode({
    'pre_classified': <Object?>[],
    'unknown_candidates': [
      for (var index = 0; index < 257; index++)
        {
          'path': '/tmp/unknown-$index',
          'size_bytes': index + 1,
          'is_dir': false,
        },
    ],
    'result_cache_key': 'cache-heavy',
    'root_path': '/tmp',
  });
}

AiAnalysisWorkspaceConfig _config(
  AiAnalysisGateway gateway, {
  String snapshotId = 'snapshot-a',
}) {
  return AiAnalysisWorkspaceConfig(
    snapshotId: snapshotId,
    targetLabel: 'Downloads',
    onExit: () {},
    onOpenSettings: () {},
    onDeletingChanged: (_) {},
    onDeleteCompleted: () {},
    gateway: gateway,
  );
}

class _FakeGateway implements AiAnalysisGateway {
  _FakeGateway({
    this.mode = AiMode.off,
    this.provider,
    this.modeFuture,
    this.candidatesRaw,
    this.previousResultRaw,
  });

  AiMode mode;
  AiProvider? provider;
  final Future<AiMode>? modeFuture;
  final String? candidatesRaw;
  String? previousResultRaw;

  @override
  Future<AiMode> getMode() => modeFuture ?? Future<AiMode>.value(mode);

  @override
  Future<AiProvider?> resolveProvider() async => provider;

  @override
  Future<String?> buildCandidates(String snapshotId) async => candidatesRaw;

  @override
  String? loadResult(String key) => previousResultRaw;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProvider implements AiProvider {
  _FakeProvider({required this.creditsRemaining});

  final int creditsRemaining;

  @override
  Future<AiQuotaInfo?> queryQuota() async =>
      AiQuotaInfo(creditsRemaining: creditsRemaining, creditsTotal: 100);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
