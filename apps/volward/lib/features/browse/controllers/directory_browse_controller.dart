// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../scan_tree.dart';
import '../../../snapshot_query.dart';
import '../../../snapshot_view_cache.dart';
import '../scan_sort_mode.dart';

/// Owns browse-only state that survives Session notifications and page rebuilds.
class DirectoryBrowseController extends ChangeNotifier {
  DirectoryBrowseController({
    Future<void> Function(String path)? selectionLoader,
  }) : _selectionLoader = selectionLoader;

  @visibleForTesting
  factory DirectoryBrowseController.forTest({
    Future<void> Function(String path)? selectionLoader,
  }) => DirectoryBrowseController(selectionLoader: selectionLoader);

  final Future<void> Function(String path)? _selectionLoader;

  String? _currentPath;
  int _selectionGeneration = 0;
  int sortIndex = ScanSortMode.sizeDesc.index;
  String? categoryFilter;
  bool deletableOnly = false;
  final Set<String> selected = {};
  final Map<String, int> selectedSizes = {};
  final Map<String, String> selectedPaths = {};
  final List<ScanTreeNode> columnChain = [];
  String? selectionAnchorPath;
  int? selectionAnchorColumnIndex;
  final ValueNotifier<int> columnNavTick = ValueNotifier(0);
  final ValueNotifier<int> browseRevision = ValueNotifier(0);
  final ValueNotifier<int> homeSummaryRevision = ValueNotifier(0);
  final SnapshotViewCache<List<SnapshotNodeRecord>> visibleChildrenCache =
      SnapshotViewCache(capacity: 128);
  final Set<SnapshotQueryKey> pendingVisibleChildrenQueries = {};

  /// Resolved result tree, cached per snapshot id.
  ScanTreeNode? cachedResolvedTree;
  String? cachedResolvedTreeKey;

  /// Selected-bytes total, recomputed only when the selection or snapshot
  /// changes instead of on every build pass.
  int cachedSelectedBytes = 0;
  String? cachedSelectedBytesKey;

  /// Largest item candidates for the home dashboard, cached per snapshot and
  /// target path.
  List<ScanTreeNode> largestItemCandidates = const [];
  String? largestItemsCacheKey;

  String? get currentPath => _currentPath;

  int get selectionGeneration => _selectionGeneration;

  Future<void> selectDirectory(String path) async {
    final generation = ++_selectionGeneration;
    await _selectionLoader?.call(path);
    if (generation != _selectionGeneration) return;
    if (_currentPath == path) return;
    _currentPath = path;
    notifyListeners();
  }

  void syncCurrentDirectory(String? path) {
    if (_currentPath == path) return;
    _currentPath = path;
  }

  void clearSelection() {
    selected.clear();
    selectedSizes.clear();
    selectedPaths.clear();
    selectionAnchorPath = null;
    selectionAnchorColumnIndex = null;
  }

  void resetColumnNavigation() {
    columnChain.clear();
    columnNavTick.value++;
  }

  void invalidateVisibleChildren() {
    visibleChildrenCache.clear();
    pendingVisibleChildrenQueries.clear();
  }

  /// Drops every cached snapshot projection so the next query pass resolves
  /// fresh data from the session.
  void invalidateSnapshotCaches() {
    cachedResolvedTree = null;
    cachedResolvedTreeKey = null;
    cachedSelectedBytesKey = null;
    largestItemsCacheKey = null;
    invalidateVisibleChildren();
  }

  /// Drops the tree-level caches but preserves per-path visible children for
  /// any paths the catalog announced as unchanged.
  void invalidateSnapshotCachesForSessionUpdate(
    Set<String> invalidatedPrefixes,
  ) {
    cachedResolvedTree = null;
    cachedResolvedTreeKey = null;
    cachedSelectedBytesKey = null;
    if (invalidatedPrefixes.isEmpty) {
      invalidateVisibleChildren();
      // Cache key omits catalogVersion, but unconditional invalidation here
      // keeps it safe.
      largestItemsCacheKey = null;
      return;
    }
    for (final prefix in invalidatedPrefixes) {
      visibleChildrenCache.invalidatePath(prefix);
    }
    pendingVisibleChildrenQueries.removeWhere((key) {
      for (final prefix in invalidatedPrefixes) {
        if (key.path == prefix || key.path.startsWith('$prefix/')) {
          return true;
        }
      }
      return false;
    });
    largestItemsCacheKey = null;
  }

  @override
  void dispose() {
    columnNavTick.dispose();
    browseRevision.dispose();
    homeSummaryRevision.dispose();
    super.dispose();
  }
}
