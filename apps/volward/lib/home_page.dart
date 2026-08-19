import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'l10n/l10n.dart';
import 'macos_settings.dart';
import 'scan_entry_record.dart';
import 'scan_tree.dart';
import 'storage_home_summary.dart';
import 'storage_overview.dart';
import 'storage_overview_provider.dart';
import 'theme/apple_tokens.dart';
import 'settings_page.dart';
import 'theme/volward_theme_settings.dart';
import 'theme/volward_tokens.dart';
import 'updater/app_updater.dart';
import 'updater/update_models.dart';
import 'volward_session.dart';
import 'widgets/apple_widgets.dart';
import 'widgets/volward_logo.dart';
import 'widgets/scan_column_view.dart';
import 'widgets/scan_filter_bar.dart';
import 'scan_tree_navigation.dart';
import 'snapshot_catalog.dart';
import 'snapshot_query.dart';
import 'snapshot_view_cache.dart';
import 'widgets/storage_steward_home.dart';
import 'widgets/top_toast.dart';
import 'widgets/update_available_dialog.dart';

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
  return parentFsPath(path);
}

String refreshPathForDeleteTargets({
  required String fallbackPath,
  required Iterable<String> targetPaths,
}) {
  final parentPaths = targetPaths
      .where((path) => path.isNotEmpty)
      .map(_parentPathOf)
      .toSet();
  if (parentPaths.length == 1) return parentPaths.single;
  return ScanTreeBuilder.normalizeRoot(fallbackPath);
}

