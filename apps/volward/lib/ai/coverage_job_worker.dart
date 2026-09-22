import 'dart:async';
import 'dart:isolate';

import '../bridge/native_bridge.dart';
import '../snapshot_cache.dart';
import 'ai_contract.dart';
import 'ai_coverage_job_controller.dart';
import 'ai_provider.dart';
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
  final enginePtr = bridge.createEngine();
  final catalogPath = config['catalogPath'] as String;
  final hasIndexApi = config['hasIndexApi'] as bool? ?? false;
  var loaded = false;
  if (hasIndexApi) {
    loaded = bridge.loadIndexFromPath(enginePtr, catalogPath);
  }
  if (!loaded) {
    loaded = bridge.loadLastSnapshotFromPath(enginePtr, catalogPath);
  }
  if (!loaded) {
    mainPort.send(<String, dynamic>{
      'type': 'ready',
      'failed': true,
      'message': 'coverage worker failed to load catalog at $catalogPath',
    });
    bridge.freeEngine(enginePtr);
    return;
  }

  final cacheDir = SnapshotCache.cacheDir();
  final engine = NativeCoverageEngine(bridge: bridge, engine: enginePtr);
  final cancelToken = CancelToken();
  CoveragePlanSummary? resumePlanCache;
  CoverageJobController? controller;
  AiProvider? provider;

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

  await for (final message in controlPort) {
    if (message is! Map) continue;
    final cmd = message['cmd']?.toString();
    final c = controller;
    if (c == null) continue;
    try {
      switch (cmd) {
        case 'dispose':
          controlPort.close();
          final p = provider;
          if (p is ByokAiProvider) {
            p.dispose();
          } else if (p is PlatformAiProvider) {
            p.dispose();
          }
          bridge.freeEngine(enginePtr);
          return;
        case 'start':
          resumePlanCache = null;
          final startState = await c.start(
            message['snapshotId'] as String,
            budgetTokens: (message['budgetTokens'] as num?)?.toInt() ?? 0,
            budgetCredits: (message['budgetCredits'] as num?)?.toInt() ?? 0,
            detachRun: true,
          );
          mainPort.send(<String, dynamic>{
            'type': 'ack',
            'cmd': cmd,
            'state': startState.toJson(),
          });
        case 'resume':
          resumePlanCache = message['preloadedPlan'] is Map
              ? CoveragePlanSummary.fromJson(
                  Map<String, dynamic>.from(message['preloadedPlan'] as Map),
                )
              : null;
          final resumed = await c.resume(
            message['snapshotId'] as String,
            detachRun: true,
          );
          mainPort.send(<String, dynamic>{
            'type': 'ack',
            'cmd': cmd,
            'state': resumed.toJson(),
          });
        case 'raiseBudgetAndResume':
          resumePlanCache = message['preloadedPlan'] is Map
              ? CoveragePlanSummary.fromJson(
                  Map<String, dynamic>.from(message['preloadedPlan'] as Map),
                )
              : null;
          final raised = await c.raiseBudgetAndResume(
            snapshotId: message['snapshotId'] as String,
            budgetTokens: (message['budgetTokens'] as num?)?.toInt() ?? 0,
            budgetCredits: (message['budgetCredits'] as num?)?.toInt() ?? 0,
            detachRun: true,
          );
          mainPort.send(<String, dynamic>{
            'type': 'ack',
            'cmd': cmd,
            'state': raised.toJson(),
          });
        case 'pause':
          final paused = await c.pause();
          mainPort.send(<String, dynamic>{
            'type': 'ack',
            'cmd': cmd,
            'state': paused.toJson(),
          });
        case 'cancel':
          final cancelled = await c.cancel(message['snapshotId'] as String);
          mainPort.send(<String, dynamic>{
            'type': 'ack',
            'cmd': cmd,
            'state': cancelled.toJson(),
          });
        case 'markAppQuit':
          await c.markAppQuit();
          mainPort.send(<String, dynamic>{'type': 'ack', 'cmd': cmd});
        case 'waitUntilIdle':
          await c.waitUntilIdle();
          mainPort.send(<String, dynamic>{'type': 'idle'});
        default:
          break;
      }
    } catch (e, st) {
      mainPort.send(<String, dynamic>{
        'type': 'error',
        'message': '$e',
        'stack': '$st',
      });
    }
  }
}
