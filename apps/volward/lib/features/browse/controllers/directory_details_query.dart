import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:volward/features/browse/controllers/directory_browse_controller.dart';
import 'package:volward/features/browse/controllers/scan_presentation_controller.dart';
import 'package:volward/features/browse/directory_browse_session.dart';
import 'package:volward/features/browse/scan_sort_mode.dart';
import 'package:volward/features/browse/snapshot_catalog.dart';
import 'package:volward/features/browse/widgets/scan_column_view.dart';
import 'package:volward/l10n/generated/app_localizations.dart';
import 'package:volward/scan_entry_record.dart';
import 'package:volward/scan_tree.dart';
import 'package:volward/scan_tree_navigation.dart';
import 'package:volward/snapshot_query.dart';
import 'directory_details_helpers.dart';
import 'directory_details_ports.dart';

const int _asyncVisibleChildrenThreshold = 512;
const int _maxAsyncSortedChildren = 2048;

/// Resolves the directory page's tree, visible children, selection and delete
/// projections. It is a plain controller over narrow ports, not an extension
/// over a page State, so every query behavior has direct unit coverage.
class DirectoryQueryController {
  DirectoryQueryController({
    required this.session,
    required this.browse,
    required this.browseController,
    required this.scanPresentationController,
    required this.isMounted,
    required this.applySetState,
    required this.l10n,
  });

  DirectorySnapshotSource session;
  DirectoryBrowseSession browse;
  final DirectoryBrowseController browseController;
  final ScanPresentationController scanPresentationController;
  final bool Function() isMounted;
  final void Function(VoidCallback fn) applySetState;
  final AppLocalizations Function() l10n;

  /// Re-points the controller at a replacement session after the page widget
  /// is rebuilt with a different one.
  void rebind({
    required DirectorySnapshotSource session,
    required DirectoryBrowseSession browse,
  }) {
    this.session = session;
    this.browse = browse;
  }

  String scanRootPath() {
    if (session.scanRoots.isNotEmpty) {
      return ScanTreeBuilder.normalizeRoot(session.scanRoots.first);
    }
    return defaultScanRootPath(
      environment: Platform.environment,
      isWindows: () => Platform.isWindows,
    );
  }

  String scanTargetLabel(AppLocalizations strings) {
    return session.scanRoots.isEmpty
        ? strings.scanTargetHomeDefault
        : session.scanRoots.join(', ');
  }

  ScanTreeNode? resolveResultTree() {
    final snapId = session.lastSnapshot?.snapshotId ?? '';
    if (browseController.cachedResolvedTree != null &&
        browseController.cachedResolvedTreeKey == snapId) {
      return browseController.cachedResolvedTree;
    }

    final snap = session.lastSnapshot;
    if (snap == null) return null;

    ScanTreeNode? tree = snap.tree;
    final rootPath = (tree != null && tree.path.isNotEmpty)
        ? ScanTreeBuilder.normalizeRoot(tree.path)
        : scanRootPath();

    if ((tree == null || tree.children.isEmpty) && snap.hasFlatEntries) {
      final entries = snap.materializeEntries();
      tree = ScanTreeBuilder.build(entries: entries, rootPath: rootPath);
    }

    browseController.cachedResolvedTree = tree;
    browseController.cachedResolvedTreeKey = snapId;
    return tree;
  }

  bool snapshotMatchesCurrentRoot() {
    return snapshotMatchesTarget(scanRootPath());
  }

  bool get hasResults {
    final snapshotMatchesCurrentRoot = this.snapshotMatchesCurrentRoot();
    final loadingTarget =
        session.targetPreviewLoading ||
        (session.scanning && !snapshotMatchesCurrentRoot);
    return !loadingTarget &&
        session.lastSnapshot != null &&
        snapshotMatchesCurrentRoot;
  }

  bool snapshotMatchesTarget(String targetPath) {
    final tree = session.lastSnapshot?.tree;
    if (tree == null || tree.path.isEmpty) return false;
    return ScanTreeBuilder.normalizeRoot(tree.path) ==
        ScanTreeBuilder.normalizeRoot(targetPath);
  }

