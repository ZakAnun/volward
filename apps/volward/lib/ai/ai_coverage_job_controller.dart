import 'dart:async';
import 'dart:math' show min;

import 'package:http/http.dart' as http;

import 'cancel_token.dart';
import 'coverage_analyze_batch.dart';
import 'coverage_analyze_tree_batch.dart';
import 'coverage_client_logic.dart';
import 'coverage_engine.dart';
import 'coverage_job_state.dart';
import 'coverage_models.dart';
import 'coverage_verdict_store.dart';

class BatchUsage {
  const BatchUsage({required this.tokens, required this.credits});

  final int tokens;
  final int credits;
}

class BatchOutcome {
  const BatchOutcome({required this.usage, required this.verdicts});

  final BatchUsage usage;
  final List<CoverageVerdict> verdicts;
}

typedef AnalyzeBatch = Future<BatchOutcome> Function(List<CoverageRow> rows);

typedef FetchLocalVerdictPage =
    Future<({List<CoverageVerdict> verdicts, int? nextCursor})> Function(
      int cursor,
    );

Future<void> flushLocalVerdictsInChunks({
  required CoverageVerdictStore verdictStore,
  required String snapshotId,
  required FetchLocalVerdictPage fetchPage,
  int chunkSize = 1000,
}) async {
  var cursor = 0;
  while (true) {
    final page = await fetchPage(cursor);
    if (page.verdicts.isEmpty) break;
    for (var i = 0; i < page.verdicts.length; i += chunkSize) {
      final end = i + chunkSize < page.verdicts.length
          ? i + chunkSize
          : page.verdicts.length;
      await verdictStore.appendAll(snapshotId, page.verdicts.sublist(i, end));
    }
    final next = page.nextCursor;
    if (next == null) break;
    cursor = next;
  }
}

class CoverageJobController {
  CoverageJobController({
    required this.engine,
    required this.verdictStore,
    required this.stateStore,
    required this.analyzeBatch,
    this.analyzeTreeBatch,
    this.batchSize = 40,
    this.maxInFlight = 4,
    this.treeBatchSize = 80,
    this.treeMaxInFlight = 2,
    this.platformCreditsRemaining,
    CancelToken? cancelToken,
  }) : _cancelToken = cancelToken ?? CancelToken();

  final CoverageEngine engine;
  final CoverageVerdictStore verdictStore;
  final CoverageJobStateStore stateStore;
  final AnalyzeBatch analyzeBatch;
  final AnalyzeTreeBatch? analyzeTreeBatch;
  final int batchSize;
  final int maxInFlight;
  final int treeBatchSize;
  final int treeMaxInFlight;

  /// When null, wallet balance is unknown — wave sizing ignores wallet cap.
  final int? Function()? platformCreditsRemaining;
  final CancelToken _cancelToken;

  CoverageJobState? _state;
  bool _pauseRequested = false;
  bool _cancelRequested = false;
  bool _running = false;
  CoveragePauseReason? _pauseRequestReason;
  final _states = StreamController<CoverageJobState>.broadcast();

  CoverageJobState? get state => _state;
  Stream<CoverageJobState> get states => _states.stream;

  Future<CoverageJobState> start(
    String snapshotId, {
    required int budgetTokens,
    required int budgetCredits,
  }) async {
    if (_running) {
      if (_state?.snapshotId == snapshotId) {
        return _state!;
      }
      await waitUntilIdle();
    }
    _pauseRequested = false;
    _cancelRequested = false;
    _pauseRequestReason = null;
    await verdictStore.clear(snapshotId);
    _state = CoverageJobState(
      snapshotId: snapshotId,
      rootPath: '',
      planVersion: 1,
      cursor: 0,
      totalUnclassified: 0,
      analyzedFiles: 0,
      preClassifiedCount: 0,
      status: CoverageJobStatus.running,
      usedTokens: 0,
      usedCredits: 0,
      budgetTokens: budgetTokens,
      budgetCredits: budgetCredits,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      clientLogicVersion: kCoverageClientLogicVersion,
    );
    await stateStore.save(_state!);
    _emit();
    await _run();
    return _state!;
  }

