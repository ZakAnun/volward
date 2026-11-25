import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../catalog/catalog_reader.dart';
import '../catalog/directory_browse_session.dart';
import '../catalog/snapshot_catalog.dart';
import '../deletion/delete_overlay.dart';
import '../../scan_entry_record.dart';
import '../../scan_snapshot_state.dart';
import '../../scan_tree.dart';
import '../../snapshot_query.dart';
import '../contracts/native_engine_ports.dart';

/// Narrow dependencies used by the catalog owner.
abstract interface class CatalogSessionHost {
  bool get catalogEngineReady;
  bool get catalogHasIndexApi;
  bool get catalogHasSnapshotFileApi;
  int get catalogIndexVersion;
  int get catalogRootSwitchGeneration;
  bool get catalogScanning;
  Set<String> get catalogPeekInFlight;
  ScanSnapshotState? get catalogSnapshot;
  List<String> get catalogScanRoots;
  String get catalogDefaultRoot;
  IndexEnginePort? get catalogIndexEngine;

  Future<void> runCatalogRootRefresh();
  Future<bool> peekScanForCatalog(String path, {bool force = false});
  void invalidateCapabilityCacheForCatalog(String? snapshotId);
  void setCatalogLastError(String? value);
  void beginCatalogNotificationBatch();
  void endCatalogNotificationBatch({bool notify = true});
  void trackCatalogRefreshTriggered();
}

