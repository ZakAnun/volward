import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'l10n/l10n.dart';
import 'macos_settings.dart';
import 'scan_entry_record.dart';
import 'scan_tree.dart';
import 'theme/apple_tokens.dart';
import 'settings_page.dart';
import 'theme/volward_theme_settings.dart';
import 'theme/volward_tokens.dart';
import 'volward_session.dart';
import 'widgets/apple_widgets.dart';
import 'widgets/volward_logo.dart';
import 'widgets/scan_column_view.dart';
import 'widgets/scan_filter_bar.dart';
import 'scan_tree_navigation.dart';
import 'snapshot_catalog.dart';
import 'snapshot_query.dart';
import 'snapshot_view_cache.dart';
import 'widgets/top_toast.dart';

/// Returns the path that the refresh button should target (Design §6.1).
///
/// Top-level pure function — exposed here for unit testing.
/// If the currently focused node is a directory, returns its path.
/// Otherwise falls back to [rootPath].
String refreshPathFromFocus({required String rootPath, ScanTreeNode? focused}) {
  if (focused != null && focused.isDirectory) return focused.path;
  return rootPath;
}

/// Returns the delete target for the currently focused node.
///
/// Files keep using their native entry id when available; directories and
/// id-less leaves fall back to their absolute path so Rust can trash them by
/// path.
String? deleteTargetFromFocus(ScanTreeNode? focused) {
  if (focused == null || focused.category == 'System') return null;
  if (!focused.isDirectory) {
    final entryId = focused.entryId;
    if (entryId != null && entryId.isNotEmpty) return entryId;
  }
  return focused.path;
}

