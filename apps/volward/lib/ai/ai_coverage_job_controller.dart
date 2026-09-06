import 'dart:async';

import 'cancel_token.dart';
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

class CoverageJobController {
  CoverageJobController({
    required this.engine,
    required this.verdictStore,
    required this.stateStore,
    required this.analyzeBatch,
    this.batchSize = 40,
    this.maxInFlight = 4,
    CancelToken? cancelToken,
  }) : _cancelToken = cancelToken ?? CancelToken();

  final CoverageEngine engine;
  final CoverageVerdictStore verdictStore;
  final CoverageJobStateStore stateStore;
  final AnalyzeBatch analyzeBatch;
  final int batchSize;
  final int maxInFlight;
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
      budgetTokens: budgetTokens > 0 ? budgetTokens : current.budgetTokens,
      budgetCredits: budgetCredits > 0 ? budgetCredits : current.budgetCredits,
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

      final plan = await engine.buildPlan(snapshotId);
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
      );
      await stateStore.save(_state!);
      _emit();

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
          final waveEnd = waveStart + maxInFlight < chunks.length
              ? waveStart + maxInFlight
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
      if (_cancelRequested && _state != null) {
        _cancelRequested = false;
        _pauseRequested = false;
        _state = _state!.copyWith(
          status: CoverageJobStatus.cancelled,
          pauseReason: () => null,
        );
        await stateStore.save(_state!);
        _emit();
      } else if (_pauseRequested &&
          _state?.status == CoverageJobStatus.running) {
        await _pause(_pauseRequestReason ?? CoveragePauseReason.manual);
      }
    } catch (_) {
      await _pause(CoveragePauseReason.failed);
    } finally {
      _running = false;
    }
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
      } catch (_) {
        if (attempt == 2) {
          await _pause(CoveragePauseReason.failed);
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

  Future<void> _pause(CoveragePauseReason reason) async {
    _pauseRequested = false;
    _pauseRequestReason = null;
    _state = _state?.copyWith(
      status: CoverageJobStatus.paused,
      pauseReason: () => reason,
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
