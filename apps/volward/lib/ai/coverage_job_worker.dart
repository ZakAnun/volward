import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../bridge/native_bridge.dart';
import '../core/session/engine_host.dart';
import '../snapshot_cache.dart';
import 'ai_coverage_job_controller.dart';
import 'ai_provider.dart';
import 'bridge_ai_contract.dart';
import 'byok_ai_provider.dart';
import 'cancel_token.dart';
import 'coverage_analyze_batch.dart';
import 'coverage_analyze_tree_batch.dart';
import 'coverage_client_logic.dart';
import 'coverage_job_state.dart';
import 'coverage_models.dart';
import 'coverage_verdict_store.dart';
import 'native_coverage_engine.dart';
import 'platform_ai_provider.dart';

/// Background isolate entry for full-coverage jobs (keeps UI isolate responsive).
@pragma('vm:entry-point')
void volwardCoverageJobWorker(List<dynamic> args) {
  final mainPort = args[0] as SendPort;
  final config = Map<String, dynamic>.from(args[1] as Map);
  runZonedGuarded(() => _coverageJobWorkerMain(mainPort, config), (
    error,
    stack,
  ) {
    mainPort.send(<String, dynamic>{
      'type': 'error',
      'message': '$error',
      'stack': '$stack',
    });
  });
}

Future<void> _coverageJobWorkerMain(
  SendPort mainPort,
  Map<String, dynamic> config,
) async {
  final bridge = VolwardNativeBridge.open();
  final engineHost = bridge.createEngineHost();
  AiProvider? provider;

  Future<void> runBody() async {
    // ignore: deprecated_member_use
    final enginePtr = engineHost.legacyEnginePointer;
    final catalogPath = config['catalogPath'] as String;
    final hasIndexApi = config['hasIndexApi'] as bool? ?? false;
    var loaded = false;
    if (hasIndexApi) {
      loaded = engineHost.index.loadIndexFromPath(catalogPath);
    }
    if (!loaded) {
      loaded = engineHost.index.loadLastSnapshotFromPath(catalogPath);
    }
    if (!loaded) {
      mainPort.send(<String, dynamic>{
        'type': 'ready',
        'failed': true,
        'message': 'coverage worker failed to load catalog at $catalogPath',
      });
      return;
    }

    final cacheDir = SnapshotCache.cacheDir();
    final engine = NativeCoverageEngine(
      bridge: bridge,
      engine: enginePtr,
      offloadHeavyCalls: false,
      lifetime: engineHost.lifetime,
    );
    final cancelToken = CancelToken();
    CoveragePlanSummary? resumePlanCache;
    CoverageJobController? controller;

    AiProvider buildProvider() {
      final kind = config['providerKind'] as String? ?? 'byok';
      if (kind == 'platform') {
        return PlatformAiProvider(
          token: config['platformToken'] as String? ?? '',
          baseUrl: config['platformBaseUrl'] as String?,
        );
      }
      return ByokAiProvider(
        apiKey: config['byokApiKey'] as String? ?? '',
        contract: BridgeAiContract(bridge),
      );
    }

    Future<void> attachController() async {
      final previous = provider;
      if (previous is ByokAiProvider) {
        previous.dispose();
      } else if (previous is PlatformAiProvider) {
        previous.dispose();
      }
      provider = buildProvider();
      final p = provider!;
      if (p is PlatformAiProvider) {
        await p.queryQuota();
      }
      AnalyzeTreeBatch? treeBatch;
      if (p is TreeAiProvider) {
        treeBatch = createCoverageAnalyzeTreeBatch(
          provider: p as TreeAiProvider,
          cancelToken: cancelToken,
        );
      }
      PlatformAiProvider? platformProvider;
      int? Function()? wallet;
      if (p is PlatformAiProvider) {
        platformProvider = p;
        wallet = () => platformProvider!.lastCreditsRemaining;
      }
      controller = CoverageJobController(
        engine: engine,
        verdictStore: CoverageVerdictStore(cacheDir),
        stateStore: CoverageJobStateStore(cacheDir),
        analyzeBatch: createCoverageAnalyzeBatch(
          provider: p,
          cancelToken: cancelToken,
        ),
        analyzeTreeBatch: treeBatch,
        preferTreeCoveragePlan: config['preferTree'] as bool? ?? false,
        cancelToken: cancelToken,
        platformCreditsRemaining: wallet,
        resumePlanLoader: (snapshotId, job) async {
          final cached = resumePlanCache;
          if (cached == null || cached.snapshotId != snapshotId) return null;
          return coverageResumePlanFromMemoryCache(
            snapshotId: snapshotId,
            job: job,
            cachedSnapshotId: cached.snapshotId,
            cachedSummary: cached,
          );
        },
      );
      controller!.states.listen((state) {
        mainPort.send(<String, dynamic>{
          'type': 'state',
          'state': state.toJson(),
        });
      });
    }

    await attachController();

    final controlPort = ReceivePort();
    mainPort.send(<String, dynamic>{
      'type': 'ready',
      'controlPort': controlPort.sendPort,
    });

    await runCoverageWorkerCommands(
      controlPort: controlPort,
      mainPort: mainPort,
      controller: controller!,
      setResumePlanCache: (value) => resumePlanCache = value,
      onDispose: () {},
    );
  }

  await runCoverageWorkerWithOwnedHost(
    engineHost: engineHost,
    provider: () => provider,
    body: runBody,
  );
}

