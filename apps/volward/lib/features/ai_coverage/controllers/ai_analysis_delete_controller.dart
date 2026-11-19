import 'dart:async';

import 'package:flutter/foundation.dart';

import '../views/ai_analysis_workspace_view_state.dart';
import 'ai_analysis_workspace_controller.dart';

/// Owns delete targets, busy state, partial report, retry targets and
/// completion notification. A delete completing after detach must clear busy
/// without notifying the detached workspace.
class AiAnalysisDeleteController extends ChangeNotifier {
  AiAnalysisDeleteController({
    required AiAnalysisWorkspaceController owner,
    String? ownerId,
  }) : _owner = owner,
       _ownerId = ownerId ?? owner.activeOwnerId;

  @visibleForTesting
  factory AiAnalysisDeleteController.forTest({bool delayedDelete = false}) {
    final owner = AiAnalysisWorkspaceController(ownerId: 'owner-a');
    final controller = AiAnalysisDeleteController(
      owner: owner,
      ownerId: 'owner-a',
    );
    if (delayedDelete) {
      final completer = Completer<Map<String, dynamic>>();
      controller._executor = () => completer.future;
      controller._pendingDelete = completer;
    }
    return controller;
  }

  final AiAnalysisWorkspaceController _owner;
  String? _ownerId;

  bool _busy = false;
  bool detached = false;
  List<String> _retryTargets = const [];
  int? _partialDeleteFailedCount;
  int? _partialDeleteFreedBytes;

  bool get busy => _busy;
  List<String> get retryTargets => _retryTargets;
  int? get partialDeleteFailedCount => _partialDeleteFailedCount;
  int? get partialDeleteFreedBytes => _partialDeleteFreedBytes;

  Future<Map<String, dynamic>> Function()? _executor;
  Completer<Map<String, dynamic>>? _pendingDelete;

  AiWorkspaceDeleteState get deleteState => AiWorkspaceDeleteState(
    busy: _busy,
    retryTargets: _retryTargets,
    partialDeleteFailedCount: _partialDeleteFailedCount,
    partialDeleteFreedBytes: _partialDeleteFreedBytes,
  );

  @visibleForTesting
  void completeDelayedDelete([Map<String, dynamic>? report]) {
    _pendingDelete?.complete(report ?? const {});
  }

  void configure({String? ownerId}) {
    final nextOwnerId = ownerId ?? _owner.activeOwnerId;
    if (nextOwnerId != _ownerId) {
      detachOwner();
      _ownerId = nextOwnerId;
      detached = false;
    }
  }

  void detachOwner() {
    detached = true;
    _busy = false;
    _touch();
  }

  void reset() {
    _retryTargets = const [];
    _partialDeleteFailedCount = null;
    _partialDeleteFreedBytes = null;
    _touch();
  }

  /// Runs a delete through confirm/execute with owner and detach guards.
  ///
  /// Returns `true` when a non-empty successful delete completed, and calls
  /// [onCompleted] exactly once for a live, attached owner.
  Future<bool> deleteSelected({
    required int generation,
    required Future<bool> Function(int generation) confirm,
    Future<Map<String, dynamic>> Function(int generation)? execute,
    void Function(bool busy)? onBusyChanged,
    required void Function() onCompleted,
  }) async {
    if (_busy) return false;
    final run =
        execute ??
        ((int generation) async =>
            _executor?.call() ?? Future.value(const <String, dynamic>{}));
    try {
      final confirmed = await confirm(generation);
      if (detached || !_isCurrentOwner(generation) || !confirmed) {
        return false;
      }
      _busy = true;
      onBusyChanged?.call(true);
      _partialDeleteFailedCount = null;
      _partialDeleteFreedBytes = null;
      _touch();
      final report = await run(generation);
      if (detached) {
        return false;
      }
      if (!_isCurrentOwner(generation)) {
        return false;
      }
      final failed = report['failed_paths'];
      final failedCount = failed is List ? failed.length : 0;
      final failedTargets = failed is List
          ? failed.whereType<String>().toList(growable: false)
          : const <String>[];
      final freedAfter = (report['freed_bytes'] as num?)?.toInt() ?? 0;
      final deletedCount = (report['deleted_count'] as num?)?.toInt() ?? 0;
      if (failedCount > 0) {
        _retryTargets = failedTargets;
        _partialDeleteFailedCount = failedCount;
        _partialDeleteFreedBytes = freedAfter;
        _touch();
        return false;
      }
      _retryTargets = const [];
      _touch();
      if (deletedCount > 0) onCompleted();
      return deletedCount > 0;
    } finally {
      if (_busy) {
        _busy = false;
        if (!detached) {
          onBusyChanged?.call(false);
          _touch();
        }
      }
    }
  }

  bool _isCurrentOwner(int generation) {
    final owned = _ownerId == null || _owner.activeOwnerId == _ownerId;
    return owned && _owner.isCurrent(generation);
  }

  bool _disposed = false;

  void _touch() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