  /// Direct children of the scanned target, for the home dashboard's middle
  /// block. `SnapshotCatalog.queryNode` is a synchronous in-memory FFI read,
  /// but the home summary runs inside `build()` and rebuilds on every scan
  /// progress tick — so memoize on (snapshotId, targetPath).
  List<ScanTreeNode> largestItemsFor(String targetPath) {
    final snapshot = session.lastSnapshot;
    final tree = snapshot?.tree;
    if (snapshot == null ||
        tree == null ||
        !snapshotMatchesTarget(targetPath)) {
      browseController.largestItemsCacheKey = null;
      browseController.largestItemCandidates = const [];
      return const [];
    }
    final cacheKey = '${snapshot.snapshotId}|$targetPath';
    if (cacheKey == browseController.largestItemsCacheKey) {
      return browseController.largestItemCandidates;
    }
    final result = SnapshotCatalog.queryNode(
      reader: browse,
      key: SnapshotQueryKey(
        snapshotId: snapshot.snapshotId,
        version: browse.catalogVersion,
        path: tree.path,
        categoryFilter: null,
        deletableOnly: false,
        sortMode: ScanSortMode.sizeDesc,
      ),
      node: tree,
      includeEntryRecords: false,
    );
    browseController.largestItemsCacheKey = cacheKey;
    browseController.largestItemCandidates = result.directNodes;
    return browseController.largestItemCandidates;
  }

  void invalidateSnapshotCaches() {
    browseController.invalidateSnapshotCaches();
  }

  void invalidateSnapshotCachesForSessionUpdate() {
    browseController.invalidateSnapshotCachesForSessionUpdate(
      browse.consumeInvalidatedPrefixes(),
    );
  }

  void resetColumnNav() {
    browseController.resetColumnNavigation();
  }

  void setColumnChain(List<ScanTreeNode> next) {
    browseController.columnChain
      ..clear()
      ..addAll(next);
    prunePendingVisibleQueries();
    browseController.columnNavTick.value++;
  }

  void prunePendingVisibleQueries() {
    final visiblePaths = <String>{};
    final root =
        browseController.cachedResolvedTree ?? session.lastSnapshot?.tree;
    if (root != null) visiblePaths.add(root.path);
    for (final node in browseController.columnChain) {
      visiblePaths.add(node.path);
    }
    browseController.pendingVisibleChildrenQueries.removeWhere(
      (key) => !visiblePaths.contains(key.path),
    );
  }

  ScanTreeNode? findNodeByPath(ScanTreeNode? root, String targetPath) {
    if (root == null) return null;
    if (root.path == targetPath) return root;
    if (!root.isDirectory) return null;
    for (final child in root.children) {
      final found = findNodeByPath(child, targetPath);
      if (found != null) return found;
    }
    return null;
  }

