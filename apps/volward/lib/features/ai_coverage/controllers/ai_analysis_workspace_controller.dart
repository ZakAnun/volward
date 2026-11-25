import 'package:flutter/foundation.dart';

import '../models/ai_analysis_workspace_display_state.dart';

export '../models/ai_analysis_workspace_display_state.dart';

/// Owns workspace operation generations, owner binding and delete busy state.
class AiAnalysisWorkspaceController extends ChangeNotifier {
  AiAnalysisWorkspaceController({
    String? ownerId,
    this.onBusyChanged,
    AiWorkspaceDisplayState initialDisplayState =
        AiWorkspaceDisplayState.loading,
  }) : activeOwnerId = ownerId,
       _displayState = initialDisplayState;

  @visibleForTesting
  factory AiAnalysisWorkspaceController.forTest({
    String? ownerId,
    ValueChanged<bool>? onBusyChanged,
  }) {
    return AiAnalysisWorkspaceController(
      ownerId: ownerId,
      onBusyChanged: onBusyChanged,
    );
  }

  String? activeOwnerId;
  AiWorkspaceDisplayState _displayState;
  bool _busy = false;
  int _operationGeneration = 0;
  int _busyGeneration = 0;
  final ValueChanged<bool>? onBusyChanged;

  AiWorkspaceDisplayState get displayState => _displayState;
  bool get busy => _busy;
  int get operationGeneration => _operationGeneration;

  int beginOperation() => ++_operationGeneration;

  bool isCurrent(int generation) =>
      generation == _operationGeneration && !_disposed;

  void updateDisplayState(AiWorkspaceDisplayState state) {
    if (_displayState == state) return;
    _displayState = state;
    notifyListeners();
  }

  void syncDisplayState(AiWorkspaceDisplayState state) {
    updateDisplayState(state);
  }

  void rebindOwner(String? ownerId) {
    activeOwnerId = ownerId;
    _operationGeneration++;
    _displayState = AiWorkspaceDisplayState.loading;
    notifyListeners();
  }

  Future<T?> runOwnerOperation<T>(
    Future<T> Function() operation, {
    void Function(T value)? onCurrentResult,
  }) async {
    final generation = beginOperation();
    final owner = activeOwnerId;
    final value = await operation();
    if (isCurrent(generation) && activeOwnerId == owner) {
      onCurrentResult?.call(value);
    }
    return value;
  }

  Future<T?> runBusy<T>(Future<T> Function() operation) async {
    if (_busy) return null;
    final busyGeneration = ++_busyGeneration;
    _setBusy(true);
    try {
      return await operation();
    } finally {
      if (_busyGeneration == busyGeneration) _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    if (_disposed) return;
    onBusyChanged?.call(value);
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _busy = false;
    _disposed = true;
    super.dispose();
  }
}