@visibleForTesting
Future<void> runCoverageWorkerWithOwnedHost({
  required EngineHost engineHost,
  required AiProvider? Function() provider,
  required Future<void> Function() body,
}) async {
  try {
    await body();
  } finally {
    final current = provider();
    if (current is ByokAiProvider) {
      current.dispose();
    } else if (current is PlatformAiProvider) {
      current.dispose();
    }
    engineHost.dispose();
  }
}

/// Worker command loop; separately callable to exercise isolate ordering.
Future<void> runCoverageWorkerCommands({
  required ReceivePort controlPort,
  required SendPort mainPort,
  required CoverageJobController controller,
  required void Function(CoveragePlanSummary?) setResumePlanCache,
  required void Function() onDispose,
}) async {
  var closing = false;
  Future<void>? stopping;
  Future<void>? disposing;
  final controls = <Future<void>>{};

  Future<void> drainControls() async {
    while (controls.isNotEmpty) {
      await Future.wait(controls.toList());
    }
  }

  Future<void> stop() => stopping ??= () async {
    await controller.markAppQuit();
    await controller.waitUntilIdle();
    await drainControls();
  }();

  void acknowledgeWhenDone<T>(
    Future<T> work,
    String? cmd,
    Object? requestId, {
    bool control = false,
  }) {
    final done = work.then<void>(
      (value) => mainPort.send({
        'type': 'ack',
        'cmd': cmd,
        'requestId': requestId,
        if (value is CoverageJobState) 'state': value.toJson(),
      }),
      onError: (Object error, StackTrace stack) => mainPort.send({
        'type': 'error',
        'requestId': requestId,
        'message': '$error',
        'stack': '$stack',
      }),
    );
    if (control) {
      controls.add(done);
      unawaited(done.whenComplete(() => controls.remove(done)));
    } else {
      unawaited(done);
    }
  }

  await for (final message in controlPort) {
    if (message is! Map) continue;
    final cmd = message['cmd']?.toString();
    final requestId = message['requestId'];
    final c = controller;
    try {
      final current = c.state;
      final snapshotId = message['snapshotId'];
      final changesJob =
          cmd == 'start' ||
          cmd == 'resume' ||
          cmd == 'raiseBudgetAndResume' ||
          cmd == 'cancel';
      if (closing && changesJob) {
        throw StateError('Coverage worker is closing');
      }
      // Controls apply their stop request immediately, but their drain/save
      // must not hold this receive loop ahead of the shutdown barrier. Keep new
      // job initialization behind them; active-job controls remain reachable.
      final waitsForControls =
          controls.isNotEmpty &&
          (cmd != 'cancel' || current?.snapshotId != snapshotId);
      if (changesJob &&
          (waitsForControls ||
              (c.isRunning && current?.snapshotId != snapshotId))) {
        unawaited(
          Future.wait([c.waitUntilIdle(), drainControls()]).then(
            (_) => controlPort.sendPort.send(message),
            onError: (Object error, StackTrace stack) => mainPort.send({
              'type': 'error',
              'requestId': requestId,
              'message': '$error',
              'stack': '$stack',
            }),
          ),
        );
        continue;
      }
      switch (cmd) {
        case 'shutdown':
          closing = true;
          acknowledgeWhenDone(stop(), cmd, requestId);
        case 'dispose':
          closing = true;
          disposing ??= () async {
            await stop();
            controlPort.close();
            onDispose();
          }();
          acknowledgeWhenDone(disposing, cmd, requestId);
        case 'start':
          setResumePlanCache(null);
          final startState = await c.start(
            message['snapshotId'] as String,
            budgetTokens: (message['budgetTokens'] as num?)?.toInt() ?? 0,
            budgetCredits: (message['budgetCredits'] as num?)?.toInt() ?? 0,
            detachRun: true,
          );
          mainPort.send(<String, dynamic>{
            'type': 'ack',
            'cmd': cmd,
            'requestId': requestId,
            'state': startState.toJson(),
          });
        case 'resume':
          setResumePlanCache(
            message['preloadedPlan'] is Map
                ? CoveragePlanSummary.fromJson(
                    Map<String, dynamic>.from(message['preloadedPlan'] as Map),
                  )
                : null,
          );
          final resumed = await c.resume(
            message['snapshotId'] as String,
            detachRun: true,
          );
          mainPort.send(<String, dynamic>{
            'type': 'ack',
            'cmd': cmd,
            'requestId': requestId,
            'state': resumed.toJson(),
          });
        case 'raiseBudgetAndResume':
          setResumePlanCache(
            message['preloadedPlan'] is Map
                ? CoveragePlanSummary.fromJson(
                    Map<String, dynamic>.from(message['preloadedPlan'] as Map),
                  )
                : null,
          );
          final raised = await c.raiseBudgetAndResume(
            snapshotId: message['snapshotId'] as String,
            budgetTokens: (message['budgetTokens'] as num?)?.toInt() ?? 0,
            budgetCredits: (message['budgetCredits'] as num?)?.toInt() ?? 0,
            detachRun: true,
          );
          mainPort.send(<String, dynamic>{
            'type': 'ack',
            'cmd': cmd,
            'requestId': requestId,
            'state': raised.toJson(),
          });
        case 'pause':
          acknowledgeWhenDone(c.pause(), cmd, requestId, control: true);
        case 'cancel':
          acknowledgeWhenDone(
            c.cancel(message['snapshotId'] as String),
            cmd,
            requestId,
            control: true,
          );
        case 'markAppQuit':
          acknowledgeWhenDone(c.markAppQuit(), cmd, requestId, control: true);
        case 'waitUntilIdle':
          unawaited(
            c.waitUntilIdle().then(
              (_) => mainPort.send({'type': 'idle', 'requestId': requestId}),
              onError: (Object error, StackTrace stack) => mainPort.send({
                'type': 'error',
                'requestId': requestId,
                'message': '$error',
                'stack': '$stack',
              }),
            ),
          );
        default:
          break;
      }
    } catch (e, st) {
      mainPort.send(<String, dynamic>{
        'type': 'error',
        'requestId': requestId,
        'message': '$e',
        'stack': '$st',
      });
    }
  }
}
