import 'dart:async';

/// Cooperative cancellation signal shared between the job controller and the
/// AI transport layer.
///
/// [cancel] completes [whenCancelled], which the transport observes to abort
/// an in-flight request. [reset] arms a fresh signal for the next run.
class CancelToken {
  Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  void reset() {
    if (_completer.isCompleted) {
      _completer = Completer<void>();
    }
  }
}

/// Thrown by a provider when an in-flight request is cancelled via
/// [CancelToken]. The caller must treat this as a stop, not a failure —
/// no retry, no persistence.
class CoverageCancelledException implements Exception {
  const CoverageCancelledException();

  @override
  String toString() => 'CoverageCancelledException';
}
