import 'package:flutter/foundation.dart';

import '../../scan/scan_lifecycle.dart';
import '../../scan/scan_session_types.dart';

/// Owns values that are derived from scan state for page presentation.
class ScanPresentationController extends ChangeNotifier {
  ScanPresentationController({this.onCancelScan, this.onPauseScan});

  @visibleForTesting
  factory ScanPresentationController.forTest() => ScanPresentationController();

  final ValueNotifier<ScanProgressViewState> progressNotifier = ValueNotifier(
    const ScanProgressViewState(),
  );
  final ValueNotifier<double?> scannedFractionNotifier = ValueNotifier(null);
  final ValueNotifier<String?> elapsedLabelNotifier = ValueNotifier(null);

  String? scanStatus;
  bool scanning = false;
  bool restoringSnapshot = false;
  bool targetPreviewLoading = false;
  bool deleting = false;
  bool postDeleteRefreshPending = false;
  int refreshingDirectoryCount = 0;
  Map<String, dynamic>? progressDetail;
  bool previousScanning = false;
  bool lastDeleting = false;
  int lastRefreshingDirectoryCount = 0;
  bool lastTargetPreviewLoading = false;
  bool lastPostDeleteRefreshPending = false;
  bool lastHasResults = false;
  String? lastRefreshedSnapshotId;
  int lastRefreshedCatalogVersion = -1;
  VoidCallback? _detachSource;
  VoidCallback? onCancelScan;
  Future<bool> Function()? onPauseScan;

  ValueListenable<ScanProgressViewState> get progress => progressNotifier;
  ValueListenable<double?> get scannedFraction => scannedFractionNotifier;
  ValueListenable<String?> get elapsedLabel => elapsedLabelNotifier;

  ScanProgressViewState get progressState => progressNotifier.value;

  void bindActions({
    required VoidCallback onCancelScan,
    required Future<bool> Function() onPauseScan,
  }) {
    this.onCancelScan = onCancelScan;
    this.onPauseScan = onPauseScan;
  }

  void cancelScan() => onCancelScan?.call();

  Future<bool> pauseScan() async => await onPauseScan?.call() ?? false;

  void markScanning(bool scanning) {
    this.scanning = scanning;
    previousScanning = scanning;
    notifyListeners();
  }

  void markResults(bool hasResults) {
    lastHasResults = hasResults;
    notifyListeners();
  }

  bool update({
    required bool scanning,
    required bool restoringSnapshot,
    required bool targetPreviewLoading,
    required bool deleting,
    required bool postDeleteRefreshPending,
    required int refreshingDirectoryCount,
    required ScanProgressViewState progress,
    required double? scannedFraction,
    required String? elapsedLabel,
  }) {
    final changed =
        this.scanning != scanning ||
        this.restoringSnapshot != restoringSnapshot ||
        this.targetPreviewLoading != targetPreviewLoading ||
        this.deleting != deleting ||
        this.postDeleteRefreshPending != postDeleteRefreshPending ||
        this.refreshingDirectoryCount != refreshingDirectoryCount ||
        progressNotifier.value != progress ||
        scannedFractionNotifier.value != scannedFraction ||
        elapsedLabelNotifier.value != elapsedLabel;
    this.scanning = scanning;
    this.restoringSnapshot = restoringSnapshot;
    this.targetPreviewLoading = targetPreviewLoading;
    this.deleting = deleting;
    this.postDeleteRefreshPending = postDeleteRefreshPending;
    this.refreshingDirectoryCount = refreshingDirectoryCount;
    if (progressNotifier.value != progress) progressNotifier.value = progress;
    if (scannedFractionNotifier.value != scannedFraction) {
      scannedFractionNotifier.value = scannedFraction;
    }
    if (elapsedLabelNotifier.value != elapsedLabel) {
      elapsedLabelNotifier.value = elapsedLabel;
    }
    if (changed) notifyListeners();
    return changed;
  }

  void updateFromLifecycle(
    ScanLifecycle lifecycle, {
    required bool restoringSnapshot,
    required bool targetPreviewLoading,
    required bool deleting,
    required bool postDeleteRefreshPending,
    required int refreshingDirectoryCount,
    required Map<String, dynamic>? progressDetail,
  }) {
    final progressChanged = this.progressDetail != progressDetail;
    this.progressDetail = progressDetail;
    final changed = update(
      scanning: lifecycle.scanning,
      restoringSnapshot: restoringSnapshot,
      targetPreviewLoading: targetPreviewLoading,
      deleting: deleting,
      postDeleteRefreshPending: postDeleteRefreshPending,
      refreshingDirectoryCount: refreshingDirectoryCount,
      progress: progressNotifier.value,
      scannedFraction: scannedFractionNotifier.value,
      elapsedLabel: elapsedLabelNotifier.value,
    );
    if (progressChanged && !changed) notifyListeners();
  }

  bool get busyForActions =>
      scanning || deleting || refreshingDirectoryCount > 0;

  void bindSource({
    required ValueListenable<ScanProgressViewState> progress,
    required ValueListenable<double?> scannedFraction,
    required ValueListenable<String?> elapsedLabel,
  }) {
    _detachSource?.call();
    void sync() {
      if (progressNotifier.value != progress.value) {
        progressNotifier.value = progress.value;
      }
      if (scannedFractionNotifier.value != scannedFraction.value) {
        scannedFractionNotifier.value = scannedFraction.value;
      }
      if (elapsedLabelNotifier.value != elapsedLabel.value) {
        elapsedLabelNotifier.value = elapsedLabel.value;
      }
    }

    sync();
    progress.addListener(sync);
    scannedFraction.addListener(sync);
    elapsedLabel.addListener(sync);
    _detachSource = () {
      progress.removeListener(sync);
      scannedFraction.removeListener(sync);
      elapsedLabel.removeListener(sync);
    };
  }

  void unbindSource() {
    _detachSource?.call();
    _detachSource = null;
  }

  @override
  void dispose() {
    unbindSource();
    progressNotifier.dispose();
    scannedFractionNotifier.dispose();
    elapsedLabelNotifier.dispose();
    super.dispose();
  }
}
