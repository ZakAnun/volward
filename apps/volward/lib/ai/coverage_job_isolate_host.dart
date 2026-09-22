import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'ai_coverage_job_controller.dart';
import 'coverage_job_state.dart';
import 'coverage_job_worker.dart';
import 'coverage_models.dart';

/// Runs [CoverageJobController] on a background isolate so native FFI does not
/// block the UI thread (macOS wait cursor).
class CoverageJobIsolateHost {
  CoverageJobIsolateHost({
    required this.catalogPath,
    required this.workerConfig,
  });

  final String catalogPath;
  final Map<String, dynamic> workerConfig;

  Isolate? _isolate;
  SendPort? _controlPort;
  ReceivePort? _mainPort;
  StreamSubscription<dynamic>? _mainSub;
  CoverageJobState? _state;
  final _states = StreamController<CoverageJobState>.broadcast();
  final _ready = Completer<void>();
  final _idleWaiters = <Completer<void>>[];
  Completer<CoverageJobState>? _commandAck;

  CoverageJobState? get state => _state;
  Stream<CoverageJobState> get states => _states.stream;

  Future<void> ensureStarted() async {
    if (_controlPort != null) {
      return _ready.future;
    }
    _mainPort = ReceivePort();
    final config = Map<String, dynamic>.from(workerConfig)
      ..['catalogPath'] = catalogPath;
    _isolate = await Isolate.spawn(volwardCoverageJobWorker, [
      _mainPort!.sendPort,
      config,
    ], debugName: 'volward-coverage-job');
    _mainSub = _mainPort!.listen(_onWorkerMessage);
    await _ready.future;
  }

  void _onWorkerMessage(dynamic message) {
    if (message is! Map) return;
    final type = message['type']?.toString();
    switch (type) {
      case 'ready':
        if (message['failed'] == true) {
          final err =
              message['message']?.toString() ?? 'coverage worker failed';
          if (!_ready.isCompleted) {
            _ready.completeError(StateError(err));
          }
          break;
        }
        _controlPort = message['controlPort'] as SendPort?;
        if (!_ready.isCompleted) _ready.complete();
      case 'state':
        final raw = message['state'];
        if (raw is Map) {
          _applyState(
            CoverageJobState.fromJson(Map<String, dynamic>.from(raw)),
          );
        }
      case 'ack':
        final raw = message['state'];
        CoverageJobState? ackState;
        if (raw is Map) {
          ackState = CoverageJobState.fromJson(Map<String, dynamic>.from(raw));
          _applyState(ackState);
        }
        final pending = _commandAck;
        if (pending != null && !pending.isCompleted) {
          pending.complete(
            ackState ??
                _state ??
                CoverageJobState.fromJson(<String, dynamic>{
                  'snapshot_id': '',
                  'root_path': '',
                  'plan_version': 1,
                  'cursor': 0,
                  'total_unclassified': 0,
                  'analyzed_files': 0,
                  'pre_classified_count': 0,
                  'status': CoverageJobStatus.idle.name,
                  'used_tokens': 0,
                  'used_credits': 0,
                  'budget_tokens': 0,
                  'budget_credits': 0,
                  'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
                }),
          );
          _commandAck = null;
        }
      case 'idle':
        for (final waiter in _idleWaiters) {
          if (!waiter.isCompleted) waiter.complete();
        }
        _idleWaiters.clear();
      case 'error':
        debugPrint(
          'CoverageJobIsolateHost: worker error: ${message['message']}\n'
          '${message['stack'] ?? ''}',
        );
        if (!_ready.isCompleted) {
          _ready.completeError(
            StateError(
              message['message']?.toString() ?? 'coverage worker error',
            ),
          );
        }
    }
  }

  void _applyState(CoverageJobState state) {
    _state = state;
    if (!_states.isClosed) {
      _states.add(state);
    }
  }

  Future<CoverageJobState> _sendCommand(Map<String, dynamic> command) async {
    await ensureStarted();
    final port = _controlPort;
    if (port == null) {
      throw StateError('coverage worker not ready');
    }
    final ack = Completer<CoverageJobState>();
    _commandAck = ack;
    port.send(command);
    return ack.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () =>
          _state ??
          CoverageJobState.fromJson(<String, dynamic>{
            'snapshot_id': '',
            'root_path': '',
            'plan_version': 1,
            'cursor': 0,
            'total_unclassified': 0,
            'analyzed_files': 0,
            'pre_classified_count': 0,
            'status': CoverageJobStatus.idle.name,
            'used_tokens': 0,
            'used_credits': 0,
            'budget_tokens': 0,
            'budget_credits': 0,
            'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
          }),
    );
  }

  Future<CoverageJobState> start(
    String snapshotId, {
    required int budgetTokens,
    required int budgetCredits,
    bool detachRun = true,
  }) async {
    return _sendCommand(<String, dynamic>{
      'cmd': 'start',
      'snapshotId': snapshotId,
      'budgetTokens': budgetTokens,
      'budgetCredits': budgetCredits,
    });
  }

  Future<CoverageJobState> pause() =>
      _sendCommand(<String, dynamic>{'cmd': 'pause'});

  Future<CoverageJobState> cancel(String snapshotId) => _sendCommand(
    <String, dynamic>{'cmd': 'cancel', 'snapshotId': snapshotId},
  );

  Future<CoverageJobState> resume(
    String snapshotId, {
    bool detachRun = true,
    CoveragePlanSummary? preloadedPlan,
  }) async {
    return _sendCommand(<String, dynamic>{
      'cmd': 'resume',
      'snapshotId': snapshotId,
      if (preloadedPlan != null) 'preloadedPlan': preloadedPlan.toJson(),
    });
  }

  Future<CoverageJobState> raiseBudgetAndResume({
    required String snapshotId,
    required int budgetTokens,
    required int budgetCredits,
    bool detachRun = true,
    CoveragePlanSummary? preloadedPlan,
  }) async {
    return _sendCommand(<String, dynamic>{
      'cmd': 'raiseBudgetAndResume',
      'snapshotId': snapshotId,
      'budgetTokens': budgetTokens,
      'budgetCredits': budgetCredits,
      if (preloadedPlan != null) 'preloadedPlan': preloadedPlan.toJson(),
    });
  }

  Future<void> _sendFireAndForget(Map<String, dynamic> command) async {
    await ensureStarted();
    _controlPort!.send(command);
  }

  Future<void> markAppQuit() =>
      _sendFireAndForget(<String, dynamic>{'cmd': 'markAppQuit'});

  Future<void> waitUntilIdle() async {
    final waiter = Completer<void>();
    _idleWaiters.add(waiter);
    await _sendFireAndForget(<String, dynamic>{'cmd': 'waitUntilIdle'});
    await waiter.future;
  }

  Future<void> dispose() async {
    try {
      if (_controlPort != null) {
        await _sendCommand(<String, dynamic>{
          'cmd': 'dispose',
        }).timeout(const Duration(seconds: 3));
      }
    } catch (_) {
      // Best-effort shutdown before killing the isolate.
    }
    _mainSub?.cancel();
    _mainPort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _controlPort = null;
    if (!_states.isClosed) {
      _states.close();
    }
  }
}
