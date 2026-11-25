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
    this.workerEntryPoint = volwardCoverageJobWorker,
  });

  final String catalogPath;
  final Map<String, dynamic> workerConfig;
  @visibleForTesting
  final void Function(List<dynamic>) workerEntryPoint;

  Isolate? _isolate;
  SendPort? _controlPort;
  ReceivePort? _mainPort;
  StreamSubscription<dynamic>? _mainSub;
  CoverageJobState? _state;
  final _states = StreamController<CoverageJobState>.broadcast();
  final _ready = Completer<void>();
  final _idleWaiters = <int, Completer<void>>{};
  final _commandAcks = <int, Completer<CoverageJobState>>{};
  int _nextRequestId = 0;
  bool _disposed = false;
  bool _closing = false;
  Future<void>? _shutdown;
  Future<void>? _disposing;
  StateError? _workerFailure;
  bool _workerDisposeAcknowledged = false;
  Future<void>? _starting;

  bool get started => _isolate != null;

  CoverageJobState? get state => _state;
  Stream<CoverageJobState> get states => _states.stream;

  Future<void> ensureStarted() {
    if (_disposed || _closing) throw StateError('Coverage host is disposed');
    if (_workerFailure != null) throw _workerFailure!;
    return _starting ??= _start();
  }

  Future<void> _start() async {
    _mainPort = ReceivePort();
    final config = Map<String, dynamic>.from(workerConfig)
      ..['catalogPath'] = catalogPath;
    _isolate = await Isolate.spawn(
      workerEntryPoint,
      [_mainPort!.sendPort, config],
      debugName: 'volward-coverage-job',
      onExit: _mainPort!.sendPort,
      onError: _mainPort!.sendPort,
    );
    _mainSub = _mainPort!.listen(_onWorkerMessage);
    await _ready.future;
  }

  void _failWorker(StateError error) {
    final failure = _workerFailure ??= error;
    for (final pending in _commandAcks.values.toList()) {
      if (!pending.isCompleted) pending.completeError(failure);
    }
    _commandAcks.clear();
    for (final pending in _idleWaiters.values.toList()) {
      if (!pending.isCompleted) pending.completeError(failure);
    }
    _idleWaiters.clear();
    if (!_ready.isCompleted) _ready.completeError(failure);
  }

  void _onWorkerMessage(dynamic message) {
    if (message == null) {
      if (!_workerDisposeAcknowledged) {
        _failWorker(StateError('coverage worker exited'));
      }
      return;
    }
    if (message is List && message.isNotEmpty) {
      _failWorker(StateError('coverage worker error: ${message.first}'));
      return;
    }
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
        if (message['cmd'] == 'dispose') _workerDisposeAcknowledged = true;
        final raw = message['state'];
        CoverageJobState? ackState;
        if (raw is Map) {
          ackState = CoverageJobState.fromJson(Map<String, dynamic>.from(raw));
          _applyState(ackState);
        }
        final id = message['requestId'];
        final pending = _commandAcks.remove(id);
        if (pending != null && !pending.isCompleted) {
          pending.complete(
            ackState ??
                _state ??
                CoverageJobState.fromJson(<String, dynamic>{
                  'snapshot_id': '',
                  'root_path': '',
                  'plan_version': 1,
                  'status': CoverageJobStatus.idle.name,
                }),
          );
        }
      case 'idle':
        final waiter = _idleWaiters.remove(message['requestId']);
        if (waiter != null && !waiter.isCompleted) waiter.complete();
      case 'error':
        debugPrint(
          'CoverageJobIsolateHost: worker error: ${message['message']}\n'
          '${message['stack'] ?? ''}',
        );
        final error = StateError(
          message['message']?.toString() ?? 'coverage worker error',
        );
        final id = message['requestId'];
        if (id == null && _ready.isCompleted) {
          _failWorker(error);
        } else {
          final command = _commandAcks.remove(id);
          if (command != null && !command.isCompleted) {
            command.completeError(error);
          }
          final idle = _idleWaiters.remove(id);
          if (idle != null && !idle.isCompleted) idle.completeError(error);
        }
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

  Future<CoverageJobState> _sendCommand(
    Map<String, dynamic> command, {
    bool duringDispose = false,
    bool waitForCompletion = false,
  }) async {
    if (!duringDispose) await ensureStarted();
    if ((_disposed || _closing) && !duringDispose) {
      throw StateError('Coverage host is disposed');
    }
    if (_workerFailure != null) throw _workerFailure!;
    final port = _controlPort;
    if (port == null) throw StateError('coverage worker not ready');
    final id = _nextRequestId++;
    final ack = Completer<CoverageJobState>();
    _commandAcks[id] = ack;
    port.send({...command, 'requestId': id});
    try {
      if (waitForCompletion) return await ack.future;
      return await ack.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () =>
            _state ??
            CoverageJobState.fromJson({
              'snapshot_id': '',
              'root_path': '',
              'plan_version': 1,
              'status': CoverageJobStatus.idle.name,
            }),
      );
    } finally {
      _commandAcks.remove(id);
    }
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
      _sendCommand(<String, dynamic>{'cmd': 'pause'}, waitForCompletion: true);

  Future<CoverageJobState> cancel(String snapshotId) => _sendCommand(
    <String, dynamic>{'cmd': 'cancel', 'snapshotId': snapshotId},
    waitForCompletion: true,
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

  Future<void> markAppQuit() async {
    await _sendCommand(<String, dynamic>{
      'cmd': 'markAppQuit',
    }, waitForCompletion: true);
  }

  Future<void> waitUntilIdle() async {
    await ensureStarted();
    if (_disposed || _closing) throw StateError('Coverage host is disposed');
    final id = _nextRequestId++;
    final waiter = Completer<void>();
    _idleWaiters[id] = waiter;
    _controlPort!.send({'cmd': 'waitUntilIdle', 'requestId': id});
    try {
      await waiter.future;
    } finally {
      _idleWaiters.remove(id);
    }
  }

  /// Permanently close admission, then stop active work. Unlike markAppQuit,
  /// deferred requests cannot restart a job after this barrier.
  Future<void> beginShutdown() {
    _closing = true;
    return _shutdown ??= () async {
      // Do not launch an unused worker just to shut it down.
      final starting = _starting;
      if (starting == null) return;
      await starting;
      if (_workerFailure != null) throw _workerFailure!;
      await _sendCommand(
        {'cmd': 'shutdown'},
        duringDispose: true,
        waitForCompletion: true,
      );
    }();
  }

  Future<void> dispose() {
    _disposed = true;
    return _disposing ??= _dispose();
  }

  Future<void> _dispose() async {
    Object? failure;
    StackTrace? failureStack;
    Future<void> attempt(FutureOr<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }

    await attempt(() async {
      await beginShutdown();
      if (_controlPort != null) {
        await _sendCommand(
          {'cmd': 'dispose'},
          duringDispose: true,
          waitForCompletion: true,
        );
      }
    });
    final error = StateError('Coverage host is disposed');
    for (final waiter in _idleWaiters.values) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
    _idleWaiters.clear();
    for (final waiter in _commandAcks.values) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
    _commandAcks.clear();
    await attempt(() async => _mainSub?.cancel());
    await attempt(() => _mainPort?.close());
    await attempt(() => _isolate?.kill(priority: Isolate.immediate));
    _isolate = null;
    _controlPort = null;
    if (!_states.isClosed) await attempt(_states.close);
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  }
}