  void onColumnSelect(ScanColumnTap tap) {
    if (session.deleting || session.scanning) return;
    final columnIndex = tap.columnIndex;
    final node = tap.node;
    final currentTree = resolveResultTree();
    final actualNode =
        findNodeByPath(currentTree, node.path) ?? node.toScanTreeNode();

    if (tap.commandPressed || tap.shiftPressed) {
      if (actualNode.category == 'System') return;
      if (tap.shiftPressed &&
          browseController.selectionAnchorPath != null &&
          browseController.selectionAnchorColumnIndex == columnIndex) {
        final range = selectColumnRange(
          tap.columnItems,
          anchorPath: browseController.selectionAnchorPath!,
          targetPath: node.path,
        );
        if (range.isNotEmpty) {
          applySetState(() {
            for (final record in range) {
              final rangeNode =
                  findNodeByPath(currentTree, record.path) ??
                  record.toScanTreeNode();
              addNodeSelection(rangeNode);
            }
            browseController.cachedSelectedBytesKey = null;
          });
        }
      } else if (tap.commandPressed) {
        applySetState(() {
          if (browseController.selected.isEmpty &&
              browseController.selectionAnchorPath != null &&
              browseController.selectionAnchorColumnIndex == columnIndex &&
              browseController.selectionAnchorPath != node.path) {
            SnapshotNodeRecord? anchorRecord;
            for (final record in tap.columnItems) {
              if (record.path == browseController.selectionAnchorPath) {
                anchorRecord = record;
                break;
              }
            }
            if (anchorRecord != null) {
              final anchorNode =
                  findNodeByPath(currentTree, anchorRecord.path) ??
                  anchorRecord.toScanTreeNode();
              addNodeSelection(anchorNode);
            }
          }
          toggleNodeSelection(actualNode);
          browseController.cachedSelectedBytesKey = null;
        });
      }
      if (tap.commandPressed) {
        browseController.selectionAnchorPath = node.path;
        browseController.selectionAnchorColumnIndex = columnIndex;
      }
      return;
    }

    browseController.selectionAnchorPath = node.path;
    browseController.selectionAnchorColumnIndex = columnIndex;
    if (browseController.selected.isNotEmpty) {
      applySetState(() {
        browseController.selected.clear();
        browseController.selectedSizes.clear();
        browseController.selectedPaths.clear();
        browseController.cachedSelectedBytesKey = null;
      });
    }
    final nextChain = toggleColumnSelection(
      browseController.columnChain,
      columnIndex,
      actualNode,
    );
    applySetState(() {
      setColumnChain(nextChain);
    });
    browse.setCurrentDirectory(browsedDirectoryPath(nextChain));
    browseController.syncCurrentDirectory(browse.currentDirectoryPath);
    final remainsSelected =
        nextChain.length > columnIndex &&
        nextChain[columnIndex].path == node.path;
    if (remainsSelected && actualNode.isDirectory && !actualNode.scanned) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (isMounted()) unawaited(browse.peekScan(actualNode.path));
      });
    }
  }

  bool shouldUseTreeOverlayForPath(String path) {
    final focused = browseController.currentPath;
    if (focused == null || focused.isEmpty) return false;
    return path == focused ||
        focused.startsWith('$path/') ||
        path.startsWith('$focused/');
  }

  bool get showingPreviewSnapshot =>
      session.lastSnapshot?.snapshotId.startsWith('preview-') == true;

  bool shouldUseTreeChildrenFor(ScanTreeNode node) {
    if (browse.directoryOverlayForPath(node.path) != null) return true;
    if (node.children.isEmpty) return false;
    return showingPreviewSnapshot || shouldUseTreeOverlayForPath(node.path);
  }

  SnapshotQueryKey visibleChildrenKeyFor(ScanTreeNode node) {
    // Use the Rust catalog version so view-cache invalidation is aligned with
    // the authoritative index. Falls back to snapshotVersion when the index
    // API is unavailable (older builds).
    return SnapshotQueryKey(
      snapshotId: session.lastSnapshot?.snapshotId ?? 'node-view',
      version: browse.catalogVersion,
      path: node.path,
      categoryFilter: browseController.categoryFilter,
      deletableOnly: browseController.deletableOnly,
      sortMode: sortMode,
    );
  }

  ScanSortMode get sortMode =>
      ScanSortMode.values[browseController.sortIndex.clamp(
        0,
        ScanSortMode.values.length - 1,
      )];

  List<SnapshotNodeRecord> visibleChildrenFor(ScanTreeNode node) {
    // While a directory is being re-scanned (delete refresh / manual refresh),
    // keep showing the previous children instead of clearing the column — the
    // refreshed overlay replaces them atomically when the peek completes, so
    // the list updates in place without blanking out (the flicker source).
    final snap = session.lastSnapshot;
    if (snap == null || !node.isDirectory) {
      return node.children
          .map(SnapshotNodeRecord.fromTree)
          .toList(growable: false);
    }
    final key = visibleChildrenKeyFor(node);
    final cache = browseController.visibleChildrenCache;
    final cached = cache[key];
    if (cached != null) {
      return cached;
    }

    // Re-resolve from the live tree so peek-scan merges (which update
    // tree.children but leave columnChain nodes stale) are visible to the
    // focused branch overlay.
    final liveNode =
        browse.directoryOverlayForPath(node.path) ??
        (shouldUseTreeOverlayForPath(node.path)
            ? (findNodeByPath(browseController.cachedResolvedTree, node.path) ??
                  node)
            : node);

    if (browse.hasIndexApi && shouldUseTreeChildrenFor(liveNode)) {
      final result = visibleChildrenFromTree(liveNode, key);
      cache[key] = result;
      return result;
    }

    if (browse.hasIndexApi) {
      scheduleVisibleChildrenQuery(
        key,
        liveNode,
        preferTree: shouldUseTreeChildrenFor(liveNode),
      );
      return cache.latestForPath(node.path) ?? const <SnapshotNodeRecord>[];
    }

    // Fallback: Dart-side tree traversal for older builds without index API.
    if (liveNode.children.length > _asyncVisibleChildrenThreshold) {
      if (key.categoryFilter == null && !key.deletableOnly) {
        final direct = liveNode.children
            .map(SnapshotNodeRecord.fromTree)
            .toList(growable: false);
        cache[key] = direct;
        return direct;
      }
      scheduleVisibleChildrenQuery(key, liveNode);
      return cache.latestForPath(node.path) ?? const <SnapshotNodeRecord>[];
    }
    final queried = SnapshotCatalog.queryNode(
      reader: browse,
      key: key,
      node: liveNode,
      includeEntryRecords: false,
    ).directNodes.map(SnapshotNodeRecord.fromTree).toList(growable: false);
    final result = queried.isEmpty && liveNode.children.isNotEmpty
        ? const <SnapshotNodeRecord>[]
        : queried;
    cache[key] = result;
    return result;
  }

  List<SnapshotNodeRecord> visibleChildrenFromTree(
    ScanTreeNode node,
    SnapshotQueryKey key,
  ) {
    final children = <SnapshotNodeRecord>[
      for (final child in node.children)
        if (child.matchesView(
          categoryFilter: key.categoryFilter,
          deletableOnly: key.deletableOnly,
        ))
          SnapshotNodeRecord.fromTree(child),
    ];
    if (children.length <= 1) {
      return List.unmodifiable(children);
    }
    children.sort((left, right) {
      if (left.isDirectory != right.isDirectory) {
        return left.isDirectory ? -1 : 1;
      }
      late final int primary;
      switch (key.sortMode) {
        case ScanSortMode.sizeDesc:
          primary = right.displayBytes.compareTo(left.displayBytes);
        case ScanSortMode.sizeAsc:
          primary = left.displayBytes.compareTo(right.displayBytes);
        case ScanSortMode.nameAsc:
          primary = SnapshotCatalog.compareAsciiCaseInsensitive(
            left.name,
            right.name,
          );
      }
      if (primary != 0) return primary;
      final nameOrder = SnapshotCatalog.compareAsciiCaseInsensitive(
        left.name,
        right.name,
      );
      return nameOrder != 0 ? nameOrder : left.path.compareTo(right.path);
    });
    return List.unmodifiable(children);
  }

  bool isPreparingVisibleChildren(ScanTreeNode node) {
    return browse.isDirectoryRefreshing(node.path) ||
        browse.peekInFlight.contains(node.path) ||
        browseController.pendingVisibleChildrenQueries.contains(
          visibleChildrenKeyFor(node),
        );
  }

  void scheduleVisibleChildrenQuery(
    SnapshotQueryKey key,
    ScanTreeNode node, {
    bool preferTree = false,
  }) {
    if (!browseController.pendingVisibleChildrenQueries.add(key)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted() ||
          !browseController.pendingVisibleChildrenQueries.contains(key)) {
        return;
      }
      if (preferTree || !browse.hasIndexApi) {
        unawaited(prepareVisibleChildrenQuery(key, node));
      } else {
        unawaited(prepareCatalogVisibleChildrenQuery(key, node));
      }
    });
  }

  Future<void> prepareCatalogVisibleChildrenQuery(
    SnapshotQueryKey key,
    ScanTreeNode node,
  ) async {
    try {
      await Future<void>.delayed(Duration.zero);
      if (!isMounted() ||
          !browseController.pendingVisibleChildrenQueries.contains(key)) {
        return;
      }
      final catalogResult = browse.queryDirectoryChildrenFromCatalog(
        node.path,
        categoryFilter: key.categoryFilter,
        deletableOnly: key.deletableOnly,
        sortMode: rustSortModeName(key.sortMode),
      );
      if (catalogResult != null) {
        browseController.visibleChildrenCache[key] = catalogResult;
        if (isMounted() &&
            browseController.pendingVisibleChildrenQueries.contains(key)) {
          browseController.columnNavTick.value++;
        }
        return;
      }
      await prepareVisibleChildrenQuery(key, node);
    } catch (_) {
      // Catalog query failed; the tree fallback path will retry on the next
      // rebuild if the cache is still empty.
    } finally {
      browseController.pendingVisibleChildrenQueries.remove(key);
    }
  }

  Future<void> prepareVisibleChildrenQuery(
    SnapshotQueryKey key,
    ScanTreeNode node,
  ) async {
    final children = node.children;
    final names = <String>[];
    final bytes = <int>[];
    final directories = <bool>[];
    final categoryMasks = <int>[];
    final deletableCategoryMasks = <int>[];
    final deletableFileCounts = <int>[];

    try {
      for (var index = 0; index < children.length; index++) {
        if (!isMounted() ||
            !browseController.pendingVisibleChildrenQueries.contains(key)) {
          return;
        }
        final child = children[index];
        names.add(child.name);
        bytes.add(child.displayBytes);
        directories.add(child.isDirectory);
        categoryMasks.add(child.categoryMask);
        deletableCategoryMasks.add(child.deletableCategoryMask);
        deletableFileCounts.add(child.deletableFileCount);
        if (index % 2048 == 2047) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      if (!isMounted() ||
          !browseController.pendingVisibleChildrenQueries.contains(key)) {
        return;
      }
      final input = _VisibleChildrenSortInput(
        sortIndex: key.sortMode.index,
        categoryBit: key.categoryFilter == null
            ? null
            : ScanEntryRecord.categoryMaskFor(key.categoryFilter),
        deletableOnly: key.deletableOnly,
        names: names,
        bytes: bytes,
        directories: directories,
        categoryMasks: categoryMasks,
        deletableCategoryMasks: deletableCategoryMasks,
        deletableFileCounts: deletableFileCounts,
      );
      final indices = _visibleChildrenIndices(input);
      if (indices.length <= _maxAsyncSortedChildren) {
        _sortVisibleChildrenIndices(input, indices);
      }
      if (!isMounted() ||
          !browseController.pendingVisibleChildrenQueries.contains(key)) {
        return;
      }
      browseController.visibleChildrenCache[key] = List.unmodifiable([
        for (final index in indices)
          if (index >= 0 && index < children.length)
            SnapshotNodeRecord.fromTree(children[index]),
      ]);
      browseController.columnNavTick.value++;
    } catch (_) {
      // A failed async view preparation should not break browsing; the next
      // rebuild can retry and still has the unsorted direct children fallback.
    } finally {
      browseController.pendingVisibleChildrenQueries.remove(key);
    }
  }

  void toggleFocusedFileSelection(ScanTreeNode node) {
    if (session.deleting || session.scanning) return;
    applySetState(() {
      toggleNodeSelection(node);
      browseController.cachedSelectedBytesKey = null;
    });
  }

  void toggleNodeSelection(ScanTreeNode node) {
    if (node.category == 'System') return;
    final id = node.entryId ?? node.path;
    if (id.isEmpty) return;
    if (browseController.selected.contains(id)) {
      browseController.selected.remove(id);
      browseController.selectedSizes.remove(id);
      browseController.selectedPaths.remove(id);
      return;
    }
    addNodeSelection(node);
  }

  void addNodeSelection(ScanTreeNode node) {
    if (node.category == 'System') return;
    final id = node.entryId ?? node.path;
    if (id.isEmpty || browseController.selected.contains(id)) return;
    final prefix = '${node.path}/';
    if (browseController.selectedPaths.values.any(
      (path) => node.path.startsWith('$path/'),
    )) {
      return;
    }
    if (node.isDirectory) {
      final childIds = browseController.selectedPaths.entries
          .where((entry) => entry.value.startsWith(prefix))
          .map((entry) => entry.key)
          .toList();
      for (final childId in childIds) {
        browseController.selected.remove(childId);
        browseController.selectedSizes.remove(childId);
        browseController.selectedPaths.remove(childId);
      }
    }
    browseController.selected.add(id);
    browseController.selectedSizes[id] = node.displayBytes;
    browseController.selectedPaths[id] = node.path;
  }

  String phaseLabel(String phase, AppLocalizations strings) {
    return switch (phase) {
      'DiscoveringRoots' => strings.scanPhaseDiscoveringRoots,
      'Walking' => strings.scanPhaseWalking,
      'Classifying' => strings.scanPhaseClassifying,
      'Aggregating' => strings.scanPhaseAggregating,
      'SavingResults' => strings.scanPhaseSavingResults,
      'LoadingResults' => strings.scanPhaseLoadingResults,
      'Done' => strings.scanPhaseDone,
      _ => phase,
    };
  }

  String scanProgressSummary() {
    final strings = l10n();
    final p = scanPresentationController.progressDetail;
    if (p == null) return strings.scanStatusScanning;
    final phaseKey = p['phase']?.toString() ?? '';
    final phase = phaseLabel(phaseKey, strings);
    final paths = p['paths_seen'];
    final elapsed = scanPresentationController.elapsedLabel.value;
    final frac = scanPresentationController.scannedFraction.value;
    // Cap displayed % at 99 while the scan is active; only the Done phase can
    // report 100 so completion never appears before the native scan finishes.
    final pct = frac != null
        ? (phaseKey == 'Done' ? 100 : (frac * 100).floor().clamp(0, 99))
        : null;
    final pctStr = pct != null ? '$pct% · ' : '';
    final buf = StringBuffer('$pctStr$phase');
    if (paths != null && paths != 0) {
      buf.write(' · ${strings.scanProgressItems((paths as num).toInt())}');
    }
    if (elapsed != null) buf.write(' · $elapsed');
    // Deliberately omit current_path — too verbose for a single-line bar.
    return buf.toString();
  }

  int matchingEntryCount() {
    return session.lastSnapshot?.matchingEntryCount(
          browseController.categoryFilter,
          deletableOnly: browseController.deletableOnly,
        ) ??
        0;
  }

  /// Returns the total size of the currently-selected entries.
  /// Cached by snapshot ID plus selected IDs so the summary only recomputes
  /// after selection or snapshot changes.
  int selectedBytes() {
    final selected = browseController.selected;
    if (selected.isEmpty) return 0;
    final selectedKey = (selected.toList()..sort()).join(',');
    final compositeKey =
        '${session.lastSnapshot?.snapshotId ?? ''}|$selectedKey';
    if (compositeKey == browseController.cachedSelectedBytesKey) {
      return browseController.cachedSelectedBytes;
    }
    browseController.cachedSelectedBytes = selected.fold<int>(
      0,
      (sum, id) => sum + (browseController.selectedSizes[id] ?? 0),
    );
    browseController.cachedSelectedBytesKey = compositeKey;
    return browseController.cachedSelectedBytes;
  }

  ScanTreeNode? focusedDeleteNode() {
    if (showingPreviewSnapshot || session.targetPreviewLoading) {
      return null;
    }
    final focus = scanColumnFocusNode(browseController.columnChain);
    if (focus == null || focus.category == 'System') {
      return null;
    }
    return focus;
  }

  List<String> deleteTargetStrings() {
    if (browseController.selected.isNotEmpty) {
      return browseController.selected.toList();
    }
    final target = deleteTargetFromFocus(focusedDeleteNode());
    if (target == null || target.isEmpty) return const [];
    return [target];
  }

  int deleteTargetCount() {
    if (browseController.selected.isNotEmpty) {
      return browseController.selected.length;
    }
    return focusedDeleteNode() == null ? 0 : 1;
  }

  int deleteTargetBytes() {
    if (browseController.selected.isNotEmpty) return selectedBytes();
    return focusedDeleteNode()?.sizeBytes ?? 0;
  }

  String treeSummary(ScanTreeNode tree) {
    final filesSeen = session.lastSnapshot?.stats['files_seen'] as num?;
    final count = filesSeen?.toInt() ?? tree.subtreeFileCount ?? tree.fileCount;
    return l10n().resultsTreeSummary(
      count,
      formatDirectoryBytes(tree.displayBytes),
    );
  }

  String compactResultsSummary(ScanTreeNode? displayTree, int matchingCount) {
    final snap = session.lastSnapshot;
    final reclaimable = snap?.reclaimableEstimateBytes;
    final strings = l10n();
    final parts = <String>[];
    if (displayTree != null) {
      parts.add(treeSummary(displayTree));
    }
    parts.add(strings.resultsClassifiedCount(matchingCount));
    if (reclaimable != null) {
      parts.add(
        strings.resultsReclaimableBytes(formatDirectoryBytes(reclaimable)),
      );
    }
    return parts.join(' · ');
  }
}

