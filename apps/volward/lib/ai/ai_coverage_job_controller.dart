import 'dart:async';

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
    this.maxInFlight = 2,
  });

  final CoverageEngine engine;
  final CoverageVerdictStore verdictStore;
  final CoverageJobStateStore stateStore;
  final AnalyzeBatch analyzeBatch;
  final int batchSize;
  final int maxInFlight;

  CoverageJobState? _state;
  bool _pauseRequested = false;
  bool _running = false;
  final _states = StreamController<CoverageJobState>.broadcast();

  CoverageJobState? get state => _state;
  Stream<CoverageJobState> get states => _states.stream;

  Future<CoverageJobState> start(
    String snapshotId, {
    required int budgetTokens,
    required int budgetCredits,
  }) async {
    final existing = await stateStore.load(snapshotId);
    final base =
        existing ??
        CoverageJobState(
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
          budgetTokens: budgetTokens,
          budgetCredits: budgetCredits,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
    _state = base.copyWith(
      status: CoverageJobStatus.running,
      pauseReason: () => null,
      budgetTokens: budgetTokens == 0 ? base.budgetTokens : budgetTokens,
      budgetCredits: budgetCredits == 0 ? base.budgetCredits : budgetCredits,
    );
    await stateStore.save(_state!);
    _emit();
    await _run();
    return _state!;
  }

  Future<CoverageJobState> pause() async {
    _pauseRequested = true;
    return _state ?? _idleFor('');
  }

  Future<CoverageJobState> resume() async {
    final current = _state;
    if (current == null) return _idleFor('');
    _pauseRequested = false;
    _state = current.copyWith(
      status: CoverageJobStatus.running,
      pauseReason: () => null,
    );
    await stateStore.save(_state!);
    _emit();
    await _run();
    return _state!;
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
        final results = await Future.wait(
          chunks
              .take(maxInFlight)
              .map((chunk) => _analyzeWithRetry(snapshotId, chunk)),
        );
        if (results.contains(null)) {
          return;
        }
        final analyzed = results.fold<int>(0, (sum, r) => sum + (r ?? 0));
        final nextCursor = page.nextCursor ?? page.rows.last.rowIndex + 1;
        final current = _state!;
        _state = current.copyWith(
          cursor: nextCursor,
          analyzedFiles: current.analyzedFiles + analyzed,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        await stateStore.save(_state!);
        _emit();
        if (page.nextCursor == null) {
          await _complete();
          return;
        }
      }
    } catch (_) {
      await _pause(CoveragePauseReason.failed);
    } finally {
      _running = false;
    }
  }

  Future<int?> _analyzeWithRetry(
    String snapshotId,
    List<CoverageRow> rows,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final outcome = await analyzeBatch(rows);
        await verdictStore.appendAll(snapshotId, outcome.verdicts);
        final usage = outcome.usage;
        _state = _state?.copyWith(
          usedTokens: (_state?.usedTokens ?? 0) + usage.tokens,
          usedCredits: (_state?.usedCredits ?? 0) + usage.credits,
        );
        return rows.fold<int>(0, (sum, row) => sum + row.memberFiles);
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
    return 0;
  }

  bool _overBudget(CoverageJobState state) {
    if (state.budgetTokens > 0 && state.usedTokens >= state.budgetTokens) {
      return true;
    }
    return state.budgetCredits > 0 && state.usedCredits >= state.budgetCredits;
  }

  Future<void> _pause(CoveragePauseReason reason) async {
    _pauseRequested = false;
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