String _parentPathOf(String path) {
  final normalized = ScanTreeBuilder.normalizeRoot(path);
  final idx = normalized.lastIndexOf('/');
  if (idx <= 0) return '/';
  return normalized.substring(0, idx);
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.session,
    required this.themeSettings,
  });
  final VolwardSession session;
  final VolwardThemeSettings themeSettings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  String? _scanStatus;
  String? _categoryFilter;
  bool _deletableOnly = false;
  // Ordinal backing: survives hot reload when enum type/name changes.
  int _sortIndex = ScanSortMode.sizeDesc.index;
  final Set<String> _selected = {};
  final Map<String, int> _selectedSizes = {};
  final List<ScanTreeNode> _columnChain = [];
  final ValueNotifier<int> _columnNavTick = ValueNotifier(0);
  bool _prevScanning = false;
  bool _permissionBannerExpanded = false;
  // Tracks the last `_lastSnapshot.snapshotId` we already observed, so plain
  // progress ticks do not trigger a full page rebuild while browsing during a
  // background scan.
  String? _lastRefreshedSnapshotId;
  // Tracks the last catalog version so refreshCurrentDirectory() (which does
  // not change snapshotId) still triggers a rebuild via setState.
  int _lastRefreshedCatalogVersion = -1;
  bool _lastTargetPreviewLoading = false;

  // ---------- canonical snapshot cache ----------
  ScanTreeNode? _cachedResolvedTree;
  String? _cachedResolvedTreeKey;

  // Cache for _selectedBytes — recomputed only when the selected IDs or
  // snapshot changes, not on every build() call.
  int _cachedSelectedBytes = 0;
  String? _cachedSelectedBytesKey; // snapshot ID + selection IDs.
  final SnapshotViewCache<List<SnapshotNodeRecord>> _visibleChildrenCache =
      SnapshotViewCache(capacity: 128);
  final Set<SnapshotQueryKey> _pendingVisibleChildrenQueries = {};

  static const int _asyncVisibleChildrenThreshold = 512;
  static const int _maxAsyncSortedChildren = 2048;

  VolwardSession get _s => widget.session;

  ScanSortMode get _sort =>
      ScanSortMode.values[_sortIndex.clamp(0, ScanSortMode.values.length - 1)];

  set _sort(ScanSortMode mode) => _sortIndex = mode.index;

  @override
  void reassemble() {
    super.reassemble();
    _sortIndex = _sortIndex.clamp(0, ScanSortMode.values.length - 1);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_onSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.session.restoreCachedSnapshotIfNeeded();
      if (!mounted) return;
      if (widget.session.lastSnapshot == null) {
        await widget.session.previewTarget();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_onSessionChanged);
    _columnNavTick.dispose();
    _pendingVisibleChildrenQueries.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _s.refreshCapabilities();
    }
  }

  Future<void> _openFullDiskAccessSettings() async {
    await MacosSettings.touchFullDiskAccessProbe();
    if (mounted && !_permissionBannerExpanded) {
      setState(() => _permissionBannerExpanded = true);
    }
    await MacosSettings.openFullDiskAccessSettings();
  }

  Future<void> _copyAppBundlePath() async {
    await MacosSettings.copyAppBundlePath();
    if (!mounted) return;
    final path = MacosSettings.appBundlePath();
    final l10n = context.l10n;
    showTopToast(
      context,
      message: l10n.permissionCopiedPath(path ?? l10n.permissionUnknownPath),
      type: ToastType.success,
    );
  }

  void _onSessionChanged() {
    final targetPreviewChanged =
        _lastTargetPreviewLoading != _s.targetPreviewLoading;
    _lastTargetPreviewLoading = _s.targetPreviewLoading;

    if (targetPreviewChanged && _s.targetPreviewLoading) {
      setState(() {
        _selected.clear();
        _selectedSizes.clear();
        _scanStatus = null;
        _columnChain.clear();
        _columnNavTick.value++;
        _invalidateSnapshotCaches();
        _lastRefreshedSnapshotId = null;
        _lastRefreshedCatalogVersion = _s.catalogVersion;
      });
    } else if (!_prevScanning && _s.scanning) {
      setState(() {
        _selected.clear();
        _selectedSizes.clear();
        _scanStatus = null;
        _columnChain.clear();
        _columnNavTick.value++;
        _invalidateSnapshotCaches();
        _lastRefreshedSnapshotId = _s.lastSnapshot?.snapshotId;
      });
    } else if (_prevScanning && !_s.scanning && _s.lastSnapshot != null) {
      // Scan completed (possibly auto-started by switchScanRoot) — show stats.
      final count = _s.lastSnapshot?.filesInSnapshot ?? 0;
      final l10n = context.l10n;
      final label =
          _s.incrementalScan ? l10n.scanStatusIncremental : l10n.scanStatusFull;
      setState(() {
        _scanStatus = l10n.scanStatusFiles(label, count);
        _columnChain.clear();
        _columnNavTick.value++;
        _invalidateSnapshotCaches();
        _selectedSizes.clear();
        _lastRefreshedSnapshotId = _s.lastSnapshot?.snapshotId;
      });
    } else {
      // Checkpoint / peek merged new data. Refresh display caches whenever
      // snapshot_id changed — including when the user is still on the root
      // column (_columnChain empty), so preview spinners clear as soon as
      // the background walk rediscovers each directory.
      // Also rebuild when catalog version advances without a snapshotId change
      // (e.g. after refreshCurrentDirectory() — pure catalog re-query).
      final snapId = _s.lastSnapshot?.snapshotId;
      final catalogVer = _s.catalogVersion;
      final snapChanged = snapId != null && snapId != _lastRefreshedSnapshotId;
      final catalogChanged = catalogVer != _lastRefreshedCatalogVersion;
      if (snapChanged || catalogChanged || targetPreviewChanged) {
        if (snapChanged) _lastRefreshedSnapshotId = snapId;
        _lastRefreshedCatalogVersion = catalogVer;
        _invalidateSnapshotCachesForSessionUpdate();
        final tree = _resolveResultTree();
        if (_columnChain.isNotEmpty && tree != null) {
          // When the catalog index API is active, Dart tree.children is empty
          // (children come from Rust), so refreshColumnChain would always
          // truncate the chain to []. Skip the re-validation; the
          // visible-children cache invalidation above is sufficient.
          if (!_s.hasIndexApi) {
            final refreshed = refreshColumnChain(tree, _columnChain);
            final chainChanged = refreshed.length != _columnChain.length ||
                !Iterable.generate(
                  refreshed.length,
                ).every((i) => refreshed[i].path == _columnChain[i].path);
            if (chainChanged) _setColumnChain(refreshed);
          }
        }
        setState(() {});
      }
      // Else: no snapshot or catalog change — skip setState entirely.
      // This covers the common case of VolwardSession.notifyListeners() fired
      // for progress ticks (elapsed timer, etc.) without any snapshot change.
    }
    _prevScanning = _s.scanning;
  }

  String _scanRootPath() {
    if (_s.scanRoots.isNotEmpty) {
      return ScanTreeBuilder.normalizeRoot(_s.scanRoots.first);
    }
    return ScanTreeBuilder.normalizeRoot(Platform.environment['HOME'] ?? '/');
  }

  String _scanTargetLabel(BuildContext context) {
    return _s.scanRoots.isEmpty
        ? context.l10n.scanTargetHomeDefault
        : _s.scanRoots.join(', ');
  }

  ScanTreeNode? _resolveResultTree() {
    final snapId = _s.lastSnapshot?.snapshotId ?? '';
    if (_cachedResolvedTree != null && _cachedResolvedTreeKey == snapId) {
      return _cachedResolvedTree;
    }

    final snap = _s.lastSnapshot;
    if (snap == null) return null;

    ScanTreeNode? tree = snap.tree;
    final rootPath = (tree != null && tree.path.isNotEmpty)
        ? ScanTreeBuilder.normalizeRoot(tree.path)
        : _scanRootPath();

    if ((tree == null || tree.children.isEmpty) && snap.hasFlatEntries) {
      final entries = snap.materializeEntries();
      tree = ScanTreeBuilder.build(entries: entries, rootPath: rootPath);
    }

    _cachedResolvedTree = tree;
    _cachedResolvedTreeKey = snapId;
    return tree;
  }

  bool _snapshotMatchesCurrentRoot() {
    final tree = _s.lastSnapshot?.tree;
    if (tree == null || tree.path.isEmpty) return false;
    return ScanTreeBuilder.normalizeRoot(tree.path) == _scanRootPath();
  }

  void _invalidateSnapshotCaches() {
    _cachedResolvedTree = null;
    _cachedResolvedTreeKey = null;
    _cachedSelectedBytesKey = null;
    _visibleChildrenCache.clear();
    _pendingVisibleChildrenQueries.clear();
  }

  void _invalidateSnapshotCachesForSessionUpdate() {
    _cachedResolvedTree = null;
    _cachedResolvedTreeKey = null;
    _cachedSelectedBytesKey = null;

    final prefixes = _s.consumeInvalidatedPrefixes();
    if (prefixes.isEmpty) {
      _visibleChildrenCache.clear();
      _pendingVisibleChildrenQueries.clear();
      return;
    }
    for (final prefix in prefixes) {
      _visibleChildrenCache.invalidatePath(prefix);
    }
    _pendingVisibleChildrenQueries.removeWhere((key) {
      for (final prefix in prefixes) {
        if (key.path == prefix || key.path.startsWith('$prefix/')) {
          return true;
        }
      }
      return false;
    });
  }

  void _resetColumnNav() {
    _columnChain.clear();
    _columnNavTick.value++;
  }

  void _setColumnChain(List<ScanTreeNode> next) {
    _columnChain
      ..clear()
      ..addAll(next);
    _prunePendingVisibleQueries();
    _columnNavTick.value++;
  }

  void _prunePendingVisibleQueries() {
    final visiblePaths = <String>{};
    final root = _cachedResolvedTree ?? _s.lastSnapshot?.tree;
    if (root != null) visiblePaths.add(root.path);
    for (final node in _columnChain) {
      visiblePaths.add(node.path);
    }
    _pendingVisibleChildrenQueries.removeWhere(
      (key) => !visiblePaths.contains(key.path),
    );
  }

  ScanTreeNode? _findNodeByPath(ScanTreeNode? root, String targetPath) {
    if (root == null) return null;
    if (root.path == targetPath) return root;
    if (!root.isDirectory) return null;
    for (final child in root.children) {
      final found = _findNodeByPath(child, targetPath);
      if (found != null) return found;
    }
    return null;
  }

  void _onColumnSelect(int columnIndex, SnapshotNodeRecord node) {
    final currentTree = _resolveResultTree();
    final actualNode =
        _findNodeByPath(currentTree, node.path) ?? node.toScanTreeNode();
    setState(() {
      _setColumnChain(_columnChain.take(columnIndex).toList()..add(actualNode));
      if (actualNode.isDirectory) {
        _selected.clear();
        _selectedSizes.clear();
        _cachedSelectedBytesKey = null;
      }
    });
    // Notify session of the currently browsed path so refreshCurrentDirectory
    // targets the right directory (Design §6.1).
    if (actualNode.isDirectory) {
      _s.setCurrentDirectory(actualNode.path);
    }
    if (actualNode.isDirectory && !actualNode.scanned) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_s.peekScan(actualNode.path));
      });
    }
  }

  bool _shouldUseTreeOverlayForPath(String path) {
    final focused = _s.currentDirectoryPath;
    if (focused == null || focused.isEmpty) return false;
    return path == focused ||
        focused.startsWith('$path/') ||
        path.startsWith('$focused/');
  }

  bool get _showingPreviewSnapshot =>
      _s.lastSnapshot?.snapshotId.startsWith('preview-') == true;

  bool _shouldUseTreeChildrenFor(ScanTreeNode node) {
    if (node.children.isEmpty) return false;
    return _showingPreviewSnapshot || _shouldUseTreeOverlayForPath(node.path);
  }

  SnapshotQueryKey _visibleChildrenKeyFor(ScanTreeNode node) {
    // Use the Rust catalog version so view-cache invalidation is aligned with
    // the authoritative index (Design §5.4).  Falls back to snapshotVersion
    // when the index API is unavailable (older builds).
    return SnapshotQueryKey(
      snapshotId: _s.lastSnapshot?.snapshotId ?? 'node-view',
      version: _s.catalogVersion,
      path: node.path,
      categoryFilter: _categoryFilter,
      deletableOnly: _deletableOnly,
      sortMode: _sort,
    );
  }

  List<SnapshotNodeRecord> _visibleChildrenFor(ScanTreeNode node) {
    final snap = _s.lastSnapshot;
    if (snap == null || !node.isDirectory) {
      return node.children
          .map(SnapshotNodeRecord.fromTree)
          .toList(growable: false);
    }
    final key = _visibleChildrenKeyFor(node);
    final cached = _visibleChildrenCache[key];
    if (cached != null) {
      return cached;
    }

    // Re-resolve from the live tree so peek-scan merges (which update
    // tree.children but leave _columnChain nodes stale) are visible to the
    // focused branch overlay.
    final liveNode = _shouldUseTreeOverlayForPath(node.path)
        ? (_findNodeByPath(_cachedResolvedTree, node.path) ?? node)
        : node;

    if (_s.hasIndexApi && _shouldUseTreeChildrenFor(liveNode)) {
      final result = _visibleChildrenFromTree(liveNode, key);
      _visibleChildrenCache[key] = result;
      return result;
    }

    if (_s.hasIndexApi) {
      _scheduleVisibleChildrenQuery(
        key,
        liveNode,
        preferTree: _shouldUseTreeChildrenFor(liveNode),
      );
      return _visibleChildrenCache.latestForPath(node.path) ??
          const <SnapshotNodeRecord>[];
    }

    // Fallback: Dart-side tree traversal for older builds without index API.
    if (liveNode.children.length > _asyncVisibleChildrenThreshold) {
      if (key.categoryFilter == null && !key.deletableOnly) {
        final direct = liveNode.children
            .map(SnapshotNodeRecord.fromTree)
            .toList(growable: false);
        _visibleChildrenCache[key] = direct;
        return direct;
      }
      _scheduleVisibleChildrenQuery(key, liveNode);
      return _visibleChildrenCache.latestForPath(node.path) ??
          const <SnapshotNodeRecord>[];
    }
    final queried = SnapshotCatalog.queryNode(
      key: key,
      node: liveNode,
      includeEntryRecords: false,
    ).directNodes.map(SnapshotNodeRecord.fromTree).toList(growable: false);
    final result = queried.isEmpty && liveNode.children.isNotEmpty
        ? const <SnapshotNodeRecord>[]
        : queried;
    _visibleChildrenCache[key] = result;
    return result;
  }

  List<SnapshotNodeRecord> _visibleChildrenFromTree(
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
      switch (key.sortMode) {
        case ScanSortMode.sizeDesc:
          return right.displayBytes.compareTo(left.displayBytes);
        case ScanSortMode.sizeAsc:
          return left.displayBytes.compareTo(right.displayBytes);
        case ScanSortMode.nameAsc:
          return SnapshotCatalog.compareAsciiCaseInsensitive(
            left.name,
            right.name,
          );
      }
    });
    return List.unmodifiable(children);
  }

  bool _isPreparingVisibleChildren(ScanTreeNode node) {
    return _pendingVisibleChildrenQueries.contains(
      _visibleChildrenKeyFor(node),
    );
  }

  void _scheduleVisibleChildrenQuery(
    SnapshotQueryKey key,
    ScanTreeNode node, {
    bool preferTree = false,
  }) {
    if (!_pendingVisibleChildrenQueries.add(key)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pendingVisibleChildrenQueries.contains(key)) return;
      if (preferTree || !_s.hasIndexApi) {
        unawaited(_prepareVisibleChildrenQuery(key, node));
      } else {
        unawaited(_prepareCatalogVisibleChildrenQuery(key, node));
      }
    });
  }

  Future<void> _prepareCatalogVisibleChildrenQuery(
    SnapshotQueryKey key,
    ScanTreeNode node,
  ) async {
    try {
      await Future<void>.delayed(Duration.zero);
      if (!mounted || !_pendingVisibleChildrenQueries.contains(key)) return;
      final catalogResult = _s.queryDirectoryChildrenFromCatalog(
        node.path,
        categoryFilter: key.categoryFilter,
        deletableOnly: key.deletableOnly,
        sortMode: rustSortModeName(key.sortMode),
      );
      if (catalogResult != null) {
        _visibleChildrenCache[key] = catalogResult;
        if (mounted && _pendingVisibleChildrenQueries.contains(key)) {
          _columnNavTick.value++;
        }
        return;
      }
      await _prepareVisibleChildrenQuery(key, node);
    } catch (_) {
      // Catalog query failed; the tree fallback path will retry on the next
      // rebuild if the cache is still empty.
    } finally {
      _pendingVisibleChildrenQueries.remove(key);
    }
  }

  Future<void> _prepareVisibleChildrenQuery(
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
        if (!mounted || !_pendingVisibleChildrenQueries.contains(key)) return;
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

      if (!mounted || !_pendingVisibleChildrenQueries.contains(key)) return;
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
      if (!mounted || !_pendingVisibleChildrenQueries.contains(key)) return;
      _visibleChildrenCache[key] = List.unmodifiable([
        for (final index in indices)
          if (index >= 0 && index < children.length)
            SnapshotNodeRecord.fromTree(children[index]),
      ]);
      _columnNavTick.value++;
    } catch (_) {
      // A failed async view preparation should not break browsing; the next
      // rebuild can retry and still has the unsorted direct children fallback.
    } finally {
      _pendingVisibleChildrenQueries.remove(key);
    }
  }

  void _toggleFocusedFileSelection(ScanTreeNode node) {
    if (node.isDirectory || node.category == 'System') return;
    final id = node.entryId;
    if (id == null || id.isEmpty) return;
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        _selectedSizes.remove(id);
      } else {
        _selected.add(id);
        _selectedSizes[id] = node.displayBytes;
      }
    });
  }

  static String _fmt(num? bytes) {
    if (bytes == null) return '—';
    final b = bytes.toInt();
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(2)} GB';
  }

  String _phaseLabel(String phase) {
    final l10n = context.l10n;
    return switch (phase) {
      'DiscoveringRoots' => l10n.scanPhaseDiscoveringRoots,
      'Walking' => l10n.scanPhaseWalking,
      'Classifying' => l10n.scanPhaseClassifying,
      'Aggregating' => l10n.scanPhaseAggregating,
      'SavingResults' => l10n.scanPhaseSavingResults,
      'LoadingResults' => l10n.scanPhaseLoadingResults,
      'Done' => l10n.scanPhaseDone,
      _ => phase,
    };
  }

  String _scanProgressSummary() {
    final p = _s.scanProgress;
    if (p == null) return context.l10n.scanStatusScanning;
    final phaseKey = p['phase']?.toString() ?? '';
    final phase = _phaseLabel(phaseKey);
    final paths = p['paths_seen'];
    final elapsed = _s.scanElapsedLabel;
    final frac = _s.scannedFraction;
    // Cap displayed % at 99 while the scan is active; only the Done phase can
    // report 100 so completion never appears before the native scan finishes.
    final pct = frac != null
        ? (phaseKey == 'Done' ? 100 : (frac * 100).floor().clamp(0, 99))
        : null;
    final pctStr = pct != null ? '$pct% · ' : '';
    final buf = StringBuffer('$pctStr$phase');
    if (paths != null && paths != 0) {
      buf.write(' · ${context.l10n.scanProgressItems((paths as num).toInt())}');
    }
    if (elapsed != null) buf.write(' · $elapsed');
    // Deliberately omit current_path — too verbose for a single-line bar.
    return buf.toString();
  }

  int _matchingEntryCount() {
    return _s.lastSnapshot?.matchingEntryCount(
          _categoryFilter,
          deletableOnly: _deletableOnly,
        ) ??
        0;
  }

  /// Returns the total size of the currently-selected entries.
  /// Cached by snapshot ID plus selected IDs so the summary only recomputes
  /// after selection or snapshot changes.
  int _selectedBytes() {
    if (_selected.isEmpty) return 0;
    final selectedKey =
        _selected.isEmpty ? '' : (_selected.toList()..sort()).join(',');
    final compositeKey = '${_s.lastSnapshot?.snapshotId ?? ''}|$selectedKey';
    if (compositeKey == _cachedSelectedBytesKey) return _cachedSelectedBytes;
    _cachedSelectedBytes = _selected.fold<int>(
      0,
      (sum, id) => sum + (_selectedSizes[id] ?? 0),
    );
    _cachedSelectedBytesKey = compositeKey;
    return _cachedSelectedBytes;
  }

  ScanTreeNode? _focusedDeleteNode() {
    if (_showingPreviewSnapshot || _s.targetPreviewLoading) {
      return null;
    }
    final focus = scanColumnFocusNode(_columnChain);
    if (focus == null || focus.category == 'System') {
      return null;
    }
    return focus;
  }

  List<String> _deleteTargetStrings() {
    if (_selected.isNotEmpty) return _selected.toList();
    final target = deleteTargetFromFocus(_focusedDeleteNode());
    if (target == null || target.isEmpty) return const [];
    return [target];
  }

  int _deleteTargetCount() {
    if (_selected.isNotEmpty) return _selected.length;
    return _focusedDeleteNode() == null ? 0 : 1;
  }

  int _deleteTargetBytes() {
    if (_selected.isNotEmpty) return _selectedBytes();
    return _focusedDeleteNode()?.sizeBytes ?? 0;
  }

  Future<void> _pickFolder() async {
    final path = await getDirectoryPath(
      confirmButtonText: context.l10n.folderPickerConfirm,
    );
    if (path == null) return;
    await _s.switchScanRoot(path);
  }

  Future<void> _startScan() async {
    if (!_s.ready) return;
    final incremental = _s.incrementalScan;
    try {
      final id = await _s.runScan();
      if (!mounted) return;
      final snapshot = _s.lastSnapshot;
      final count = snapshot?.filesInSnapshot ?? 0;
      final l10n = context.l10n;
      final label =
          incremental ? l10n.scanStatusIncremental : l10n.scanStatusFull;
      setState(() {
        _scanStatus = '${l10n.scanStatusFiles(label, count)} · $id';
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e is ScanCancelledException
          ? context.l10n.scanStatusCancelled
          : context.l10n.scanStatusFailed(e.toString());
      setState(() => _scanStatus = msg);
    }
  }

  Future<void> _confirmDelete() async {
    final targetStrings = _deleteTargetStrings();
    if (targetStrings.isEmpty) return;
    final focus = _focusedDeleteNode();
    final refreshPath = focus == null ? null : _parentPathOf(focus.path);
    final shouldRetreatFocus = targetStrings.length == 1 && focus != null;
    final preview = await _s.deleteEntries(targetStrings, dryRun: true);
    if (!mounted) return;
    final l10n = context.l10n;
    final count = (preview['deleted_count'] as num?)?.toInt() ?? 0;
    final freed = (preview['freed_bytes'] as num?)?.toInt() ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmMessage(count, _fmt(freed))),
        actions: [
          AppleButton(
            label: l10n.scanActionCancel,
            variant: AppleButtonVariant.pearl,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          AppleButton(
            label: l10n.deleteActionDelete,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final report = await _s.deleteEntries(
        targetStrings,
        rescanAfterDelete: true,
        refreshPath: refreshPath,
      );
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _selectedSizes.clear();
        _cachedSelectedBytesKey = null;
      });
      if (shouldRetreatFocus && _columnChain.isNotEmpty) {
        // Drop the stale leaf so a second delete cannot target the removed node.
        _setColumnChain(_columnChain.take(_columnChain.length - 1).toList());
      }
      final freedAfter = (report['freed_bytes'] as num?)?.toInt() ?? 0;
      final failed = report['failed_paths'];
      final failedCount = failed is List ? failed.length : 0;
      showTopToast(
        context,
        message: failedCount > 0
            ? l10n.deleteSuccessWithFailures(failedCount, _fmt(freedAfter))
            : l10n.deleteSuccess(_fmt(freedAfter)),
        type: failedCount > 0 ? ToastType.error : ToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showTopToast(
        context,
        message: l10n.deleteFailed(e.toString()),
        type: ToastType.error,
      );
    }
  }

  Future<void> _confirmEmptyTrash() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.trashEmptyConfirmTitle),
        content: Text(l10n.trashEmptyConfirmMessage),
        actions: [
          AppleButton(
            label: l10n.scanActionCancel,
            variant: AppleButtonVariant.pearl,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          AppleButton(
            label: l10n.trashActionEmpty,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _s.emptyTrash(rescanAfterEmpty: true);
      if (!mounted) return;
      showTopToast(
        context,
        message: l10n.trashEmptySuccess,
        type: ToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showTopToast(
        context,
        message: l10n.trashEmptyFailed(e.toString()),
        type: ToastType.error,
      );
    }
  }

  // Section wrapper with tighter page rhythm.
  Widget _pad(Widget child, {EdgeInsets? padding}) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Padding(
          padding: padding ??
              const EdgeInsets.fromLTRB(
                AppleSpacing.lg,
                AppleSpacing.sm,
                AppleSpacing.lg,
                0,
              ),
          child: child,
        ),
      ),
    );
  }

  /// Like [_pad] but fills remaining vertical space (for column browser).
  Widget _padExpanded(Widget child, {required EdgeInsets padding}) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final maxH = constraints.maxHeight;
          if (!maxH.isFinite || maxH <= 0) {
            return const SizedBox.shrink();
          }
          final width = maxW > 880 ? 880.0 : maxW;
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: width, height: maxH, child: child),
          );
        },
      ),
    );
  }

  Widget _buildCompactResultsChrome(
    BuildContext context, {
    required int matchingCount,
    required ScanTreeNode? displayTree,
  }) {
    final showPermission =
        _s.ready && (!_s.hasSnapshotFileApi || !_s.deepScanReady);
    final busy = _s.deleting || _s.scanning;

    return _pad(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showPermission) ...[
            _buildPermissionBanner(context),
            const SizedBox(height: AppleSpacing.xxs),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _compactResultsSummary(displayTree, matchingCount),
                  style: context.vwFinePrintInk,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppleSpacing.xs),
              Tooltip(
                message: _scanTargetLabel(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _s.scanRoots.isEmpty
                          ? context.l10n.scanTargetHomeShort
                          : context.l10n.scanTargetCustomShort,
                      style: context.vwFinePrint,
                    ),
                    if (_s.scanning) ...[
                      const SizedBox(width: 4),
                      ValueListenableBuilder<double?>(
                        valueListenable: _s.scannedFractionNotifier,
                        builder: (ctx, frac, _) {
                          return Text(
                            frac != null ? '${(frac * 100).round()}%' : '…',
                            style: ctx.vwFinePrint.copyWith(
                              color: ctx.volward.primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppleSpacing.xs),
              IconButton(
                icon: Icon(
                  Icons.refresh_outlined,
                  size: 18,
                  color: context.volward.inkMuted80,
                ),
                tooltip: context.l10n.scanActionRescan,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: (_s.ready && !busy && _s.hasSnapshotFileApi)
                    ? () => unawaited(_s.refreshCurrentDirectory())
                    : null,
              ),
              const SizedBox(width: AppleSpacing.xxs),
              AppleButton(
                label: context.l10n.scanActionFolder,
                icon: Icons.folder_open_outlined,
                variant: AppleButtonVariant.pearl,
                onPressed: _pickFolder,
              ),
              if (_s.scanRoots.isNotEmpty) ...[
                const SizedBox(width: AppleSpacing.xxs),
                AppleButton(
                  label: context.l10n.scanActionHome,
                  icon: Icons.home_outlined,
                  variant: AppleButtonVariant.pearl,
                  onPressed: () async {
                    setState(() => _scanStatus = null);
                    await _s.switchScanRoot(null);
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: AppleSpacing.xxs),
          ScanFilterBar(
            categoryFilter: _categoryFilter,
            onCategoryChanged: (cat) {
              setState(() {
                _categoryFilter = cat;
                _resetColumnNav();
              });
            },
            sortMode: _sort,
            onSortChanged: (mode) {
              // Sort is applied at render time by ScanColumnView — no isolate,
              // no tree copy, zero latency.
              setState(() => _sort = mode);
            },
            scanning: _s.scanning,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(
        AppleSpacing.lg,
        AppleSpacing.xxs,
        AppleSpacing.lg,
        AppleSpacing.xxs,
      ),
    );
  }

  String _compactResultsSummary(ScanTreeNode? displayTree, int matchingCount) {
    final snap = _s.lastSnapshot;
    final reclaimable = snap?.reclaimableEstimateBytes;
    final l10n = context.l10n;
    final parts = <String>[];
    if (displayTree != null) {
      parts.add(_formatTreeSummary(displayTree));
    }
    parts.add(l10n.resultsClassifiedCount(matchingCount));
    if (reclaimable != null) {
      parts.add(l10n.resultsReclaimableBytes(_fmt(reclaimable)));
    }
    return parts.join(' · ');
  }

  Widget _buildResultsBrowser(
    BuildContext context,
    ScanTreeNode? displayTree,
    int matchingCount,
  ) {
    final v = context.volward;
    if (displayTree == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: v.canvas,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(color: v.hairline),
        ),
        child: Center(
          child: Text(
            _s.scanning
                ? context.l10n.resultsUpdating
                : matchingCount == 0
                    ? context.l10n.resultsNoFilterMatches
                    : context.l10n
                        .resultsNoFilterMatchesWithCount(matchingCount),
            style: context.vwFinePrint,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // When the catalog index API is available, the old tree's children may be
    // empty even though Rust has real results (e.g. after a catalog-only
    // refresh, or for a root that was built from a preview stub).  Skip the
    // empty-tree short-circuit in that case and let _visibleChildrenFor schedule
    // the appropriate cached query outside the build pass.
    final treeChildrenEmpty = displayTree.children.isEmpty;
    final rootKey = _visibleChildrenKeyFor(displayTree);
    final cachedRootChildren = _visibleChildrenCache.peek(rootKey) ??
        _visibleChildrenCache.latestForPath(displayTree.path);
    final catalogQueryPending =
        _pendingVisibleChildrenQueries.contains(rootKey);
    if (_s.hasIndexApi && cachedRootChildren == null && !catalogQueryPending) {
      _scheduleVisibleChildrenQuery(
        rootKey,
        displayTree,
        preferTree: _shouldUseTreeChildrenFor(displayTree),
      );
    }
    // Only skip the empty-state when the catalog API is present and the root is
    // either already cached, still pending, or still scanning.  For old builds
    // or genuinely empty directories, the friendly empty-state is still shown.
    final catalogMayHaveChildren = _s.hasIndexApi &&
        (catalogQueryPending ||
            cachedRootChildren?.isNotEmpty == true ||
            _s.scanning);
    if (treeChildrenEmpty && !catalogMayHaveChildren) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: v.canvas,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(color: v.hairline),
        ),
        child: Center(
          child: Text(
            context.l10n.resultsNoFilesUnder(displayTree.path),
            style: context.vwFinePrint,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ScanColumnView(
      root: displayTree,
      visibleChildren: _visibleChildrenFor(displayTree),
      visibleChildrenByPath: {
        for (final node in _columnChain) node.path: _visibleChildrenFor(node),
      },
      loadingChildrenPaths: {
        if (_isPreparingVisibleChildren(displayTree)) displayTree.path,
        for (final node in _columnChain)
          if (_isPreparingVisibleChildren(node)) node.path,
      },
      childrenPreSorted: _s.hasIndexApi &&
          !_showingPreviewSnapshot &&
          _categoryFilter == null &&
          !_deletableOnly,
      selectionChain: List.unmodifiable(_columnChain),
      onSelect: _onColumnSelect,
      formatBytes: _fmt,
      selectedEntryIds: Set.unmodifiable(_selected),
      peekInFlight: _s.peekInFlight,
      busy: _s.deleting || _s.scanning,
      sortMode: _sort,
      categoryFilter: _categoryFilter,
      deletableOnly: _deletableOnly,
    );
  }

  @override
  Widget build(BuildContext context) {
    final restoring = _s.restoringSnapshot;
    final snapshotMatchesCurrentRoot = _snapshotMatchesCurrentRoot();
    final loadingTarget =
        _s.targetPreviewLoading || (_s.scanning && !snapshotMatchesCurrentRoot);
    final hasResults = !restoring &&
        !loadingTarget &&
        _s.lastSnapshot != null &&
        snapshotMatchesCurrentRoot;
    final displayTree = hasResults ? _resolveResultTree() : null;
    final matchingCount = hasResults ? _matchingEntryCount() : 0;

    return Scaffold(
      backgroundColor: context.volward.canvasParchment,
      body: Column(
        children: [
          _buildTopNav(context),
          Expanded(
            child: restoring || loadingTarget
                ? _buildRestoreLoading(
                    context,
                    label: restoring
                        ? context.l10n.resultsRestoringPreviousScan
                        : context.l10n.scanColumnPreparingFolder,
                  )
                : hasResults
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildCompactResultsChrome(
                            context,
                            matchingCount: matchingCount,
                            displayTree: displayTree,
                          ),
                          Expanded(
                            child: ListenableBuilder(
                              listenable: _columnNavTick,
                              builder: (context, _) {
                                final focus = scanColumnFocusNode(_columnChain);
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: _padExpanded(
                                        _buildResultsBrowser(
                                          context,
                                          displayTree,
                                          matchingCount,
                                        ),
                                        padding: const EdgeInsets.fromLTRB(
                                          AppleSpacing.lg,
                                          0,
                                          AppleSpacing.lg,
                                          AppleSpacing.xxs,
                                        ),
                                      ),
                                    ),
                                    _buildItemPreview(context, focus),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      )
                    : CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(child: _buildScanSection(context)),
                          const SliverToBoxAdapter(child: SizedBox(height: 72)),
                        ],
                      ),
          ),
          _buildStickyBar(context),
        ],
      ),
    );
  }

  Widget _buildRestoreLoading(BuildContext context, {required String label}) {
    final v = context.volward;
    Widget skeletonBar(
      double width, {
      double height = 10,
      double radius = AppleRadius.sm,
    }) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: v.inkMuted48.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: SizedBox(width: width, height: height),
      );
    }

    Widget skeletonIcon(IconData icon, {Color? color}) {
      return SizedBox(
        width: 20,
        height: 20,
        child: Icon(
          icon,
          size: 18,
          color: color ?? v.inkMuted48.withValues(alpha: 0.44),
        ),
      );
    }

    Widget skeletonChip(double width) {
      return skeletonBar(width, height: 24, radius: AppleRadius.pill);
    }

    Widget skeletonToolbar() {
      return _pad(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: v.primary,
                  ),
                ),
                const SizedBox(width: AppleSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: context.vwFinePrintInk),
                      const SizedBox(height: 4),
                      skeletonBar(280, height: 8),
                    ],
                  ),
                ),
                const SizedBox(width: AppleSpacing.xs),
                skeletonBar(44, height: 12),
                const SizedBox(width: AppleSpacing.xs),
                skeletonChip(82),
                const SizedBox(width: AppleSpacing.xxs),
                skeletonChip(62),
              ],
            ),
            const SizedBox(height: AppleSpacing.xxs),
            DecoratedBox(
              decoration: BoxDecoration(
                color: v.surfacePearl,
                borderRadius: BorderRadius.circular(AppleRadius.sm),
                border: Border.all(color: v.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppleSpacing.sm,
                  vertical: AppleSpacing.xxs,
                ),
                child: SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      skeletonChip(48),
                      const SizedBox(width: AppleSpacing.xxs),
                      skeletonChip(62),
                      const SizedBox(width: AppleSpacing.xxs),
                      skeletonChip(56),
                      const SizedBox(width: AppleSpacing.xxs),
                      skeletonChip(64),
                      const SizedBox(width: AppleSpacing.xxs),
                      skeletonChip(68),
                      const Spacer(),
                      skeletonChip(92),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppleSpacing.xxs),
            ClipRRect(
              borderRadius: const BorderRadius.all(
                Radius.circular(AppleRadius.pill),
              ),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: v.primary,
                backgroundColor: v.hairline,
              ),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(
          AppleSpacing.lg,
          AppleSpacing.xxs,
          AppleSpacing.lg,
          AppleSpacing.xxs,
        ),
      );
    }

    Widget skeletonColumn({required double width, required int rows}) {
      return Container(
        width: width,
        decoration: BoxDecoration(
          color: v.canvas,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(color: v.hairline),
        ),
        padding: const EdgeInsets.all(AppleSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            skeletonBar(width * 0.55, height: 12),
            const SizedBox(height: AppleSpacing.sm),
            for (var i = 0; i < rows; i++) ...[
              Row(
                children: [
                  skeletonIcon(
                    Icons.folder_outlined,
                    color: v.folderIcon.withValues(alpha: 0.42),
                  ),
                  const SizedBox(width: AppleSpacing.xs),
                  Expanded(child: skeletonBar(width * (0.38 + (i % 4) * 0.09))),
                  const SizedBox(width: AppleSpacing.xs),
                  skeletonBar(34 + (i % 3) * 12, height: 8),
                ],
              ),
              if (i != rows - 1) const SizedBox(height: AppleSpacing.sm),
            ],
          ],
        ),
      );
    }

    Widget skeletonBrowser() {
      return _padExpanded(
        LayoutBuilder(
          builder: (context, constraints) {
            final browserHeight =
                constraints.maxHeight.isFinite && constraints.maxHeight > 0
                    ? constraints.maxHeight
                    : 360.0;

            int rowsFor(int target) {
              const rowHeight = 20.0;
              const chromeHeight =
                  AppleSpacing.sm * 2 + 12 + AppleSpacing.sm + 16;
              final available = browserHeight - chromeHeight;
              final maxRows = ((available + AppleSpacing.sm) /
                      (rowHeight + AppleSpacing.sm))
                  .floor()
                  .clamp(3, 8);
              return target < maxRows ? target : maxRows;
            }

            return DecoratedBox(
              decoration: BoxDecoration(
                color: v.canvasParchment,
                borderRadius: BorderRadius.circular(AppleRadius.sm),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    skeletonColumn(width: 220, rows: rowsFor(7)),
                    const SizedBox(width: AppleSpacing.xs),
                    skeletonColumn(width: 220, rows: rowsFor(6)),
                    const SizedBox(width: AppleSpacing.xs),
                    skeletonColumn(width: 220, rows: rowsFor(5)),
                    const SizedBox(width: AppleSpacing.xs),
                    skeletonColumn(width: 220, rows: rowsFor(4)),
                  ],
                ),
              ),
            );
          },
        ),
        padding: const EdgeInsets.fromLTRB(
          AppleSpacing.lg,
          0,
          AppleSpacing.lg,
          AppleSpacing.xxs,
        ),
      );
    }

    Widget skeletonPreview() {
      return _pad(
        Material(
          color: v.canvas,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppleRadius.sm),
            side: BorderSide(color: v.hairline),
          ),
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppleSpacing.sm),
              child: Row(
                children: [
                  skeletonIcon(Icons.insert_drive_file_outlined),
                  const SizedBox(width: AppleSpacing.xs),
                  Expanded(child: skeletonBar(220, height: 10)),
                  const SizedBox(width: AppleSpacing.sm),
                  skeletonBar(88, height: 10),
                  const SizedBox(width: AppleSpacing.sm),
                  skeletonChip(96),
                ],
              ),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppleSpacing.lg,
          0,
          AppleSpacing.lg,
          AppleSpacing.xxs,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        skeletonToolbar(),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: skeletonBrowser()),
              skeletonPreview(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopNav(BuildContext context) {
    final v = context.volward;
    return Container(
      height: 36,
      color: v.surfaceBlack,
      padding: const EdgeInsets.symmetric(horizontal: AppleSpacing.md),
      child: Row(
        children: [
          const VolwardLogoMark(size: 20),
          const SizedBox(width: AppleSpacing.sm),
          Text(
            'Volward',
            style: AppleTypography.navLink.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.12,
              color: v.bodyOnDark,
            ),
          ),
          const SizedBox(width: AppleSpacing.sm),
          Text('·', style: context.vwNavLinkMuted),
          const SizedBox(width: AppleSpacing.sm),
          Text(context.l10n.navSubtitle, style: context.vwNavLinkMuted),
          const Spacer(),
          IconButton(
            tooltip: context.l10n.settingsTooltip,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.settings_outlined, size: 18, color: v.bodyMuted),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(
                    themeSettings: widget.themeSettings,
                    session: _s,
                    deletableOnly: _deletableOnly,
                    onDeletableOnlyChanged: (value) {
                      setState(() {
                        _deletableOnly = value;
                        _resetColumnNav();
                      });
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionBanner(BuildContext context) {
    final v = context.volward;
    final l10n = context.l10n;
    if (!_s.ready) {
      return Row(
        children: [
          Icon(Icons.hourglass_empty, size: 14, color: v.inkMuted48),
          const SizedBox(width: AppleSpacing.xxs),
          Expanded(
            child: Text(
              _s.initError ?? l10n.stickyLoadingEngine,
              style: context.vwFinePrint,
            ),
          ),
        ],
      );
    }

    if (!_s.hasSnapshotFileApi) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppleSpacing.sm),
        decoration: BoxDecoration(
          color: v.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(color: v.danger.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.permissionNativeOutdatedTitle,
              style: context.vwCaptionStrong,
            ),
            const SizedBox(height: AppleSpacing.xxs),
            Text(
              l10n.permissionNativeOutdatedDescription,
              style: context.vwFinePrint,
            ),
          ],
        ),
      );
    }

    if (_s.deepScanReady) {
      return const SizedBox.shrink();
    }

    if (!_permissionBannerExpanded) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 14, color: v.warning),
          const SizedBox(width: AppleSpacing.xxs),
          Expanded(
            child: Text(
              l10n.permissionFullDiskRecommended,
              style: context.vwFinePrint,
            ),
          ),
          AppleButton(
            label: l10n.permissionOpenSettings,
            icon: Icons.open_in_new,
            variant: AppleButtonVariant.secondary,
            onPressed: _openFullDiskAccessSettings,
          ),
          IconButton(
            icon: Icon(Icons.expand_more, size: 18, color: v.inkMuted80),
            tooltip: l10n.permissionShowDetails,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => setState(() => _permissionBannerExpanded = true),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppleSpacing.sm),
      decoration: BoxDecoration(
        color: v.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        border: Border.all(color: v.warning.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.permissionFullDiskRecommendedTitle,
                  style: context.vwCaptionStrong,
                ),
              ),
              IconButton(
                icon: Icon(Icons.expand_less, size: 18, color: v.inkMuted80),
                tooltip: l10n.permissionHideDetails,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () =>
                    setState(() => _permissionBannerExpanded = false),
              ),
            ],
          ),
          const SizedBox(height: AppleSpacing.xxs),
          Text(l10n.permissionFullDiskInstructions, style: context.vwFinePrint),
          if (MacosSettings.appBundlePath() case final path?) ...[
            const SizedBox(height: AppleSpacing.xxs),
            Text(
              l10n.permissionAppPath(path),
              style: context.vwFinePrint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppleSpacing.sm),
          Wrap(
            spacing: AppleSpacing.xs,
            runSpacing: AppleSpacing.xs,
            children: [
              AppleButton(
                label: l10n.permissionOpenSettings,
                icon: Icons.open_in_new,
                variant: AppleButtonVariant.secondary,
                onPressed: _openFullDiskAccessSettings,
              ),
              AppleButton(
                label: l10n.permissionCopyAppPath,
                icon: Icons.copy,
                variant: AppleButtonVariant.pearl,
                onPressed: _copyAppBundlePath,
              ),
              AppleButton(
                label: l10n.permissionCheckAgain,
                icon: Icons.refresh,
                variant: AppleButtonVariant.pearl,
                onPressed: _s.refreshCapabilities,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanSection(BuildContext context) {
    final v = context.volward;
    final l10n = context.l10n;
    final showPermission =
        !_s.ready || !_s.hasSnapshotFileApi || !_s.deepScanReady;
    return _pad(
      AppleUtilityCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showPermission) ...[
              _buildPermissionBanner(context),
              const SizedBox(height: AppleSpacing.sm),
              Divider(height: 1, color: v.hairline),
              const SizedBox(height: AppleSpacing.sm),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.scanTargetTitle,
                        style: context.vwCaptionStrong,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _scanTargetLabel(context),
                        style: context.vwCaption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppleSpacing.sm),
                Wrap(
                  spacing: AppleSpacing.xs,
                  runSpacing: AppleSpacing.xs,
                  alignment: WrapAlignment.end,
                  children: [
                    AppleButton(
                      label: l10n.scanActionFolder,
                      icon: Icons.folder_open_outlined,
                      variant: AppleButtonVariant.secondary,
                      onPressed: _pickFolder,
                    ),
                    if (_s.scanRoots.isNotEmpty)
                      AppleButton(
                        label: l10n.scanActionHome,
                        icon: Icons.home_outlined,
                        variant: AppleButtonVariant.pearl,
                        onPressed: () async {
                          setState(() => _scanStatus = null);
                          await _s.switchScanRoot(null);
                        },
                      ),
                    if (_s.scanning)
                      AppleButton(
                        label: l10n.scanActionCancel,
                        icon: Icons.stop_outlined,
                        variant: AppleButtonVariant.darkUtility,
                        onPressed: _s.cancelScan,
                      ),
                  ],
                ),
              ],
            ),
            if (_s.scanning) ...[
              const SizedBox(height: AppleSpacing.sm),
              ValueListenableBuilder<double?>(
                valueListenable: _s.scannedFractionNotifier,
                builder: (context, frac, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(AppleRadius.pill),
                        ),
                        child: LinearProgressIndicator(
                          value: frac,
                          minHeight: 3,
                        ),
                      ),
                      const SizedBox(height: AppleSpacing.xxs),
                      ValueListenableBuilder<String?>(
                        valueListenable: _s.scanElapsedNotifier,
                        builder: (context, _, __) {
                          return Text(
                            _scanProgressSummary(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.vwFinePrint,
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
              if (_s.scanRoots.isEmpty) ...[
                const SizedBox(height: AppleSpacing.xxs),
                Text(l10n.scanHomeLongRunningHint, style: context.vwFinePrint),
              ],
            ] else if (_scanStatus != null) ...[
              const SizedBox(height: AppleSpacing.xxs),
              Text(_scanStatus!, style: context.vwFinePrint),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTreeSummary(ScanTreeNode tree) {
    final filesSeen = _s.lastSnapshot?.stats['files_seen'] as num?;
    final count = filesSeen?.toInt() ?? tree.subtreeFileCount ?? tree.fileCount;
    return context.l10n.resultsTreeSummary(count, _fmt(tree.displayBytes));
  }

  Widget _buildItemPreview(BuildContext context, ScanTreeNode? focus) {
    final v = context.volward;
    final l10n = context.l10n;
    if (focus == null) {
      return _pad(
        Material(
          color: v.canvas,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppleRadius.sm),
            side: BorderSide(color: v.hairline),
          ),
          child: SizedBox(
            height: 36,
            child: Center(
              child: Text(l10n.previewSelectPrompt, style: context.vwFinePrint),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppleSpacing.lg,
          0,
          AppleSpacing.lg,
          AppleSpacing.xxs,
        ),
      );
    }

    final isDir = focus.isDirectory;
    final size = isDir ? focus.displayBytes : focus.sizeBytes;
    final subtreeItems = isDir ? focus.fileCount : 0;
    final category = isDir ? l10n.previewFolderCategory : focus.category;
    final entryId = focus.entryId;
    final marked = entryId != null && _selected.contains(entryId);
    final busy = _s.deleting || _s.scanning;

    return _pad(
      Material(
        color: v.canvas,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          side: BorderSide(color: v.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppleSpacing.sm,
              vertical: AppleSpacing.xxs,
            ),
            child: Row(
              children: [
                Icon(
                  isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                  size: 22,
                  color: isDir ? v.folderIcon : v.inkMuted48,
                ),
                const SizedBox(width: AppleSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        focus.name,
                        style: context.vwCaptionStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${isDir && !focus.scanned ? '—' : _fmt(size)} · $category'
                        '${isDir ? ' · ${l10n.previewItemCount(subtreeItems)}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.vwFinePrint,
                      ),
                    ],
                  ),
                ),
                if (!isDir && entryId != null && category != 'System')
                  Checkbox(
                    value: marked,
                    onChanged:
                        busy ? null : (_) => _toggleFocusedFileSelection(focus),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppleSpacing.lg,
        0,
        AppleSpacing.lg,
        AppleSpacing.xxs,
      ),
    );
  }

  Widget _buildStickyBar(BuildContext context) {
    final busy = _s.deleting || _s.scanning;
    final deleteTargetCount = _deleteTargetCount();
    final deleteTargetBytes = _deleteTargetBytes();
    final l10n = context.l10n;
    final String label;
    final String actionLabel;
    final VoidCallback? actionPressed;
    final IconData? actionIcon;

    if (_s.scanning) {
      // Elapsed ticks via scanElapsedNotifier below; the label is built there.
      label = '';
      actionLabel = l10n.scanActionCancel;
      actionIcon = Icons.stop_outlined;
      actionPressed = _s.cancelScan;
    } else {
      final hasResults = _s.lastSnapshot != null;
      final peekCount = _s.peekInFlight.length;
      if (hasResults) {
        label = deleteTargetCount > 0
            ? l10n.stickySelected(deleteTargetCount, _fmt(deleteTargetBytes))
            : peekCount > 0
                ? l10n.stickyDirectoriesLoading(peekCount)
                : l10n.stickyBrowseResults;
        // Refresh button targets the currently focused directory (Design §6.2).
        // This is a catalog re-query — no file-system scan is started.
        actionLabel = busy ? '' : l10n.scanActionRescan;
        actionIcon = busy ? null : Icons.refresh_outlined;
        actionPressed = (busy || !_s.ready || !_s.hasSnapshotFileApi)
            ? null
            : () => unawaited(_s.refreshCurrentDirectory());
      } else {
        label = _s.ready ? l10n.stickyReadyToScan : l10n.stickyLoadingEngine;
        actionLabel = l10n.scanActionStart;
        actionIcon = Icons.search;
        actionPressed =
            (_s.ready && !busy && _s.hasSnapshotFileApi) ? _startScan : null;
      }
    }

    // During a scan, progress % arrives via scannedFractionNotifier (deferred
    // tree walk) and elapsed via scanElapsedNotifier (1 Hz) — wrap both so the
    // sticky label updates without rebuilding the whole page.
    final Widget leading = _s.scanning
        ? ValueListenableBuilder<double?>(
            valueListenable: _s.scannedFractionNotifier,
            builder: (context, _, __) {
              return ValueListenableBuilder<String?>(
                valueListenable: _s.scanElapsedNotifier,
                builder: (context, _, __) =>
                    Text(_scanProgressSummary(), style: context.vwCaption),
              );
            },
          )
        : Text(label, style: context.vwCaption);

    return AppleStickyBar(
      leading: leading,
      action: (_s.scanning || _s.lastSnapshot == null)
          ? AppleButton(
              label: actionLabel,
              icon: actionIcon,
              onPressed: actionPressed,
            )
          : Wrap(
              alignment: WrapAlignment.end,
              spacing: AppleSpacing.xs,
              runSpacing: AppleSpacing.xs,
              children: [
                AppleButton(
                  label: l10n.trashActionEmpty,
                  icon: Icons.delete_sweep_outlined,
                  variant: AppleButtonVariant.pearl,
                  onPressed: busy ? null : _confirmEmptyTrash,
                ),
                AppleButton(
                  label: busy
                      ? l10n.deleteActionWorking
                      : l10n.deleteActionMoveToTrash,
                  icon: busy ? null : Icons.delete_outline,
                  onPressed:
                      deleteTargetCount > 0 && !busy ? _confirmDelete : null,
                ),
              ],
            ),
    );
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
