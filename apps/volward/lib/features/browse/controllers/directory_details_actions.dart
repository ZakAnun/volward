import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:volward/features/browse/controllers/directory_browse_controller.dart';
import 'package:volward/features/browse/controllers/directory_details_query.dart';
import 'package:volward/features/browse/controllers/directory_details_ports.dart';
import 'package:volward/features/browse/directory_browse_session.dart';
import 'package:volward/features/browse/widgets/scan_filter_bar.dart';
import 'package:volward/features/deletion/deletion_actions.dart';
import 'package:volward/features/scan/scan_lifecycle.dart';
import 'package:volward/features/scan/scan_session_types.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/scan_snapshot_state.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/storage_home_summary.dart';
import 'package:volward/storage_overview.dart';
import 'package:volward/widgets/apple_widgets.dart';
import 'package:volward/widgets/top_toast.dart';
import 'directory_details_helpers.dart';

/// Executes the directory page's browse, scan and delete actions over narrow
/// ports. It owns no Flutter State and renders no UI — dialogs and toasts are
/// injected — so every action has direct unit coverage.
class DirectoryDetailsActionsController {
  DirectoryDetailsActionsController({
    required this.session,
    required this.scan,
    required this.browse,
    required this.deletion,
    required this.state,
    required this.browseController,
    required this.query,
    required this.isMounted,
    required this.applySetState,
    required this.l10n,
    required this.showConfirm,
    required this.showToast,
    required this.attachedSession,
    required this.isStartupPendingFor,
    required this.loadOverview,
    this.directoryPicker,
  });

  DirectorySnapshotSource session;
  ScanLifecycle scan;
  DirectoryBrowseSession browse;
  DeletionActions deletion;
  final DirectoryDetailsActionState state;
  final DirectoryBrowseController browseController;
  final DirectoryQueryController query;
  final bool Function() isMounted;
  final void Function(VoidCallback fn) applySetState;
  final AppLocalizations Function() l10n;
  final DirectoryConfirmDialog showConfirm;
  final DirectoryToastPresenter showToast;
  final Object? Function() attachedSession;
  final bool Function(Object? session) isStartupPendingFor;
  final void Function(String? selectedPath) loadOverview;
  final Future<String?> Function({required String confirmButtonText})?
  directoryPicker;

  /// Re-points the controller at a replacement session after the page widget
  /// is rebuilt with a different one.
  void rebind({
    required DirectorySnapshotSource session,
    required ScanLifecycle scan,
    required DirectoryBrowseSession browse,
    required DeletionActions deletion,
  }) {
    this.session = session;
    this.scan = scan;
    this.browse = browse;
    this.deletion = deletion;
  }

  bool isCurrentSession(Object? session, int generation) {
    return isMounted() &&
        identical(attachedSession(), session) &&
        generation == state.sessionGeneration;
  }

  Future<String?> chooseFolderPath() {
    final confirm = l10n().folderPickerConfirm;
    final picker = directoryPicker;
    return picker != null
        ? picker(confirmButtonText: confirm)
        : getDirectoryPath(confirmButtonText: confirm);
  }

  Future<void> pickFolder() async {
    final path = await chooseFolderPath();
    if (path == null) return;
    if (!await switchToValidatedRoot(path)) return;
    rememberCustomTarget(ScanTreeBuilder.normalizeRoot(path));
    synchronizeHomeTarget(additionalState: () => state.isBrowsing = true);
  }

  Future<void> pickHomeFolder() async {
    final path = await chooseFolderPath();
    if (path == null) return;
    await prepareHomeTarget(path);
  }

  bool isPresetLocationPath(String path) {
    final normalized = ScanTreeBuilder.normalizeRoot(path);
    for (final location in state.storageOverview.locations) {
      if (location.kind == StorageLocationKind.volume) continue;
      if (ScanTreeBuilder.normalizeRoot(location.path) == normalized) {
        return true;
      }
    }
    return false;
  }

  StorageLocationInfo customLocationFor(String path) {
    return StorageLocationInfo(
      id: 'custom:$path',
      name: rootDisplayNameFor(path),
      path: path,
      kind: StorageLocationKind.custom,
      volumeId: state.storageOverview.volumeForPath(path)?.id ?? '',
    );
  }

