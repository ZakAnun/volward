import 'package:flutter/foundation.dart';

enum ScanRunMode { auto, resume, rescan }

/// Thrown when the user cancels an in-progress scan.
class ScanCancelledException implements Exception {
  ScanCancelledException([this.message = 'Scan cancelled']);

  final String message;

  @override
  String toString() => message;
}

@immutable
class ScanProgressViewState {
  const ScanProgressViewState({this.phase, this.fraction});

  final String? phase;
  final double? fraction;

  @override
  bool operator ==(Object other) {
    return other is ScanProgressViewState &&
        other.phase == phase &&
        other.fraction == fraction;
  }

  @override
  int get hashCode => Object.hash(phase, fraction);
}

/// Settings may observe scan availability and change incremental mode.
abstract interface class ScanPreferences implements Listenable {
  bool get scanning;
  bool get canUseIncrementalScan;
  bool get incrementalScan;
  void setIncrementalScan(bool incremental);
}

/// Scan lifecycle contract used by pages and application composition.
abstract interface class ScanLifecycle implements ScanPreferences {
  bool get hasSnapshotFileApi;
  bool get hasAuthoritativeSnapshotForCurrentRoot;
  int get rootSwitchGeneration;

  Future<void> loadSessionStateIfNeeded();
  Future<String> resolveStartupRoot();
  Future<void> validateScanRoot(String path);
  void setScanRoots(List<String> roots);
  Future<void> previewTarget({int? expectedGeneration});
  Future<void> restoreCachedSnapshotIfNeeded();
  Future<void> switchScanRoot(
    String? path, {
    bool validateBeforeSwitch = false,
  });
  Future<String> runScan({ScanRunMode mode = ScanRunMode.auto});
  void cancelScan();
}