/// Owns authoritative browse/catalog state.
class CatalogSession extends ChangeNotifier
    implements DirectoryBrowseSession, CatalogReader {
  CatalogSession({required this.host, ScanSnapshotState? initialSnapshot})
    : _snapshot = initialSnapshot;

  final CatalogSessionHost host;
  ScanSnapshotState? _snapshot;
  String? _currentDirectoryPath;
  int _snapshotVersion = 0;
  final Set<String> _invalidatedPrefixes = {};
  final Map<String, ScanTreeNode> _directoryOverlays = {};
  final Set<String> _refreshingDirectoryPaths = {};
  final Set<String> _postDeleteRefreshPaths = {};
  final Map<String, String> _refreshErrors = {};

  @visibleForTesting
  bool didAttemptHydration = false;
  @visibleForTesting
  Future<void> Function(String path)? directoryRefreshRunnerForTest;

  ScanSnapshotState? get _currentSnapshot => _snapshot ?? host.catalogSnapshot;

  @override
  bool get hasIndexApi => host.catalogHasIndexApi;

  @override
  int get catalogVersion {
    final rustVersion = host.catalogHasIndexApi ? host.catalogIndexVersion : 0;
    return rustVersion ^ (_snapshotVersion << 20);
  }

  int get snapshotVersion => _snapshotVersion;

  Set<String> get invalidatedPrefixes => Set.unmodifiable(_invalidatedPrefixes);

  @override
  String? get currentDirectoryPath => _currentDirectoryPath;

  @override
  String get refreshTargetPath =>
      _currentDirectoryPath ??
      (host.catalogScanRoots.isNotEmpty
          ? host.catalogScanRoots.first
          : host.catalogDefaultRoot);

  @override
  Set<String> get refreshingDirectoryPaths =>
      Set.unmodifiable(_refreshingDirectoryPaths);

  @override
  Set<String> get peekInFlight => host.catalogPeekInFlight;

  bool get postDeleteRefreshPending => _postDeleteRefreshPaths.isNotEmpty;

  String? refreshErrorForPath(String path) =>
      _refreshErrors[ScanTreeBuilder.normalizeRoot(path)];

  @override
  bool isDirectoryRefreshing(String path) =>
      _refreshingDirectoryPaths.contains(ScanTreeBuilder.normalizeRoot(path));

  @override
  bool get canRefreshCurrentDirectory {
    if (!host.catalogEngineReady) return false;
    final root = ScanTreeBuilder.normalizeRoot(
      host.catalogScanRoots.isNotEmpty
          ? host.catalogScanRoots.first
          : host.catalogDefaultRoot,
    );
    final target = ScanTreeBuilder.normalizeRoot(refreshTargetPath);
    return !isDirectoryRefreshing(target) &&
        (target != root || host.catalogHasSnapshotFileApi);
  }

  @override
  void setCurrentDirectory(String? path) {
    if (_currentDirectoryPath == path) return;
    _currentDirectoryPath = path;
  }

  @visibleForTesting
  void setCurrentPathForTest(String path) => _currentDirectoryPath = path;

  @override
  Set<String> consumeInvalidatedPrefixes() {
    final prefixes = Set<String>.from(_invalidatedPrefixes);
    _invalidatedPrefixes.clear();
    return prefixes;
  }

  @override
  ScanTreeNode? directoryOverlayForPath(String path) =>
      _directoryOverlays[ScanTreeBuilder.normalizeRoot(path)];

  void resetBrowseStateForRootChange() {
    _currentDirectoryPath = null;
    _directoryOverlays.clear();
    _refreshingDirectoryPaths.clear();
    _postDeleteRefreshPaths.clear();
    _refreshErrors.clear();
    _snapshotVersion++;
    _invalidatedPrefixes.clear();
  }

  void applySnapshot(ScanSnapshotState snapshot) {
    _snapshot = snapshot;
    didAttemptHydration = false;
    resetBrowseStateForRootChange();
    notifyListeners();
  }

  @visibleForTesting
  void replaceSnapshotForTest(ScanSnapshotState snapshot) {
    _snapshot = snapshot;
    didAttemptHydration = false;
    _directoryOverlays.clear();
    _invalidatedPrefixes.clear();
  }

  SnapshotQueryResult query(SnapshotQueryKey key) {
    final snapshot = _currentSnapshot;
    if (snapshot == null) {
      return const SnapshotQueryResult(
        directNodes: <ScanTreeNode>[],
        directChildren: <ScanTreeNode>[],
        directEntries: <ScanEntryRecord>[],
        totalBytes: 0,
        reclaimableBytes: 0,
      );
    }
    return SnapshotCatalog(
      snapshotId: snapshot.snapshotId,
      tree: snapshot.tree,
      reader: this,
    ).query(key);
  }

  @override
  List<SnapshotNodeRecord>? queryDirectoryChildrenFromCatalog(
    String path, {
    String? categoryFilter,
    bool deletableOnly = false,
    String sortMode = 'size_desc',
  }) {
    final engine = host.catalogIndexEngine;
    if (!host.catalogHasIndexApi || engine == null) return null;
    try {
      final result = engine.queryDirectoryJson(
        normalizeFsPath(path),
        categoryFilter: categoryFilter,
        deletableOnly: deletableOnly,
        sortMode: sortMode,
      );
      final nodes = result['direct_children'] as List?;
      if (nodes == null) return null;
      return nodes
          .whereType<Map<String, dynamic>>()
          .map(SnapshotNodeRecord.fromJson)
          .toList(growable: false);
    } catch (e) {
      debugPrint('CatalogSession.queryDirectoryChildren: $e');
      return null;
    }
  }

  @override
  Future<void> refreshCurrentDirectory([String? path]) async {
    if (!host.catalogEngineReady && !host.catalogHasIndexApi) return;
    final targetPath = path ?? refreshTargetPath;
    final root = ScanTreeBuilder.normalizeRoot(
      host.catalogScanRoots.isNotEmpty
          ? host.catalogScanRoots.first
          : host.catalogDefaultRoot,
    );
    final target = ScanTreeBuilder.normalizeRoot(targetPath);
    if (_refreshingDirectoryPaths.contains(target)) return;

    host.trackCatalogRefreshTriggered();
    _currentDirectoryPath = target == root ? null : target;
    _refreshingDirectoryPaths.add(target);
    _refreshErrors.remove(target);
    _invalidatedPrefixes.add(target);
    _snapshotVersion++;
    notifyListeners();

    final scopedRefresh = target != root;
    if (scopedRefresh) host.beginCatalogNotificationBatch();
    try {
      if (!scopedRefresh) {
        final generation = host.catalogRootSwitchGeneration;
        while (host.catalogScanning &&
            generation == host.catalogRootSwitchGeneration) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        if (generation != host.catalogRootSwitchGeneration) return;
        await host.runCatalogRootRefresh();
      } else {
        final refreshed = await host.peekScanForCatalog(target, force: true);
        if (!refreshed) {
          _refreshErrors[target] =
              'The directory could not be refreshed. '
              'The previous results are still shown.';
        }
      }
      host.invalidateCapabilityCacheForCatalog(_currentSnapshot?.snapshotId);
    } catch (e, st) {
      _refreshErrors[target] = e.toString();
      host.setCatalogLastError('$e');
      debugPrint('CatalogSession.refreshCurrentDirectory failed: $e\n$st');
    } finally {
      _refreshingDirectoryPaths.remove(target);
      if (scopedRefresh) {
        notifyListeners();
        host.endCatalogNotificationBatch(notify: false);
      } else {
        notifyListeners();
      }
    }
  }

  @override
  Future<bool> peekScan(String path, {bool force = false}) =>
      host.peekScanForCatalog(path, force: force);

  Future<void> commitMergedSnapshot({
    required ScanSnapshotState snapshot,
    required String targetPath,
    required Map<String, dynamic> subtreeTree,
    required List<Map<String, dynamic>> subtreeEntries,
    required bool authoritative,
    bool notify = true,
  }) async {
    _snapshot = snapshot;
    if (authoritative) {
      final entriesById = <String, ScanEntryRecord>{
        for (final entry in subtreeEntries)
          if (entry['id'] != null)
            entry['id'].toString(): ScanEntryRecord.fromWire(entry),
      };
      final overlay = ScanTreeNode.fromSnapshotJson(
        Map<String, dynamic>.from(subtreeTree),
        entriesById: entriesById,
      );
      final normalizedPath = ScanTreeBuilder.normalizeRoot(targetPath);
      final prefix = normalizedPath.endsWith('/')
          ? normalizedPath
          : '$normalizedPath/';
      _directoryOverlays.removeWhere(
        (path, _) => path == normalizedPath || path.startsWith(prefix),
      );
      _directoryOverlays[normalizedPath] = overlay;
      _spliceSubtreeIntoCatalog(normalizedPath, subtreeTree, subtreeEntries);
    }
    _snapshotVersion++;
    _invalidatedPrefixes.add(targetPath);
    if (notify) notifyListeners();
  }

  void _spliceSubtreeIntoCatalog(
    String normalizedPath,
    Map<String, dynamic> subtreeTree,
    List<Map<String, dynamic>> subtreeEntries,
  ) {
    final engine = host.catalogIndexEngine;
    if (!host.catalogHasIndexApi ||
        engine == null ||
        !engine.hasReplaceSubtreeApi) {
      return;
    }
    try {
      final payload = jsonEncode(<String, dynamic>{
        'tree': subtreeTree,
        'entries': subtreeEntries,
      });
      engine.replaceDirectoryWithSubtree(normalizedPath, payload);
    } catch (e, st) {
      debugPrint('CatalogSession.spliceSubtreeIntoCatalog failed: $e\n$st');
    }
  }

  void applySuccessfulDeleteOverlay(
    String directoryPath,
    List<String> targets,
    Map<String, dynamic> report, {
    Map<String, String>? targetPathById,
    bool notify = true,
  }) {
    final normalizedPath = ScanTreeBuilder.normalizeRoot(directoryPath);
    final existing = _directoryOverlays[normalizedPath];
    final snapshotNode = existing == null
        ? _findSnapshotDirectory(_currentSnapshot?.tree, normalizedPath)
        : null;
    final records = existing != null
        ? existing.children
              .map(SnapshotNodeRecord.fromTree)
              .toList(growable: false)
        : (queryDirectoryChildrenFromCatalog(normalizedPath) ??
              snapshotNode?.children
                  .map(SnapshotNodeRecord.fromTree)
                  .toList(growable: false));
    if (records == null) {
      debugPrint(
        'CatalogSession: delete overlay skipped for $normalizedPath — '
        'no records available (list may be stale; manual refresh required)',
      );
      _refreshErrors[normalizedPath] =
          'The directory could not be refreshed after delete. '
          'The previous results are still shown.';
      return;
    }
    final deletedCount = (report['deleted_count'] as num?)?.toInt() ?? 0;
    if (deletedCount <= 0) {
      debugPrint(
        'CatalogSession: delete overlay skipped for $normalizedPath — '
        'report deleted_count=$deletedCount',
      );
      return;
    }

    final overlay = deletedEntryOverlay(
      records: records,
      targets: targets,
      report: report,
      targetPathById: targetPathById,
    );
    final remaining = overlay.remaining;
    final removedPaths = overlay.removedPaths;
    final base = existing ?? snapshotNode ?? ScanTreeNode.empty(normalizedPath);
    _directoryOverlays.removeWhere((path, _) {
      for (final removedPath in removedPaths) {
        if (path == removedPath || path.startsWith('$removedPath/')) {
          return true;
        }
      }
      return false;
    });
    _directoryOverlays[normalizedPath] = ScanTreeNode(
      name: base.name,
      path: normalizedPath,
      isDirectory: true,
      sizeBytes: base.sizeBytes,
      scanned: true,
      peekScanned: true,
      children: remaining,
    );
    _snapshotVersion++;
    _invalidatedPrefixes.add(normalizedPath);
    if (notify) notifyListeners();
  }

  ScanTreeNode? _findSnapshotDirectory(ScanTreeNode? node, String targetPath) {
    if (node == null) return null;
    if (node.path == targetPath && node.isDirectory) return node;
    if (!node.isDirectory) return null;
    for (final child in node.children) {
      final found = _findSnapshotDirectory(child, targetPath);
      if (found != null) return found;
    }
    return null;
  }

  void scheduleDirectoryRefreshAfterDelete(String path) {
    final normalizedPath = ScanTreeBuilder.normalizeRoot(path);
    _postDeleteRefreshPaths.add(normalizedPath);
    notifyListeners();
    unawaited(
      Future<void>.delayed(Duration.zero, () async {
        try {
          final runner = directoryRefreshRunnerForTest;
          if (runner != null) {
            await runner(path);
          } else {
            await refreshCurrentDirectory(path);
          }
        } catch (e, st) {
          _refreshErrors[normalizedPath] = e.toString();
          debugPrint(
            'CatalogSession: post-delete directory refresh failed: $e\n$st',
          );
          notifyListeners();
        } finally {
          _postDeleteRefreshPaths.remove(normalizedPath);
          notifyListeners();
        }
      }),
    );
  }
}