  void rememberCustomTarget(String path, {bool persist = true}) {
    final normalized = ScanTreeBuilder.normalizeRoot(path);
    if (normalized.isEmpty || state.storageOverview.locations.isEmpty) return;
    if (isPresetLocationPath(normalized)) return;
    final next = customLocationFor(normalized);
    final unchanged =
        state.recentCustomLocations.isNotEmpty &&
        ScanTreeBuilder.normalizeRoot(state.recentCustomLocations.first.path) ==
            normalized;
    state.recentCustomLocations = [
      next,
      for (final location in state.recentCustomLocations)
        if (ScanTreeBuilder.normalizeRoot(location.path) != normalized)
          location,
    ].take(5).toList(growable: false);
    if (persist && !unchanged) {
      session.rememberCustomRoot(normalized);
    }
  }

  void syncRecentCustomLocations() {
    state.recentCustomLocations = [
      for (final saved in session.recentCustomRoots)
        if (saved.isNotEmpty && !isPresetLocationPath(saved))
          customLocationFor(saved),
    ];
    final current = state.homeTargetPath;
    if (current != null && current.isNotEmpty) {
      rememberCustomTarget(current, persist: false);
    }
  }

  Future<void> prepareHomeTarget(String path) async {
    if (state.targetPreparationPending) return;
    final activeSession = attachedSession();
    final activeGeneration = state.sessionGeneration;
    state.scanStartGeneration++;
    applySetState(() => state.targetPreparationPending = true);
    try {
      final normalized = ScanTreeBuilder.normalizeRoot(path);
      final current = ScanTreeBuilder.normalizeRoot(query.scanRootPath());
      if (normalized != current) {
        if (!await switchToValidatedRoot(normalized)) {
          return;
        }
      }
      if (!isCurrentSession(activeSession, activeGeneration)) return;
      rememberCustomTarget(normalized);
      synchronizeHomeTarget();
    } finally {
      if (isCurrentSession(activeSession, activeGeneration)) {
        applySetState(() => state.targetPreparationPending = false);
      }
    }
  }

  Future<bool> switchToValidatedRoot(String path) async {
    try {
      await scan.switchScanRoot(path, validateBeforeSwitch: true);
      return isMounted() &&
          ScanTreeBuilder.normalizeRoot(query.scanRootPath()) ==
              ScanTreeBuilder.normalizeRoot(path);
    } catch (error) {
      if (!isMounted()) return false;
      showToast(l10n().scanStatusFailed(error.toString()), ToastType.error);
      return false;
    }
  }

  void synchronizeHomeTarget({VoidCallback? additionalState}) {
    final target = ScanTreeBuilder.normalizeRoot(query.scanRootPath());
    final targetChanged = target != state.homeTargetPath;
    if (targetChanged) state.overviewLoadGeneration++;
    applySetState(() {
      if (targetChanged) {
        state.storageOverview = const StorageOverviewData.loading();
      }
      state.homeTargetPath = target;
      state.hasValidRoot = target.isNotEmpty;
      additionalState?.call();
    });
    loadOverview(target);
  }

  Future<void> switchBrowseToHomeRoot() async {
    applySetState(() => state.scanStatus = null);
    await scan.switchScanRoot(null);
    if (!isMounted()) return;
    synchronizeHomeTarget();
  }

  void showHome() {
    if (!state.isBrowsing) return;
    applySetState(() => state.isBrowsing = false);
  }

  Future<void> waitForStartupRootResolution() async {
    while (isMounted()) {
      final gate = state.startupRootGate;
      final resolved = await gate.future;
      if (!isMounted()) return;
      if (resolved && identical(gate, state.startupRootGate)) return;
    }
  }

  Future<void> onHomeBrowse({String? focusPath}) async {
    if (!state.startupRootGate.isCompleted) {
      await waitForStartupRootResolution();
      if (!isMounted()) return;
    }
    if (!state.hasValidRoot) {
      await pickFolder();
      return;
    }
    applySetState(() {
      state.isBrowsing = true;
      if (focusPath != null) focusBrowseOnPath(focusPath);
    });
  }

  /// Opens the column chain down to [path]'s directory. A file focuses its
  /// parent, so the file's own row is on screen.
  ///
  /// Catalog-backed snapshots often leave [ScanTreeNode.children] empty, so
  /// the chain is built from [DirectoryBrowseSession.queryDirectoryChildrenFromCatalog]
  /// when the in-memory tree has no children.
  void focusBrowseOnPath(String path) {
    final root = query.resolveResultTree();
    if (root == null) return;
    final node = query.findNodeByPath(root, path);
    final String directory;
    if (node != null) {
      directory = node.isDirectory ? node.path : parentFsPath(node.path);
    } else {
      final normalized = normalizeFsPath(path);
      final rootPath = normalizeFsPath(root.path);
      if (normalized == rootPath) {
        query.resetColumnNav();
        return;
      }
      if (!isUnderFsRoot(normalized, rootPath)) return;
      directory = normalized;
    }
    query.setColumnChain(chainToPath(root, directory));
  }