  Future<CoverageJobState> pause() async {
    _pauseRequestReason = CoveragePauseReason.manual;
    _pauseRequested = true;
    _cancelToken.cancel();
    await waitUntilIdle();
    return _state ?? _idleFor('');
  }

  Future<void> waitUntilIdle() async {
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  void dispose() {
    if (!_states.isClosed) {
      _states.close();
    }
  }

  Future<void> markAppQuit() async {
    if (_state?.status != CoverageJobStatus.running) return;
    _pauseRequestReason = CoveragePauseReason.appQuit;
    _pauseRequested = true;
    _cancelToken.cancel();
    await waitUntilIdle();
  }

  Future<CoverageJobState> resume(String snapshotId) async {
    if (_running) {
      if (_state?.snapshotId == snapshotId) {
        return _state!;
      }
      await waitUntilIdle();
    }
    final current = await _ensureLoaded(snapshotId);
    if (current == null) return _idleFor(snapshotId);
    _pauseRequested = false;
    _cancelRequested = false;
    _pauseRequestReason = null;
    _state = current.copyWith(
      status: CoverageJobStatus.running,
      pauseReason: () => null,
      pauseDetail: () => null,
      failedBatchPaths: const [],
      clientLogicVersion: kCoverageClientLogicVersion,
    );
    await stateStore.save(_state!);
    _emit();
    await _run();
    return _state!;
  }

  Future<CoverageJobState> cancel(String snapshotId) async {
    if (_running && _state?.snapshotId != snapshotId) {
      await waitUntilIdle();
    }
    _cancelRequested = true;
    _pauseRequested = true;
    _cancelToken.cancel();
    final current = await _ensureLoaded(snapshotId);
    if (current == null) return _idleFor(snapshotId);
    if (current.status != CoverageJobStatus.running &&
        current.status != CoverageJobStatus.paused) {
      return current;
    }
    if (!_running) {
      _state = current.copyWith(
        status: CoverageJobStatus.cancelled,
        pauseReason: () => null,
      );
      await stateStore.save(_state!);
      _emit();
      return _state!;
    }
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return _state ?? current;
  }

  Future<CoverageJobState> raiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
  }) async {
    if (_running) {
      if (_state?.snapshotId == snapshotId) {
        return _state!;
      }
      await waitUntilIdle();
    }
    final current = await _ensureLoaded(snapshotId);
    if (current == null) return _idleFor(snapshotId);
    _pauseRequested = false;
    _cancelRequested = false;
    _state = current.copyWith(
      status: CoverageJobStatus.running,
      pauseReason: () => null,
      pauseDetail: () => null,
      failedBatchPaths: const [],
      budgetTokens: budgetTokens > 0 ? budgetTokens : current.budgetTokens,
      budgetCredits: budgetCredits > 0 ? budgetCredits : current.budgetCredits,
      clientLogicVersion: kCoverageClientLogicVersion,
    );
    await stateStore.save(_state!);
    _emit();
    await _run();
    return _state!;
  }

  Future<CoverageJobState?> _ensureLoaded(String snapshotId) async {
    if (_state != null && _state!.snapshotId == snapshotId) {
      return _state;
    }
    final loaded = await stateStore.load(snapshotId);
    _state = loaded;
    return loaded;
  }

  CoverageJobState _idleFor(String snapshotId) => CoverageJobState(
    snapshotId: snapshotId,
    rootPath: '',
    planVersion: 1,
    cursor: 0,
    totalUnclassified: 0,
    analyzedFiles: 0,
    preClassifiedCount: 0,
    status: CoverageJobStatus.idle,
    usedTokens: 0,
    usedCredits: 0,
    budgetTokens: 0,
    budgetCredits: 0,
    updatedAtMs: DateTime.now().millisecondsSinceEpoch,
  );

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    _cancelToken.reset();
    try {
      var guard = _state;
      if (guard == null) return;
      final snapshotId = guard.snapshotId;

      var plan = await engine.buildPlan(snapshotId);
      if (plan.isTreePlan) {
        plan = await engine.buildTreePlan(snapshotId);
      }
      if (plan.snapshotId != snapshotId) {
        await _pause(CoveragePauseReason.failed);
        return;
      }
      if (guard.cursor > 0 && guard.planVersion != plan.planVersion) {
        await _pause(CoveragePauseReason.failed);
        return;
      }
      if (guard.rootPath.isNotEmpty && guard.rootPath != plan.rootPath) {
        await _pause(CoveragePauseReason.failed);
        return;
      }
      if (guard.fingerprint != null &&
          plan.fingerprint != null &&
          !guard.fingerprint!.matches(plan.fingerprint!)) {
        await _pause(CoveragePauseReason.failed);
        return;
      }
      guard = _state = CoverageJobState(
        snapshotId: plan.snapshotId,
        rootPath: plan.rootPath,
        planVersion: plan.planVersion,
        cursor: guard.cursor,
        totalUnclassified: plan.totalUnclassified,
        analyzedFiles: guard.analyzedFiles,
        preClassifiedCount: plan.preClassifiedCount,
        status: CoverageJobStatus.running,
        usedTokens: guard.usedTokens,
        usedCredits: guard.usedCredits,
        budgetTokens: guard.budgetTokens,
        budgetCredits: guard.budgetCredits,
        fingerprint: plan.fingerprint ?? guard.fingerprint,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        clientLogicVersion: guard.clientLogicVersion,
        treeQueueCursor: guard.treeQueueCursor,
        tailQueueCursor: guard.tailQueueCursor,
        localResolvedFiles: guard.localResolvedFiles,
        treeNodesCompleted: guard.treeNodesCompleted,
        estimatedTreeCredits: guard.estimatedTreeCredits,
        estimatedTailCredits: guard.estimatedTailCredits,
      );
      await stateStore.save(_state!);
      _emit();

      if (plan.planVersion >= 3 && guard.localResolvedFiles == 0) {
        await flushLocalVerdictsInChunks(
          verdictStore: verdictStore,
          snapshotId: snapshotId,
          fetchPage: (cursor) async {
            final page = await engine.fetchLocalVerdictsPage(
              snapshotId,
              cursor: cursor,
            );
            return (verdicts: page.verdicts, nextCursor: page.nextCursor);
          },
        );
        final localResolved =
            (plan.localSafeFiles ?? 0) + (plan.localKeepFiles ?? 0);
        if (localResolved > 0 && _state != null) {
          _state = _state!.copyWith(localResolvedFiles: localResolved);
          await stateStore.save(_state!);
          _emit();
        }
      }

      final treeBatch = analyzeTreeBatch;
      if (plan.planVersion >= 3 && plan.isTreePlan && treeBatch != null) {
        final treeOk = await _runTreeBfsPhase(
          snapshotId: snapshotId,
          plan: plan,
          analyzeTreeBatch: treeBatch,
        );
        if (!treeOk) {
          await _finishPauseOrCancel();
          return;
        }
        final tailOk = await _runTailPhase(snapshotId: snapshotId, plan: plan);
        if (!tailOk) {
          await _finishPauseOrCancel();
          return;
        }
        if (!_pauseRequested) {
          await _complete();
        } else {
          await _finishPauseOrCancel();
        }
        return;
      }

      while (!_pauseRequested && _state != null) {
        final state = _state!;
        if (_overBudget(state)) {
          await _pause(CoveragePauseReason.budget);
          return;
        }
        final page = await engine.nextPage(
          snapshotId,
          state.planVersion,
          state.cursor,
        );
        if (page.rows.isEmpty) {
          await _complete();
          return;
        }

        final chunks = <List<CoverageRow>>[];
        for (var i = 0; i < page.rows.length; i += batchSize) {
          final end = i + batchSize < page.rows.length
              ? i + batchSize
              : page.rows.length;
          chunks.add(page.rows.sublist(i, end));
        }
        for (
          var waveStart = 0;
          waveStart < chunks.length;
          waveStart += maxInFlight
        ) {
          if (_pauseRequested) break;
          if (_overBudget(_state!)) {
            await _pause(CoveragePauseReason.budget);
            return;
          }
          final remaining = _remainingWaveSlots(_state!);
          if (remaining <= 0) {
            await _pause(CoveragePauseReason.budget);
            return;
          }
          final waveEnd = waveStart + remaining < chunks.length
              ? waveStart + remaining
              : chunks.length;
          final results = await Future.wait(
            chunks
                .sublist(waveStart, waveEnd)
                .map((chunk) => _analyzeWithRetry(snapshotId, chunk)),
          );
          // Count the contiguous persisted prefix (results are in input order).
          var committed = 0;
          for (final result in results) {
            if (result == null) break;
            committed++;
          }
          var waveAnalyzed = 0;
          var waveTokens = 0;
          var waveCredits = 0;
          for (var i = 0; i < committed; i++) {
            final result = results[i]!;
            waveAnalyzed += result.memberFiles;
            waveTokens += result.usage.tokens;
            waveCredits += result.usage.credits;
          }
          if (committed > 0) {
            // Advance the cursor past contiguous persisted batches so a
            // pause/crash mid-page never re-sends them on resume.
            final waveCursor =
                chunks[waveStart + committed - 1].last.rowIndex + 1;
            final current = _state!;
            _state = current.copyWith(
              cursor: waveCursor,
              analyzedFiles: current.analyzedFiles + waveAnalyzed,
              usedTokens: current.usedTokens + waveTokens,
              usedCredits: current.usedCredits + waveCredits,
              updatedAtMs: DateTime.now().millisecondsSinceEpoch,
            );
            await stateStore.save(_state!);
            _emit();
          }
          if (committed < results.length) {
            // A batch failed (already paused) or was cancelled. Stop.
            if (_pauseRequested) {
              break;
            }
            return;
          }
          if (_overBudget(_state!)) {
            await _pause(CoveragePauseReason.budget);
            return;
          }
        }
        if (_pauseRequested) break;
        if (page.nextCursor == null) {
          await _complete();
          return;
        }
      }
      await _finishPauseOrCancel();
    } catch (_) {
      await _pause(CoveragePauseReason.failed);
    } finally {
      _running = false;
    }
  }

  Future<void> _finishPauseOrCancel() async {
    if (_cancelRequested && _state != null) {
      _cancelRequested = false;
      _pauseRequested = false;
      _state = _state!.copyWith(
        status: CoverageJobStatus.cancelled,
        pauseReason: () => null,
      );
      await stateStore.save(_state!);
      _emit();
    } else if (_pauseRequested && _state?.status == CoverageJobStatus.running) {
      await _pause(_pauseRequestReason ?? CoveragePauseReason.manual);
    }
  }

  /// Returns false when paused, cancelled, or failed mid-phase.
  Future<bool> _runTreeBfsPhase({
    required String snapshotId,
    required CoveragePlanSummary plan,
    required AnalyzeTreeBatch analyzeTreeBatch,
  }) async {
    final queue = <CoverageTreeNode>[];
    var seedCursor = _state!.treeQueueCursor;
    while (!_pauseRequested) {
      final page = await engine.nextTreePage(
        snapshotId,
        plan.planVersion,
        seedCursor,
      );
      if (page.nodes.isEmpty && page.nextCursor == null) {
        break;
      }
      queue.addAll(page.nodes);
      final next = page.nextCursor;
      if (next == null) {
        seedCursor = seedCursor + 1;
        await _persistJobState(treeQueueCursor: seedCursor);
        break;
      }
      seedCursor = next;
      await _persistJobState(treeQueueCursor: seedCursor);
    }

    while (!_pauseRequested && queue.isNotEmpty) {
      if (_overBudget(_state!)) {
        await _pause(CoveragePauseReason.budget);
        return false;
      }
      final levelSize = queue.length;
      final levelNodes = queue.sublist(0, levelSize);
      queue.removeRange(0, levelSize);

      final chunks = <List<CoverageTreeNode>>[];
      for (var i = 0; i < levelNodes.length; i += treeBatchSize) {
        final end = i + treeBatchSize < levelNodes.length
            ? i + treeBatchSize
            : levelNodes.length;
        chunks.add(levelNodes.sublist(i, end));
      }
      for (
        var waveStart = 0;
        waveStart < chunks.length;
        waveStart += treeMaxInFlight
      ) {
        if (_pauseRequested) return false;
        if (_overBudget(_state!)) {
          await _pause(CoveragePauseReason.budget);
          return false;
        }
        final remaining = _remainingTreeWaveSlots(_state!);
        if (remaining <= 0) {
          await _pause(CoveragePauseReason.budget);
          return false;
        }
        final waveEnd = waveStart + remaining < chunks.length
            ? waveStart + remaining
            : chunks.length;
        final waveChunks = chunks.sublist(waveStart, waveEnd);
        final results = await Future.wait(
          waveChunks.map(
            (chunk) =>
                _analyzeTreeWithRetry(snapshotId, chunk, analyzeTreeBatch),
          ),
        );
        var committed = 0;
        for (final result in results) {
          if (result == null) break;
          committed++;
        }
        var waveTokens = 0;
        var waveCredits = 0;
        var waveLocalResolved = 0;
        var waveAnalyzedFiles = 0;
        for (var i = 0; i < committed; i++) {
          final result = results[i]!;
          waveTokens += result.usage.tokens;
          waveCredits += result.usage.credits;
          waveLocalResolved += result.localResolved;
          waveAnalyzedFiles += result.analyzedFiles;
          queue.addAll(result.childrenToEnqueue);
        }
        final nodesThisWave = waveChunks
            .take(committed)
            .fold<int>(0, (sum, chunk) => sum + chunk.length);
        if (committed > 0) {
          final current = _state!;
          _state = current.copyWith(
            treeNodesCompleted: current.treeNodesCompleted + nodesThisWave,
            usedTokens: current.usedTokens + waveTokens,
            usedCredits: current.usedCredits + waveCredits,
            localResolvedFiles: current.localResolvedFiles + waveLocalResolved,
            analyzedFiles: current.analyzedFiles + waveAnalyzedFiles,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          await stateStore.save(_state!);
          _emit();
        }
        if (committed < results.length) {
          return false;
        }
        if (_overBudget(_state!)) {
          await _pause(CoveragePauseReason.budget);
          return false;
        }
      }
    }
    return true;
  }

  Future<bool> _runTailPhase({
    required String snapshotId,
    required CoveragePlanSummary plan,
  }) async {
    var tailCursor = _state!.tailQueueCursor;
    while (!_pauseRequested) {
      if (_overBudget(_state!)) {
        await _pause(CoveragePauseReason.budget);
        return false;
      }
      final page = await engine.nextTailPage(
        snapshotId,
        plan.planVersion,
        tailCursor,
        pageSize: batchSize,
      );
      if (page.rows.isEmpty) {
        if (page.nextCursor == null) return true;
        tailCursor = page.nextCursor!;
        await _persistJobState(tailQueueCursor: tailCursor);
        continue;
      }
      final rows = <CoverageRow>[];
      for (var i = 0; i < page.rows.length; i++) {
        final row = page.rows[i];
        rows.add(
          CoverageRow(
            rowIndex: tailCursor + i,
            kind: CoverageRowKind.file,
            path: row.path,
            sizeBytes: row.sizeBytes,
          ),
        );
      }
      final chunks = <List<CoverageRow>>[];
      for (var i = 0; i < rows.length; i += batchSize) {
        final end = i + batchSize < rows.length ? i + batchSize : rows.length;
        chunks.add(rows.sublist(i, end));
      }
      for (
        var waveStart = 0;
        waveStart < chunks.length;
        waveStart += maxInFlight
      ) {
        if (_pauseRequested) return false;
        if (_overBudget(_state!)) {
          await _pause(CoveragePauseReason.budget);
          return false;
        }
        final remaining = _remainingWaveSlots(_state!);
        if (remaining <= 0) {
          await _pause(CoveragePauseReason.budget);
          return false;
        }
        final waveEnd = waveStart + remaining < chunks.length
            ? waveStart + remaining
            : chunks.length;
        final results = await Future.wait(
          chunks
              .sublist(waveStart, waveEnd)
              .map((chunk) => _analyzeWithRetry(snapshotId, chunk)),
        );
        var committed = 0;
        for (final result in results) {
          if (result == null) break;
          committed++;
        }
        var waveAnalyzed = 0;
        var waveTokens = 0;
        var waveCredits = 0;
        for (var i = 0; i < committed; i++) {
          final result = results[i]!;
          waveAnalyzed += result.memberFiles;
          waveTokens += result.usage.tokens;
          waveCredits += result.usage.credits;
        }
        if (committed > 0) {
          final waveTailCursor =
              chunks[waveStart + committed - 1].last.rowIndex + 1;
          final current = _state!;
          _state = current.copyWith(
            tailQueueCursor: waveTailCursor,
            analyzedFiles: current.analyzedFiles + waveAnalyzed,
            usedTokens: current.usedTokens + waveTokens,
            usedCredits: current.usedCredits + waveCredits,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          await stateStore.save(_state!);
          _emit();
        }
        if (committed < results.length) {
          return false;
        }
        if (_overBudget(_state!)) {
          await _pause(CoveragePauseReason.budget);
          return false;
        }
      }
      final next = page.nextCursor;
      if (next == null) return true;
      tailCursor = next;
      await _persistJobState(tailQueueCursor: tailCursor);
    }
    return !_pauseRequested;
  }

  Future<void> _persistJobState({
    int? treeQueueCursor,
    int? tailQueueCursor,
  }) async {
    final current = _state;
    if (current == null) return;
    _state = current.copyWith(
      treeQueueCursor: treeQueueCursor,
      tailQueueCursor: tailQueueCursor,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await stateStore.save(_state!);
    _emit();
  }

  Future<
    ({
      BatchUsage usage,
      int localResolved,
      int analyzedFiles,
      List<CoverageTreeNode> childrenToEnqueue,
    })?
  >
  _analyzeTreeWithRetry(
    String snapshotId,
    List<CoverageTreeNode> nodes,
    AnalyzeTreeBatch analyzeTreeBatch,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final outcome = await analyzeTreeBatch(nodes);
        await verdictStore.appendAll(snapshotId, outcome.verdicts);
        final byPath = {
          for (final verdict in outcome.verdicts) verdict.path: verdict,
        };
        var localResolved = 0;
        var analyzedFiles = 0;
        final children = <CoverageTreeNode>[];
        for (final node in nodes) {
          final dirVerdict = byPath[node.path];
          if (dirVerdict == null) continue;
          if ((dirVerdict.verdict == 'keep' ||
                  dirVerdict.verdict == 'safe_to_remove') &&
              dirVerdict.confidence == 'high') {
            final propagated = await engine.applyDirVerdict(
              snapshotId,
              node.path,
              dirVerdict.verdict,
              dirVerdict.confidence,
              node.role,
            );
            if (propagated.isNotEmpty) {
              await verdictStore.appendAll(snapshotId, propagated);
              localResolved += propagated.length;
              analyzedFiles += propagated.length;
            }
          } else if (dirVerdict.verdict == 'drill_down') {
            final expanded = await engine.expandTreeNode(snapshotId, node.path);
            children.addAll(expanded);
          }
        }
        return (
          usage: outcome.usage,
          localResolved: localResolved,
          analyzedFiles: analyzedFiles,
          childrenToEnqueue: children,
        );
      } on CoverageCancelledException {
        return null;
      } on CoverageAnalyzeException catch (e) {
        await _recordFailedTreeBatch(nodes, creditsCharged: e.creditsCharged);
        await _pause(
          CoveragePauseReason.failed,
          detail: CoveragePauseDetail.parse,
        );
        return null;
      } catch (e) {
        final retryable =
            e is http.ClientException ||
            e.toString().contains('api_error:502') ||
            e.toString().contains('TimeoutException');
        if (!retryable || attempt == 2) {
          await _recordFailedTreeBatch(nodes);
          await _pause(
            CoveragePauseReason.failed,
            detail: retryable
                ? CoveragePauseDetail.network
                : CoveragePauseDetail.api,
          );
          return null;
        }
        await Future<void>.delayed(
          Duration(milliseconds: 200 * (1 << attempt)),
        );
      }
    }
    return (
      usage: const BatchUsage(tokens: 0, credits: 0),
      localResolved: 0,
      analyzedFiles: 0,
      childrenToEnqueue: const <CoverageTreeNode>[],
    );
  }

  Future<void> _recordFailedTreeBatch(
    List<CoverageTreeNode> nodes, {
    int creditsCharged = 0,
  }) async {
    if (nodes.isEmpty) return;
    final current = _state;
    if (current == null) return;
    _state = current.copyWith(
      failedBatchPaths: nodes.map((node) => node.path).toList(growable: false),
      creditsChargedNoVerdict: creditsCharged > 0
          ? current.creditsChargedNoVerdict + creditsCharged
          : current.creditsChargedNoVerdict,
    );
    await stateStore.save(_state!);
    _emit();
  }

  int _remainingTreeWaveSlots(CoverageJobState state) {
    final run = state.budgetCredits > 0
        ? (state.budgetCredits - state.usedCredits).clamp(0, treeMaxInFlight)
        : treeMaxInFlight;
    final wallet = platformCreditsRemaining?.call();
    if (wallet == null) return run;
    return min(run, wallet.clamp(0, treeMaxInFlight));
  }

  Future<({int memberFiles, BatchUsage usage})?> _analyzeWithRetry(
    String snapshotId,
    List<CoverageRow> rows,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final outcome = await analyzeBatch(rows);
        await verdictStore.appendAll(snapshotId, outcome.verdicts);
        return (
          memberFiles: rows.fold<int>(0, (sum, row) => sum + row.memberFiles),
          usage: outcome.usage,
        );
      } on CoverageCancelledException {
        return null;
      } on CoverageAnalyzeException catch (e) {
        await _recordFailedBatch(rows, creditsCharged: e.creditsCharged);
        await _pause(
          CoveragePauseReason.failed,
          detail: CoveragePauseDetail.parse,
        );
        return null;
      } catch (e) {
        final retryable =
            e is http.ClientException ||
            e.toString().contains('api_error:502') ||
            e.toString().contains('TimeoutException');
        if (!retryable || attempt == 2) {
          await _recordFailedBatch(rows);
          await _pause(
            CoveragePauseReason.failed,
            detail: retryable
                ? CoveragePauseDetail.network
                : CoveragePauseDetail.api,
          );
          return null;
        }
        await Future<void>.delayed(
          Duration(milliseconds: 200 * (1 << attempt)),
        );
      }
    }
    return (memberFiles: 0, usage: const BatchUsage(tokens: 0, credits: 0));
  }

  bool _overBudget(CoverageJobState state) {
    if (state.budgetTokens > 0 && state.usedTokens >= state.budgetTokens) {
      return true;
    }
    return state.budgetCredits > 0 && state.usedCredits >= state.budgetCredits;
  }

  int _remainingWaveSlots(CoverageJobState state) {
    final run = state.budgetCredits > 0
        ? (state.budgetCredits - state.usedCredits).clamp(0, maxInFlight)
        : maxInFlight;
    final wallet = platformCreditsRemaining?.call();
    if (wallet == null) return run;
    return min(run, wallet.clamp(0, maxInFlight));
  }

  Future<void> _recordFailedBatch(
    List<CoverageRow> rows, {
    int creditsCharged = 0,
  }) async {
    if (rows.isEmpty) return;
    final current = _state;
    if (current == null) return;
    _state = current.copyWith(
      failedBatchPaths: rows.map((row) => row.path).toList(growable: false),
      creditsChargedNoVerdict: creditsCharged > 0
          ? current.creditsChargedNoVerdict + creditsCharged
          : current.creditsChargedNoVerdict,
    );
    await stateStore.save(_state!);
    _emit();
  }

  Future<void> _pause(
    CoveragePauseReason reason, {
    CoveragePauseDetail? detail,
  }) async {
    _pauseRequested = false;
    _pauseRequestReason = null;
    _state = _state?.copyWith(
      status: CoverageJobStatus.paused,
      pauseReason: () => reason,
      pauseDetail: () => reason == CoveragePauseReason.failed ? detail : null,
    );
    if (_state != null) await stateStore.save(_state!);
    _emit();
  }

  Future<void> _complete() async {
    _state = _state?.copyWith(
      status: CoverageJobStatus.completed,
      pauseReason: () => null,
    );
    if (_state != null) await stateStore.save(_state!);
    _emit();
  }

  void _emit() {
    final state = _state;
    if (state != null && !_states.isClosed) _states.add(state);
  }
}
