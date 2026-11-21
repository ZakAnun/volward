import 'dart:async';

import 'package:flutter/material.dart';

import '../../../scan_snapshot_state.dart';
import '../../../storage_overview.dart';
import '../../../widgets/top_toast.dart';

/// Read-only session state consumed by the directory detail controllers.
///
/// The page State implements no query or action behavior itself. It hands the
/// controllers this narrow snapshot of the session, so the controllers can be
/// exercised with a fake session in tests.
abstract interface class DirectorySnapshotSource {
  List<String> get scanRoots;
  ScanSnapshotState? get lastSnapshot;
  bool get scanning;
  bool get deleting;
  bool get targetPreviewLoading;
  bool get restoringSnapshot;
  bool get postDeleteRefreshPending;
  bool get hasAiSessionApi;
  bool get hasSnapshotFileApi;
  bool get ready;
  List<String> get recentCustomRoots;
  void rememberCustomRoot(String path);
}

/// Mutable page state owned by the page State and driven by the actions
/// controller. The State implements this contract; the controller never sees
/// a `State` object.
abstract interface class DirectoryDetailsActionState {
  bool get isBrowsing;
  set isBrowsing(bool value);

  bool get hasValidRoot;
  set hasValidRoot(bool value);

  bool get targetPreparationPending;
  set targetPreparationPending(bool value);

  bool get scanStartPending;
  set scanStartPending(bool value);

  String? get scanStatus;
  set scanStatus(String? value);

  String? get homeTargetPath;
  set homeTargetPath(String? value);

  List<StorageLocationInfo> get recentCustomLocations;
  set recentCustomLocations(List<StorageLocationInfo> value);

  StorageOverviewData get storageOverview;
  set storageOverview(StorageOverviewData value);

  Completer<bool> get startupRootGate;
  set startupRootGate(Completer<bool> value);

  int get scanStartGeneration;
  set scanStartGeneration(int value);

  int get sessionGeneration;

  int get overviewLoadGeneration;
  set overviewLoadGeneration(int value);
}

/// Confirmation dialogs are injected so action tests never need a BuildContext.
typedef DirectoryConfirmDialog = Future<bool?> Function(AlertDialog dialog);

/// Toast presentation is injected for the same reason.
typedef DirectoryToastPresenter = void Function(String message, ToastType type);