  List<ScanTreeNode> chainToPath(ScanTreeNode root, String targetPath) {
    final chain = <ScanTreeNode>[];
    var current = root;
    while (current.path != targetPath) {
      ScanTreeNode? next;
      for (final child in focusChildrenOf(current)) {
        if (!child.isDirectory) continue;
        if (targetPath == child.path ||
            targetPath.startsWith('${child.path}/')) {
          next = child;
          break;
        }
      }
      if (next == null) break;
      chain.add(next);
      current = next;
    }
    return chain;
  }

  List<ScanTreeNode> focusChildrenOf(ScanTreeNode node) {
    if (node.children.isNotEmpty) return node.children;
    final catalog = browse.queryDirectoryChildrenFromCatalog(node.path);
    if (catalog == null || catalog.isEmpty) return const [];
    return [for (final record in catalog) record.toScanTreeNode()];
  }

  void openHomeCategory(String name) {
    final known = ScanFilterBar.categoryOptions.contains(name);
    applySetState(() {
      browseController.categoryFilter = known ? name : null;
      query.resetColumnNav();
      state.isBrowsing = true;
    });
  }

  StorageHomeSummary homeSummary(ScanProgressViewState progress) {
    final target = state.homeTargetPath ?? query.scanRootPath();
    return StorageHomeSummary.fromInputs(
      overview: state.storageOverview,
      targetPath: target,
      matchingSnapshot: query.snapshotMatchesTarget(target)
          ? session.lastSnapshot
          : null,
      largestItemCandidates: query.largestItemsFor(target),
      scanning: session.scanning || session.restoringSnapshot,
      restoringSnapshot: session.restoringSnapshot && !session.scanning,
      scanProgress: session.scanning ? progress.fraction : null,
      scanPhase: session.scanning ? progress.phase : null,
      recentCustomLocations: state.recentCustomLocations,
    );
  }

  ScanSnapshotState? homeAiSnapshot() {
    final target = state.homeTargetPath ?? query.scanRootPath();
    final snapshot = query.snapshotMatchesTarget(target)
        ? session.lastSnapshot
        : null;
    final snapshotId = snapshot?.snapshotId ?? '';
    if (!session.hasAiSessionApi ||
        session.scanning ||
        session.postDeleteRefreshPending ||
        browse.refreshingDirectoryPaths.isNotEmpty ||
        snapshot == null ||
        snapshot.stats['scan_state']?.toString() != 'Done' ||
        snapshotId.isEmpty ||
        snapshotId.startsWith('preview-')) {
      return null;
    }
    return snapshot;
  }

  void handleAiDeleteCompleted() {
    if (!isMounted()) return;
    applySetState(() {});
  }

  bool get canStartScan {
    return state.startupRootGate.isCompleted &&
        !isStartupPendingFor(attachedSession()) &&
        state.hasValidRoot &&
        !state.targetPreparationPending &&
        !session.targetPreviewLoading &&
        session.ready &&
        !session.scanning &&
        !state.scanStartPending &&
        session.hasSnapshotFileApi;
  }

  VoidCallback? get scanStartAction {
    if (!canStartScan) return null;
    final activeSession = attachedSession();
    final generation = state.scanStartGeneration;
    return () => unawaited(startScan(activeSession, generation));
  }

  bool isCurrentScanStart(Object? session, int generation) {
    return isMounted() &&
        identical(attachedSession(), session) &&
        !isStartupPendingFor(session) &&
        generation == state.scanStartGeneration;
  }

  Future<void> startScan(
    Object? expectedSession,
    int expectedGeneration,
  ) async {
    if (!identical(attachedSession(), expectedSession) ||
        expectedGeneration != state.scanStartGeneration ||
        !state.startupRootGate.isCompleted ||
        isStartupPendingFor(expectedSession) ||
        !state.hasValidRoot ||
        state.targetPreparationPending ||
        session.targetPreviewLoading ||
        !canStartScan) {
      return;
    }
    final activeSession = expectedSession;
    final generation = ++state.scanStartGeneration;
    final incremental = scan.incrementalScan;
    applySetState(() => state.scanStartPending = true);
    String? nextStatus;
    try {
      final id = await scan.runScan(mode: ScanRunMode.rescan);
      if (!isMounted() || !isCurrentScanStart(activeSession, generation)) {
        return;
      }
      final snapshot = session.lastSnapshot;
      final count = snapshot?.filesInSnapshot ?? 0;
      final strings = l10n();
      final label = incremental
          ? strings.scanStatusIncremental
          : strings.scanStatusFull;
      nextStatus = '${strings.scanStatusFiles(label, count)} · $id';
    } catch (e) {
      if (!isMounted() || !isCurrentScanStart(activeSession, generation)) {
        return;
      }
      final strings = l10n();
      nextStatus = e is ScanCancelledException
          ? strings.scanStatusCancelled
          : strings.scanStatusFailed(e.toString());
    } finally {
      if (isCurrentScanStart(activeSession, generation)) {
        applySetState(() {
          state.scanStartPending = false;
          if (nextStatus != null) state.scanStatus = nextStatus;
        });
      }
    }
  }