class _VisibleChildrenSortInput {
  const _VisibleChildrenSortInput({
    required this.sortIndex,
    required this.categoryBit,
    required this.deletableOnly,
    required this.names,
    required this.bytes,
    required this.directories,
    required this.categoryMasks,
    required this.deletableCategoryMasks,
    required this.deletableFileCounts,
  });

  final int sortIndex;
  final int? categoryBit;
  final bool deletableOnly;
  final List<String> names;
  final List<int> bytes;
  final List<bool> directories;
  final List<int> categoryMasks;
  final List<int> deletableCategoryMasks;
  final List<int> deletableFileCounts;
}

List<int> _visibleChildrenIndices(_VisibleChildrenSortInput input) {
  final directories = <int>[];
  final files = <int>[];
  final count = input.names.length;
  for (var index = 0; index < count; index++) {
    if (!_matchesVisibleProjection(input, index)) continue;
    if (input.directories[index]) {
      directories.add(index);
    } else {
      files.add(index);
    }
  }
  return <int>[...directories, ...files];
}

void _sortVisibleChildrenIndices(
  _VisibleChildrenSortInput input,
  List<int> indices,
) {
  int compare(int left, int right) {
    final sortMode = ScanSortMode
        .values[input.sortIndex.clamp(0, ScanSortMode.values.length - 1)];
    switch (sortMode) {
      case ScanSortMode.sizeAsc:
        return input.bytes[left].compareTo(input.bytes[right]);
      case ScanSortMode.sizeDesc:
        return input.bytes[right].compareTo(input.bytes[left]);
      case ScanSortMode.nameAsc:
        return SnapshotCatalog.compareAsciiCaseInsensitive(
          input.names[left],
          input.names[right],
        );
    }
  }

  final split = indices.indexWhere((index) => !input.directories[index]);
  if (split < 0) {
    indices.sort(compare);
    return;
  }
  final sortedDirectories = indices.sublist(0, split)..sort(compare);
  final sortedFiles = indices.sublist(split)..sort(compare);
  indices
    ..setRange(0, split, sortedDirectories)
    ..setRange(split, indices.length, sortedFiles);
}

bool _matchesVisibleProjection(_VisibleChildrenSortInput input, int index) {
  final categoryBit = input.categoryBit;
  if (categoryBit == null && !input.deletableOnly) return true;
  if (input.deletableOnly) {
    if (input.deletableFileCounts[index] == 0) return false;
    if (categoryBit != null) {
      return (input.deletableCategoryMasks[index] & categoryBit) != 0;
    }
    return true;
  }
  return (input.categoryMasks[index] & categoryBit!) != 0;
}
