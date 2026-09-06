import 'dart:async';

import 'package:flutter/widgets.dart';

/// Design §5.3: minimize/hide must not pause; only process detach quits.
bool shouldMarkAppQuitOnLifecycle(AppLifecycleState state) =>
    state == AppLifecycleState.detached;

/// Waits until [isReady] returns true, optionally listening for changes.
Future<bool> waitUntilReady({
  required bool Function() isReady,
  void Function(VoidCallback listener)? addListener,
  void Function(VoidCallback listener)? removeListener,
  Duration pollInterval = const Duration(milliseconds: 50),
  Duration timeout = const Duration(seconds: 30),
}) async {
  if (isReady()) return true;
  if (addListener != null && removeListener != null) {
    final completer = Completer<bool>();
    void listener() {
      if (isReady() && !completer.isCompleted) {
        completer.complete(true);
      }
    }

    addListener(listener);
    try {
      final result = await completer.future.timeout(
        timeout,
        onTimeout: () => isReady(),
      );
      return result;
    } finally {
      removeListener(listener);
    }
  }

  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(pollInterval);
    if (isReady()) return true;
  }
  return isReady();
}