  Future<void> confirmDelete() async {
    final targetStrings = query.deleteTargetStrings();
    if (targetStrings.isEmpty) return;
    final focus = query.focusedDeleteNode();
    final targetPathById = <String, String>{};
    if (browseController.selected.isNotEmpty) {
      for (final target in targetStrings) {
        final path = browseController.selectedPaths[target];
        if (path != null && path.isNotEmpty) {
          targetPathById[target] = path;
        }
      }
    } else if (targetStrings.length == 1 && focus != null) {
      targetPathById[targetStrings.single] = focus.path;
    }
    final refreshPath = refreshPathForDeleteTargets(
      fallbackPath: browse.currentDirectoryPath ?? query.scanRootPath(),
      targetPaths: targetPathById.values,
    );
    final shouldRetreatFocus = targetStrings.length == 1 && focus != null;
    final preview = await deletion.deleteEntries(targetStrings, dryRun: true);
    if (!isMounted()) return;
    final strings = l10n();
    final count = (preview['deleted_count'] as num?)?.toInt() ?? 0;
    final freed = (preview['freed_bytes'] as num?)?.toInt() ?? 0;
    final ok = await showConfirm(
      AlertDialog(
        title: Text(strings.deleteConfirmTitle),
        content: Text(
          strings.deleteConfirmMessage(count, formatDirectoryBytes(freed)),
        ),
        actions: [
          Builder(
            builder: (context) => AppleButton(
              label: strings.scanActionCancel,
              variant: AppleButtonVariant.pearl,
              onPressed: () => Navigator.pop(context, false),
            ),
          ),
          Builder(
            builder: (context) => AppleButton(
              label: strings.deleteActionDelete,
              onPressed: () => Navigator.pop(context, true),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !isMounted()) return;
    try {
      final report = await deletion.deleteEntries(
        targetStrings,
        rescanAfterDelete: true,
        refreshPath: refreshPath,
        targetPathById: targetPathById,
      );
      if (!isMounted()) return;
      applySetState(() {
        browseController.clearSelection();
        browseController.cachedSelectedBytesKey = null;
      });
      if (shouldRetreatFocus && browseController.columnChain.isNotEmpty) {
        // Drop the stale leaf so a second delete cannot target the removed
        // node.
        query.setColumnChain(
          browseController.columnChain
              .take(browseController.columnChain.length - 1)
              .toList(),
        );
      }
      final freedAfter = (report['freed_bytes'] as num?)?.toInt() ?? 0;
      final failed = report['failed_paths'];
      final failedCount = failed is List ? failed.length : 0;
      showToast(
        failedCount > 0
            ? strings.deleteSuccessWithFailures(
                failedCount,
                formatDirectoryBytes(freedAfter),
              )
            : strings.deleteSuccess(formatDirectoryBytes(freedAfter)),
        failedCount > 0 ? ToastType.error : ToastType.success,
      );
    } catch (e) {
      if (!isMounted()) return;
      showToast(strings.deleteFailed(e.toString()), ToastType.error);
    }
  }

  Future<void> confirmEmptyTrash() async {
    final strings = l10n();
    final ok = await showConfirm(
      AlertDialog(
        title: Text(strings.trashEmptyConfirmTitle),
        content: Text(strings.trashEmptyConfirmMessage),
        actions: [
          Builder(
            builder: (context) => AppleButton(
              label: strings.scanActionCancel,
              variant: AppleButtonVariant.pearl,
              onPressed: () => Navigator.pop(context, false),
            ),
          ),
          Builder(
            builder: (context) => AppleButton(
              label: strings.trashActionEmpty,
              onPressed: () => Navigator.pop(context, true),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !isMounted()) return;
    try {
      await deletion.emptyTrash(rescanAfterEmpty: true);
      if (!isMounted()) return;
      showToast(strings.trashEmptySuccess, ToastType.success);
    } catch (e) {
      if (!isMounted()) return;
      showToast(strings.trashEmptyFailed(e.toString()), ToastType.error);
    }
  }
}