enum _HomeContentMode { home, browse }

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.session,
    required this.themeSettings,
    required this.updater,
    this.directoryPicker,
    this.storageOverviewProvider = const MethodChannelStorageOverviewProvider(),
  });
  final VolwardSession session;
  final VolwardThemeSettings themeSettings;
  final AppUpdater updater;
  final Future<String?> Function({required String confirmButtonText})?
  directoryPicker;
  final StorageOverviewProvider storageOverviewProvider;

  static const logoKey = Key('volward-top-nav-home');
  static const browseFolderActionKey = Key('volward-browse-folder-action');
  static const browseHomeActionKey = Key('volward-browse-home-action');

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
  final Map<String, String> _selectedPaths = {};
  final List<ScanTreeNode> _columnChain = [];
  String? _selectionAnchorPath;
  int? _selectionAnchorColumnIndex;
  final ValueNotifier<int> _columnNavTick = ValueNotifier(0);
  bool _prevScanning = false;
  bool _lastDeleting = false;
  int _lastRefreshingDirectoryCount = 0;
  bool _permissionBannerExpanded = false;
  // Tracks the last `_lastSnapshot.snapshotId` we already observed, so plain
  // progress ticks do not trigger a full page rebuild while browsing during a
  // background scan.
  String? _lastRefreshedSnapshotId;
  // Tracks the last catalog version so refreshCurrentDirectory() (which does
  // not change snapshotId) still triggers a rebuild via setState.
  int _lastRefreshedCatalogVersion = -1;
  bool _lastTargetPreviewLoading = false;
  bool _hasValidRoot = false;
  _HomeContentMode _contentMode = _HomeContentMode.home;
  Completer<bool> _startupRootGate = Completer<bool>();
  StorageOverviewData _storageOverview = const StorageOverviewData.loading();
  String? _homeTargetPath;
  List<StorageLocationInfo> _recentCustomLocations = const [];
  int _overviewLoadGeneration = 0;
  late VolwardSession _subscribedSession;
  int _sessionGeneration = 0;
  VolwardSession? _startupPendingSession;
  int? _startupPendingGeneration;
  bool _scanStartPending = false;
  bool _targetPreparationPending = false;
  int _scanStartGeneration = 0;

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
  List<ScanTreeNode> _largestItemCandidates = const [];
  String? _largestItemsCacheKey;

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
    _subscribedSession = widget.session;
    _subscribedSession.addListener(_onSessionChanged);
    _scheduleSessionStartup(_subscribedSession);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeCheckForUpdates());
    });
  }

  void _scheduleSessionStartup(VolwardSession session) {
    final generation = ++_sessionGeneration;
    final gate = _startupRootGate;
    _startupPendingSession = session;
    _startupPendingGeneration = generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runSessionStartup(session, generation, gate));
    });
  }

  Future<void> _runSessionStartup(
    VolwardSession session,
    int generation,
    Completer<bool> gate,
  ) async {
    try {
      // Preview-first startup: lightweight session state + a validated launch
      // root render immediately, without waiting for the full snapshot/index
      // restore to complete (that restore continues in the background).
      await session.loadSessionStateIfNeeded();
      if (!_isCurrentSession(session, generation)) return;
      final launchRoot = await session.resolveStartupRoot();
      if (!_isCurrentSession(session, generation)) return;

      setState(() {
        _hasValidRoot = launchRoot.isNotEmpty;
        _homeTargetPath = launchRoot;
      });
      unawaited(
        _loadStorageOverview(
          launchRoot,
          expectedSession: session,
          expectedSessionGeneration: generation,
        ),
      );
      if (identical(gate, _startupRootGate) && !gate.isCompleted) {
        gate.complete(true);
      }

      if (launchRoot.isNotEmpty) {
        if (session.refreshTargetPath != launchRoot) {
          session.setScanRoots([launchRoot]);
        }
        final previewGeneration = session.rootSwitchGeneration;
        await session.previewTarget(expectedGeneration: previewGeneration);
        if (!_isCurrentSession(session, generation)) return;
      }

      _restoreCachedSnapshotInBackground(session, generation);
    } catch (error, stackTrace) {
      if (_isCurrentSession(session, generation)) {
        debugPrint('HomePage startup failed: $error\n$stackTrace');
      }
    } finally {
      _finishSessionStartup(session, generation, gate);
    }
  }

  bool _isCurrentSession(VolwardSession session, int generation) {
    return mounted &&
        identical(_subscribedSession, session) &&
        generation == _sessionGeneration;
  }

  bool _isStartupPendingFor(VolwardSession session) {
    return identical(_startupPendingSession, session) &&
        _startupPendingGeneration == _sessionGeneration;
  }

  bool get _startupPending => _isStartupPendingFor(_subscribedSession);

  void _finishSessionStartup(
    VolwardSession session,
    int generation,
    Completer<bool> gate,
  ) {
    if (!_isCurrentSession(session, generation)) return;
    if (identical(gate, _startupRootGate) && !gate.isCompleted) {
      gate.complete(true);
    }
    if (!identical(_startupPendingSession, session) ||
        _startupPendingGeneration != generation) {
      return;
    }
    _startupPendingSession = null;
    _startupPendingGeneration = null;
    setState(() {});
  }

  Future<void> _restoreCachedSnapshotInBackground(
    VolwardSession session,
    int generation,
  ) async {
    try {
      await session.restoreCachedSnapshotIfNeeded();
    } catch (error, stackTrace) {
      if (_isCurrentSession(session, generation)) {
        debugPrint(
          'HomePage cached snapshot restore failed: $error\n$stackTrace',
        );
      }
      return;
    }
    if (!_isCurrentSession(session, generation)) return;
    setState(() {
      _invalidateSnapshotCachesForSessionUpdate();
      _lastRefreshedSnapshotId = session.lastSnapshot?.snapshotId;
      _lastRefreshedCatalogVersion = session.catalogVersion;
      _syncRecentCustomLocations();
    });
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sessionChanged = !identical(oldWidget.session, widget.session);
    final providerChanged = !identical(
      oldWidget.storageOverviewProvider,
      widget.storageOverviewProvider,
    );
    if (!sessionChanged && !providerChanged) return;

    if (sessionChanged) {
      _subscribedSession.removeListener(_onSessionChanged);
      _subscribedSession = widget.session;
      _subscribedSession.addListener(_onSessionChanged);
      _sessionGeneration++;
      _scanStartGeneration++;
      _scanStartPending = false;
      _targetPreparationPending = false;
      _scanStatus = null;
      _selected.clear();
      _selectedSizes.clear();
      _selectedPaths.clear();
      _selectionAnchorPath = null;
      _selectionAnchorColumnIndex = null;
      _columnChain.clear();
      _columnNavTick.value++;
      _invalidateSnapshotCaches();
      _lastRefreshedSnapshotId = _s.lastSnapshot?.snapshotId;
      _lastRefreshedCatalogVersion = _s.catalogVersion;
      _lastDeleting = _s.deleting;
      _lastRefreshingDirectoryCount = _s.refreshingDirectoryPaths.length;
      _lastTargetPreviewLoading = _s.targetPreviewLoading;
      _prevScanning = _s.scanning;
      _homeTargetPath = null;
      _recentCustomLocations = const [];
      _hasValidRoot = false;
      if (!_startupRootGate.isCompleted) {
        _startupRootGate.complete(false);
      }
      _startupRootGate = Completer<bool>();
      unawaited(_s.refreshCapabilities());
      _overviewLoadGeneration++;
      _storageOverview = const StorageOverviewData.loading();
      _scheduleSessionStartup(_subscribedSession);
      return;
    }

    _overviewLoadGeneration++;
    _storageOverview = const StorageOverviewData.loading();
    if (_startupRootGate.isCompleted) {
      unawaited(_loadStorageOverview(_homeTargetPath ?? _scanRootPath()));
    }
  }

  Future<void> _maybeCheckForUpdates() async {
    await widget.updater.check(userInitiated: false);
    if (!mounted) return;
    if (widget.updater.shouldPromptOnStartup) {
      await showUpdateAvailableDialog(
        context: context,
        updater: widget.updater,
      );
      return;
    }
    final status = widget.updater.status;
    if (status.phase == UpdatePhase.error &&
        (status.failureKind == UpdateFailureKind.noMatchingAsset ||
            status.failureKind == UpdateFailureKind.integrity ||
            status.failureKind == UpdateFailureKind.unsupportedRuntime)) {
      await showUpdateFailureDialog(context: context, updater: widget.updater);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionGeneration++;
    _overviewLoadGeneration++;
    _scanStartGeneration++;
    _scanStartPending = false;
    _targetPreparationPending = false;
    _startupPendingSession = null;
    _startupPendingGeneration = null;
    if (!_startupRootGate.isCompleted) {
      _startupRootGate.complete(false);
    }
    _subscribedSession.removeListener(_onSessionChanged);
    _columnNavTick.dispose();
    _pendingVisibleChildrenQueries.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _s.refreshCapabilities();
      if (_startupRootGate.isCompleted) {
        unawaited(_loadStorageOverview(_homeTargetPath ?? _scanRootPath()));
      }
    }
  }

  Future<void> _loadStorageOverview(
    String? selectedPath, {
    VolwardSession? expectedSession,
    int? expectedSessionGeneration,
  }) async {
    final generation = ++_overviewLoadGeneration;
    final provider = widget.storageOverviewProvider;
    bool isCurrentRequest() {
      return mounted &&
          generation == _overviewLoadGeneration &&
          (expectedSession == null ||
              identical(expectedSession, _subscribedSession)) &&
          (expectedSessionGeneration == null ||
              expectedSessionGeneration == _sessionGeneration) &&
          identical(provider, widget.storageOverviewProvider);
    }

    if (selectedPath == null || selectedPath.isEmpty) {
      if (isCurrentRequest()) {
        setState(
          () => _storageOverview = const StorageOverviewData.unavailable(
            'missing-root',
          ),
        );
      }
      return;
    }
    final data = await provider.load(selectedPath: selectedPath);
    if (!isCurrentRequest()) return;
    setState(() {
      _storageOverview = data;
      _syncRecentCustomLocations();
    });
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
    final deletingChanged = _lastDeleting != _s.deleting;
    _lastDeleting = _s.deleting;
    final refreshingDirectoryCount = _s.refreshingDirectoryPaths.length;
    final refreshingChanged =
        _lastRefreshingDirectoryCount != refreshingDirectoryCount;
    _lastRefreshingDirectoryCount = refreshingDirectoryCount;
    final targetPreviewChanged =
        _lastTargetPreviewLoading != _s.targetPreviewLoading;
    _lastTargetPreviewLoading = _s.targetPreviewLoading;

    if (targetPreviewChanged && _s.targetPreviewLoading) {
      setState(() {
        _selected.clear();
        _selectedSizes.clear();
        _selectedPaths.clear();
        _selectionAnchorPath = null;
        _selectionAnchorColumnIndex = null;
        _scanStatus = null;
        _columnChain.clear();
        _columnNavTick.value++;
        _invalidateSnapshotCaches();
        _lastRefreshedSnapshotId = null;
        _lastRefreshedCatalogVersion = _s.catalogVersion;
      });
    } else if (!_prevScanning && _s.scanning) {
      setState(() {
        // Scan now owns the busy state; don't keep Start disabled after Stop.
        _scanStartPending = false;
        _scanStatus = null;
        _invalidateSnapshotCaches();
        _lastRefreshedSnapshotId = _s.lastSnapshot?.snapshotId;
        if (_contentMode != _HomeContentMode.home) {
          _selected.clear();
          _selectedSizes.clear();
          _selectedPaths.clear();
          _selectionAnchorPath = null;
          _selectionAnchorColumnIndex = null;
          _columnChain.clear();
          _columnNavTick.value++;
        }
      });
    } else if (_prevScanning && !_s.scanning) {
      // Completed or cancelled — release the start-scan lock even if runScan()
      // is still unwinding (native cancel can lag behind `_scanning = false`).
      final snapshot = _s.lastSnapshot;
      final count = snapshot?.filesInSnapshot ?? 0;
      final l10n = context.l10n;
      final label = _s.incrementalScan
          ? l10n.scanStatusIncremental
          : l10n.scanStatusFull;
      setState(() {
        _scanStartPending = false;
        if (snapshot != null) {
          _scanStatus = l10n.scanStatusFiles(label, count);
          _invalidateSnapshotCaches();
          _lastRefreshedSnapshotId = snapshot.snapshotId;
          if (_contentMode != _HomeContentMode.home) {
            _columnChain.clear();
            _columnNavTick.value++;
            _selectedSizes.clear();
            _selectedPaths.clear();
            _selectionAnchorPath = null;
            _selectionAnchorColumnIndex = null;
          }
        }
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
      final dataChanged = snapChanged || catalogChanged || targetPreviewChanged;
      if (dataChanged || deletingChanged || refreshingChanged) {
        if (dataChanged) {
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
              final chainChanged =
                  refreshed.length != _columnChain.length ||
                  !Iterable.generate(
                    refreshed.length,
                  ).every((i) => refreshed[i].path == _columnChain[i].path);
              if (chainChanged) _setColumnChain(refreshed);
            }
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
    return defaultScanRootPath(
      environment: Platform.environment,
      isWindows: () => Platform.isWindows,
    );
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
    return _snapshotMatchesTarget(_scanRootPath());
  }

  bool _snapshotMatchesTarget(String targetPath) {
    final tree = _s.lastSnapshot?.tree;
    if (tree == null || tree.path.isEmpty) return false;
    return ScanTreeBuilder.normalizeRoot(tree.path) ==
        ScanTreeBuilder.normalizeRoot(targetPath);
  }

  /// Direct children of the scanned target, for the home dashboard's middle
  /// block. `SnapshotCatalog.queryNode` is a synchronous in-memory FFI read,
  /// but `_homeSummary` runs inside `build()` and rebuilds on every scan
  /// progress tick — so memoize on (snapshotId, targetPath).
  List<ScanTreeNode> _largestItemsFor(String targetPath) {
    final snapshot = _s.lastSnapshot;
    final tree = snapshot?.tree;
    if (snapshot == null ||
        tree == null ||
        !_snapshotMatchesTarget(targetPath)) {
      _largestItemsCacheKey = null;
      _largestItemCandidates = const [];
      return const [];
    }
    final cacheKey = '${snapshot.snapshotId}|$targetPath';
    if (cacheKey == _largestItemsCacheKey) return _largestItemCandidates;
    final result = SnapshotCatalog.queryNode(
      key: SnapshotQueryKey(
        snapshotId: snapshot.snapshotId,
        version: _s.catalogVersion,
        path: tree.path,
        categoryFilter: null,
        deletableOnly: false,
        sortMode: ScanSortMode.sizeDesc,
      ),
      node: tree,
      includeEntryRecords: false,
    );
    _largestItemsCacheKey = cacheKey;
    _largestItemCandidates = result.directNodes;
    return _largestItemCandidates;
  }

  void _invalidateSnapshotCaches() {
    _cachedResolvedTree = null;
    _cachedResolvedTreeKey = null;
    _cachedSelectedBytesKey = null;
    _visibleChildrenCache.clear();
    _pendingVisibleChildrenQueries.clear();
    _largestItemsCacheKey = null;
  }

  void _invalidateSnapshotCachesForSessionUpdate() {
    _cachedResolvedTree = null;
    _cachedResolvedTreeKey = null;
    _cachedSelectedBytesKey = null;

    final prefixes = _s.consumeInvalidatedPrefixes();
    if (prefixes.isEmpty) {
      _visibleChildrenCache.clear();
      _pendingVisibleChildrenQueries.clear();
      // Cache key omits catalogVersion, but unconditional invalidation here keeps it safe.
      _largestItemsCacheKey = null;
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
    _largestItemsCacheKey = null;
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

  void _onColumnSelect(ScanColumnTap tap) {
    if (_s.deleting || _s.scanning) return;
    final columnIndex = tap.columnIndex;
    final node = tap.node;
    final currentTree = _resolveResultTree();
    final actualNode =
        _findNodeByPath(currentTree, node.path) ?? node.toScanTreeNode();

    if (tap.commandPressed || tap.shiftPressed) {
      if (actualNode.category == 'System') return;
      if (tap.shiftPressed &&
          _selectionAnchorPath != null &&
          _selectionAnchorColumnIndex == columnIndex) {
        final range = selectColumnRange(
          tap.columnItems,
          anchorPath: _selectionAnchorPath!,
          targetPath: node.path,
        );
        if (range.isNotEmpty) {
          setState(() {
            for (final record in range) {
              final rangeNode =
                  _findNodeByPath(currentTree, record.path) ??
                  record.toScanTreeNode();
              _addNodeSelection(rangeNode);
            }
            _cachedSelectedBytesKey = null;
          });
        }
      } else if (tap.commandPressed) {
        setState(() {
          if (_selected.isEmpty &&
              _selectionAnchorPath != null &&
              _selectionAnchorColumnIndex == columnIndex &&
              _selectionAnchorPath != node.path) {
            SnapshotNodeRecord? anchorRecord;
            for (final record in tap.columnItems) {
              if (record.path == _selectionAnchorPath) {
                anchorRecord = record;
                break;
              }
            }
            if (anchorRecord != null) {
              final anchorNode =
                  _findNodeByPath(currentTree, anchorRecord.path) ??
                  anchorRecord.toScanTreeNode();
              _addNodeSelection(anchorNode);
            }
          }
          _toggleNodeSelection(actualNode);
          _cachedSelectedBytesKey = null;
        });
      }
      if (tap.commandPressed) {
        _selectionAnchorPath = node.path;
        _selectionAnchorColumnIndex = columnIndex;
      }
      return;
    }

    _selectionAnchorPath = node.path;
    _selectionAnchorColumnIndex = columnIndex;
    if (_selected.isNotEmpty) {
      setState(() {
        _selected.clear();
        _selectedSizes.clear();
        _selectedPaths.clear();
        _cachedSelectedBytesKey = null;
      });
    }
    final nextChain = toggleColumnSelection(
      _columnChain,
      columnIndex,
      actualNode,
    );
    setState(() {
      _setColumnChain(nextChain);
    });
    _s.setCurrentDirectory(browsedDirectoryPath(nextChain));
    final remainsSelected =
        nextChain.length > columnIndex &&
        nextChain[columnIndex].path == node.path;
    if (remainsSelected && actualNode.isDirectory && !actualNode.scanned) {
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
    if (_s.directoryOverlayForPath(node.path) != null) return true;
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
    // While a directory is being re-scanned (delete refresh / manual refresh),
    // keep showing the previous children instead of clearing the column — the
    // refreshed overlay replaces them atomically when the peek completes, so
    // the list updates in place without blanking out (the flicker source).
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
    final liveNode =
        _s.directoryOverlayForPath(node.path) ??
        (_shouldUseTreeOverlayForPath(node.path)
            ? (_findNodeByPath(_cachedResolvedTree, node.path) ?? node)
            : node);

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

  bool _isPreparingVisibleChildren(ScanTreeNode node) {
    return _s.isDirectoryRefreshing(node.path) ||
        _s.peekInFlight.contains(node.path) ||
        _pendingVisibleChildrenQueries.contains(_visibleChildrenKeyFor(node));
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
    if (_s.deleting || _s.scanning) return;
    setState(() {
      _toggleNodeSelection(node);
      _cachedSelectedBytesKey = null;
    });
  }

  void _toggleNodeSelection(ScanTreeNode node) {
    if (node.category == 'System') return;
    final id = node.entryId ?? node.path;
    if (id.isEmpty) return;
    if (_selected.contains(id)) {
      _selected.remove(id);
      _selectedSizes.remove(id);
      _selectedPaths.remove(id);
      return;
    }
    _addNodeSelection(node);
  }

  void _addNodeSelection(ScanTreeNode node) {
    if (node.category == 'System') return;
    final id = node.entryId ?? node.path;
    if (id.isEmpty || _selected.contains(id)) return;
    final prefix = '${node.path}/';
    if (_selectedPaths.values.any((path) => node.path.startsWith('$path/'))) {
      return;
    }
    if (node.isDirectory) {
      final childIds = _selectedPaths.entries
          .where((entry) => entry.value.startsWith(prefix))
          .map((entry) => entry.key)
          .toList();
      for (final childId in childIds) {
        _selected.remove(childId);
        _selectedSizes.remove(childId);
        _selectedPaths.remove(childId);
      }
    }
    _selected.add(id);
    _selectedSizes[id] = node.displayBytes;
    _selectedPaths[id] = node.path;
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
    final selectedKey = _selected.isEmpty
        ? ''
        : (_selected.toList()..sort()).join(',');
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

  Future<String?> _chooseFolderPath() {
    final confirm = context.l10n.folderPickerConfirm;
    final picker = widget.directoryPicker;
    return picker != null
        ? picker(confirmButtonText: confirm)
        : getDirectoryPath(confirmButtonText: confirm);
  }

  Future<void> _pickFolder() async {
    final path = await _chooseFolderPath();
    if (path == null) return;
    if (!await _switchToValidatedRoot(path)) return;
    _rememberCustomTarget(ScanTreeBuilder.normalizeRoot(path));
    _synchronizeHomeTarget(
      additionalState: () => _contentMode = _HomeContentMode.browse,
    );
  }

  Future<void> _pickHomeFolder() async {
    final path = await _chooseFolderPath();
    if (path == null) return;
    await _prepareHomeTarget(path);
  }

  bool _isPresetLocationPath(String path) {
    final normalized = ScanTreeBuilder.normalizeRoot(path);
    for (final location in _storageOverview.locations) {
      if (location.kind == StorageLocationKind.volume) continue;
      if (ScanTreeBuilder.normalizeRoot(location.path) == normalized) {
        return true;
      }
    }
    return false;
  }

  StorageLocationInfo _customLocationFor(String path) {
    return StorageLocationInfo(
      id: 'custom:$path',
      name: rootDisplayNameFor(path),
      path: path,
      kind: StorageLocationKind.custom,
      volumeId: _storageOverview.volumeForPath(path)?.id ?? '',
    );
  }

  void _rememberCustomTarget(String path, {bool persist = true}) {
    final normalized = ScanTreeBuilder.normalizeRoot(path);
    if (normalized.isEmpty || _storageOverview.locations.isEmpty) return;
    if (_isPresetLocationPath(normalized)) return;
    final next = _customLocationFor(normalized);
    final unchanged =
        _recentCustomLocations.isNotEmpty &&
        ScanTreeBuilder.normalizeRoot(_recentCustomLocations.first.path) ==
            normalized;
    _recentCustomLocations = [
      next,
      for (final location in _recentCustomLocations)
        if (ScanTreeBuilder.normalizeRoot(location.path) != normalized)
          location,
    ].take(5).toList(growable: false);
    if (persist && !unchanged) {
      _s.rememberCustomRoot(normalized);
    }
  }

  void _syncRecentCustomLocations() {
    _recentCustomLocations = [
      for (final saved in _s.recentCustomRoots)
        if (saved.isNotEmpty && !_isPresetLocationPath(saved))
          _customLocationFor(saved),
    ];
    final current = _homeTargetPath;
    if (current != null && current.isNotEmpty) {
      _rememberCustomTarget(current, persist: false);
    }
  }

  Future<void> _prepareHomeTarget(String path) async {
    if (_s.scanning || _targetPreparationPending) return;
    final session = _s;
    final sessionGeneration = _sessionGeneration;
    _scanStartGeneration++;
    setState(() => _targetPreparationPending = true);
    try {
      final normalized = ScanTreeBuilder.normalizeRoot(path);
      final current = ScanTreeBuilder.normalizeRoot(_scanRootPath());
      if (normalized != current) {
        if (!await _switchToValidatedRoot(normalized, startFullScan: false)) {
          return;
        }
      }
      if (!_isCurrentSession(session, sessionGeneration)) return;
      _rememberCustomTarget(normalized);
      _synchronizeHomeTarget();
    } finally {
      if (_isCurrentSession(session, sessionGeneration)) {
        setState(() => _targetPreparationPending = false);
      }
    }
  }

  Future<bool> _switchToValidatedRoot(
    String path, {
    bool startFullScan = true,
  }) async {
    try {
      await _s.switchScanRoot(
        path,
        startFullScan: startFullScan,
        validateBeforeSwitch: true,
      );
      return mounted;
    } catch (error) {
      if (!mounted) return false;
      showTopToast(
        context,
        message: context.l10n.scanStatusFailed(error.toString()),
        type: ToastType.error,
      );
      return false;
    }
  }

  void _synchronizeHomeTarget({VoidCallback? additionalState}) {
    final target = ScanTreeBuilder.normalizeRoot(_scanRootPath());
    final targetChanged = target != _homeTargetPath;
    if (targetChanged) _overviewLoadGeneration++;
    setState(() {
      if (targetChanged) {
        _storageOverview = const StorageOverviewData.loading();
      }
      _homeTargetPath = target;
      _hasValidRoot = target.isNotEmpty;
      additionalState?.call();
    });
    unawaited(_loadStorageOverview(target));
  }

  Future<void> _switchBrowseToHomeRoot() async {
    setState(() => _scanStatus = null);
    await _s.switchScanRoot(null);
    if (!mounted) return;
    _synchronizeHomeTarget();
  }

  void _showHome() {
    if (_contentMode == _HomeContentMode.home) return;
    setState(() => _contentMode = _HomeContentMode.home);
  }

  Future<void> _waitForStartupRootResolution() async {
    while (mounted) {
      final gate = _startupRootGate;
      final resolved = await gate.future;
      if (!mounted) return;
      if (resolved && identical(gate, _startupRootGate)) return;
    }
  }

  Future<void> _onHomeBrowse({String? focusPath}) async {
    if (!_startupRootGate.isCompleted) {
      await _waitForStartupRootResolution();
      if (!mounted) return;
    }
    if (!_hasValidRoot) {
      await _pickFolder();
      return;
    }
    setState(() {
      _contentMode = _HomeContentMode.browse;
      if (focusPath != null) _focusBrowseOnPath(focusPath);
    });
  }

  /// Opens the column chain down to [path]'s directory. A file focuses its
  /// parent, so the file's own row is on screen.
  void _focusBrowseOnPath(String path) {
    final root = _resolveResultTree();
    if (root == null) return;
    final node = _findNodeByPath(root, path);
    if (node == null) return;
    final directory = node.isDirectory ? node.path : parentFsPath(node.path);
    _setColumnChain(_chainToPath(root, directory));
  }

  List<ScanTreeNode> _chainToPath(ScanTreeNode root, String targetPath) {
    final chain = <ScanTreeNode>[];
    var current = root;
    while (current.path != targetPath) {
      ScanTreeNode? next;
      for (final child in current.children) {
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

  void _openHomeCategory(String name) {
    final known = ScanFilterBar.categoryOptions.contains(name);
    setState(() {
      _categoryFilter = known ? name : null;
      _resetColumnNav();
      _contentMode = _HomeContentMode.browse;
    });
  }

  StorageHomeSummary _homeSummary(ScanProgressViewState progress) {
    final target = _homeTargetPath ?? _scanRootPath();
    return StorageHomeSummary.fromInputs(
      overview: _storageOverview,
      targetPath: target,
      matchingSnapshot: _snapshotMatchesTarget(target) ? _s.lastSnapshot : null,
      largestItemCandidates: _largestItemsFor(target),
      scanning: _s.scanning,
      scanProgress: _s.scanning ? progress.fraction : null,
      scanPhase: _s.scanning ? progress.phase : null,
      recentCustomLocations: _recentCustomLocations,
    );
  }

  bool get _canStartScan {
    return _startupRootGate.isCompleted &&
        !_startupPending &&
        _hasValidRoot &&
        !_targetPreparationPending &&
        !_s.targetPreviewLoading &&
        _s.ready &&
        !_s.scanning &&
        !_scanStartPending &&
        _s.hasSnapshotFileApi;
  }

  VoidCallback? get _scanStartAction {
    if (!_canStartScan) return null;
    final session = _s;
    final generation = _scanStartGeneration;
    return () => unawaited(_startScan(session, generation));
  }

  bool _isCurrentScanStart(VolwardSession session, int generation) {
    return mounted &&
        identical(_subscribedSession, session) &&
        !_isStartupPendingFor(session) &&
        generation == _scanStartGeneration;
  }

  Future<void> _startScan(
    VolwardSession expectedSession,
    int expectedGeneration,
  ) async {
    if (!identical(_subscribedSession, expectedSession) ||
        expectedGeneration != _scanStartGeneration ||
        !_startupRootGate.isCompleted ||
        _isStartupPendingFor(expectedSession) ||
        !_hasValidRoot ||
        _targetPreparationPending ||
        expectedSession.targetPreviewLoading ||
        !_canStartScan) {
      return;
    }
    final session = expectedSession;
    final generation = ++_scanStartGeneration;
    final incremental = session.incrementalScan;
    setState(() => _scanStartPending = true);
    String? nextStatus;
    try {
      final id = await session.runScan();
      if (!mounted || !_isCurrentScanStart(session, generation)) return;
      final snapshot = session.lastSnapshot;
      final count = snapshot?.filesInSnapshot ?? 0;
      final l10n = context.l10n;
      final label = incremental
          ? l10n.scanStatusIncremental
          : l10n.scanStatusFull;
      nextStatus = '${l10n.scanStatusFiles(label, count)} · $id';
    } catch (e) {
      if (!mounted || !_isCurrentScanStart(session, generation)) return;
      nextStatus = e is ScanCancelledException
          ? context.l10n.scanStatusCancelled
          : context.l10n.scanStatusFailed(e.toString());
    } finally {
      if (_isCurrentScanStart(session, generation)) {
        setState(() {
          _scanStartPending = false;
          if (nextStatus != null) _scanStatus = nextStatus;
        });
      }
    }
  }

  Future<void> _confirmDelete() async {
    final targetStrings = _deleteTargetStrings();
    if (targetStrings.isEmpty) return;
    final focus = _focusedDeleteNode();
    final targetPathById = <String, String>{};
    if (_selected.isNotEmpty) {
      for (final target in targetStrings) {
        final path = _selectedPaths[target];
        if (path != null && path.isNotEmpty) {
          targetPathById[target] = path;
        }
      }
    } else if (targetStrings.length == 1 && focus != null) {
      targetPathById[targetStrings.single] = focus.path;
    }
    final refreshPath = refreshPathForDeleteTargets(
      fallbackPath: _s.currentDirectoryPath ?? _scanRootPath(),
      targetPaths: targetPathById.values,
    );
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
        targetPathById: targetPathById,
      );
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _selectedSizes.clear();
        _selectedPaths.clear();
        _selectionAnchorPath = null;
        _selectionAnchorColumnIndex = null;
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
          padding:
              padding ??
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
                onPressed: (_s.canRefreshCurrentDirectory && !busy)
                    ? () => unawaited(_s.refreshCurrentDirectory())
                    : null,
              ),
              const SizedBox(width: AppleSpacing.xxs),
              AppleButton(
                key: HomePage.browseFolderActionKey,
                label: context.l10n.scanActionFolder,
                icon: Icons.folder_open_outlined,
                variant: AppleButtonVariant.pearl,
                onPressed: _pickFolder,
              ),
              if (_s.scanRoots.isNotEmpty) ...[
                const SizedBox(width: AppleSpacing.xxs),
                AppleButton(
                  key: HomePage.browseHomeActionKey,
                  label: context.l10n.scanActionHome,
                  icon: Icons.home_outlined,
                  variant: AppleButtonVariant.pearl,
                  onPressed: _switchBrowseToHomeRoot,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppleSpacing.xxs),
          ScanFilterBar(
            categoryFilter: _categoryFilter,
            presentCategories: {
              if (_snapshotMatchesCurrentRoot())
                for (final entry in _s.lastSnapshot!.categoryCounts.entries)
                  if (entry.value > 0 &&
                      ScanFilterBar.categoryOptions.contains(entry.key))
                    entry.key,
            },
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
                : context.l10n.resultsNoFilterMatchesWithCount(matchingCount),
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
    final cachedRootChildren =
        _visibleChildrenCache.peek(rootKey) ??
        _visibleChildrenCache.latestForPath(displayTree.path);
    final catalogQueryPending = _pendingVisibleChildrenQueries.contains(
      rootKey,
    );
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
    final catalogMayHaveChildren =
        _s.hasIndexApi &&
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
      childrenPreSorted:
          _s.hasIndexApi &&
          !_showingPreviewSnapshot &&
          _categoryFilter == null &&
          !_deletableOnly,
      selectionChain: List.unmodifiable(_columnChain),
      onSelect: _onColumnSelect,
      formatBytes: _fmt,
      selectedEntryIds: Set.unmodifiable(_selected),
      peekInFlight: _s.peekInFlight,
      busy:
          _s.deleting || _s.scanning || _s.refreshingDirectoryPaths.isNotEmpty,
      sortMode: _sort,
      categoryFilter: _categoryFilter,
      deletableOnly: _deletableOnly,
    );
  }

  @override
  Widget build(BuildContext context) {
    final browsing = _contentMode == _HomeContentMode.browse;
    final restoring = _s.restoringSnapshot;
    final snapshotMatchesCurrentRoot = _snapshotMatchesCurrentRoot();
    final loadingTarget =
        _s.targetPreviewLoading || (_s.scanning && !snapshotMatchesCurrentRoot);
    final hasResults =
        !loadingTarget && _s.lastSnapshot != null && snapshotMatchesCurrentRoot;
    final displayTree = browsing && hasResults ? _resolveResultTree() : null;
    final matchingCount = browsing && hasResults ? _matchingEntryCount() : 0;

    return Scaffold(
      backgroundColor: browsing
          ? context.volward.canvasParchment
          : StorageStewardHome.backgroundColor,
      body: Column(
        children: [
          if (browsing) _buildTopNav(context),
          Expanded(
            child: !browsing
                ? ValueListenableBuilder<ScanProgressViewState>(
                    valueListenable: _s.scanProgressNotifier,
                    builder: (context, progress, _) => StorageStewardHome(
                      summary: _homeSummary(progress),
                      onBrowse: () => unawaited(_onHomeBrowse()),
                      onChooseFolder: () => unawaited(_pickHomeFolder()),
                      onSelectTarget: (location) =>
                          unawaited(_prepareHomeTarget(location.path)),
                      onScan: _scanStartAction,
                      onCancelScan: _s.scanning ? _s.cancelScan : null,
                      onOpenSettings: _openSettings,
                      onSelectCategory: _openHomeCategory,
                      onOpenItem: (item) =>
                          unawaited(_onHomeBrowse(focusPath: item.path)),
                    ),
                  )
                : (restoring || loadingTarget) && !hasResults
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Keep the startup shell (target picker, scan actions)
                      // visible instead of swapping the whole page for a
                      // full-screen skeleton — the folder picker stays usable
                      // while the browser pane is still loading.
                      _buildScanSection(context),
                      Expanded(
                        child: _buildRestoreLoading(
                          context,
                          label: restoring
                              ? context.l10n.resultsRestoringPreviousScan
                              : context.l10n.scanColumnPreparingFolder,
                        ),
                      ),
                    ],
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
                              crossAxisAlignment: CrossAxisAlignment.stretch,
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
          if (_contentMode == _HomeContentMode.browse) _buildStickyBar(context),
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
              final maxRows =
                  ((available + AppleSpacing.sm) /
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

  void _openSettings() {
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
          updater: widget.updater,
        ),
      ),
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
          Tooltip(
            message: context.l10n.scanActionHome,
            child: Semantics(
              button: true,
              label: context.l10n.scanActionHome,
              child: InkWell(
                key: HomePage.logoKey,
                onTap: _showHome,
                borderRadius: BorderRadius.circular(AppleRadius.sm),
                child: ExcludeSemantics(
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
                    ],
                  ),
                ),
              ),
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
            onPressed: _openSettings,
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
                      key: HomePage.browseFolderActionKey,
                      label: l10n.scanActionFolder,
                      icon: Icons.folder_open_outlined,
                      variant: AppleButtonVariant.secondary,
                      onPressed: _pickFolder,
                    ),
                    if (_s.scanRoots.isNotEmpty)
                      AppleButton(
                        key: HomePage.browseHomeActionKey,
                        label: l10n.scanActionHome,
                        icon: Icons.home_outlined,
                        variant: AppleButtonVariant.pearl,
                        onPressed: _switchBrowseToHomeRoot,
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
    final selectId = entryId ?? (isDir ? focus.path : null);
    final marked = selectId != null && _selected.contains(selectId);
    final busy =
        _s.deleting || _s.scanning || _s.refreshingDirectoryPaths.isNotEmpty;

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
                if (selectId != null && category != 'System')
                  Checkbox(
                    value: marked,
                    onChanged: busy
                        ? null
                        : (_) => _toggleFocusedFileSelection(focus),
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
    final busy =
        _s.deleting ||
        _s.scanning ||
        _scanStartPending ||
        _s.refreshingDirectoryPaths.isNotEmpty;
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
        // Refresh button targets the currently focused directory. The root uses
        // a full scan; a child directory uses a scoped peek scan.
        actionLabel = busy ? '' : l10n.scanActionRescan;
        actionIcon = busy ? null : Icons.refresh_outlined;
        actionPressed = (busy || !_s.canRefreshCurrentDirectory)
            ? null
            : () => unawaited(_s.refreshCurrentDirectory());
      } else {
        label = _s.ready ? l10n.stickyReadyToScan : l10n.stickyLoadingEngine;
        actionLabel = l10n.scanActionStart;
        actionIcon = Icons.search;
        actionPressed = _scanStartAction;
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
                  label: _s.deleting
                      ? l10n.deleteActionWorking
                      : l10n.deleteActionMoveToTrash,
                  icon: _s.deleting ? null : Icons.delete_outline,
                  onPressed: deleteTargetCount > 0 && !busy
                      ? _confirmDelete
                      : null,
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
