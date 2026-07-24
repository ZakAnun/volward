import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'macos_settings.dart';
import 'scan_tree.dart';
import 'scan_tree_filter.dart';
import 'theme/apple_tokens.dart';
import 'settings_page.dart';
import 'theme/volward_theme_settings.dart';
import 'theme/volward_tokens.dart';
import 'volward_session.dart';
import 'widgets/apple_widgets.dart';
import 'widgets/scan_column_view.dart';
import 'widgets/scan_filter_bar.dart';
import 'scan_tree_navigation.dart';

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
  final List<ScanTreeNode> _columnChain = [];
  final ValueNotifier<int> _columnNavTick = ValueNotifier(0);
  bool _prevScanning = false;
  bool _permissionBannerExpanded = false;
  // Tracks the last `_lastSnapshot['snapshot_id']` we already refreshed the
  // column-nav caches for, so plain progress ticks (which fire ~3x/sec via
  // VolwardSession.notifyListeners but don't touch _lastSnapshot) don't
  // trigger a full tree re-sort/re-aggregate on every tick while browsing
  // during a background scan.
  String? _lastRefreshedSnapshotId;

  ScanTreeNode? _cachedDisplayTree;
  String? _cachedDisplayTreeKey;
  ScanTreeNode? _cachedResolvedTree;
  String? _cachedResolvedTreeKey;
  List<Map<String, dynamic>>? _cachedFilteredEntries;
  String? _cachedFilteredEntriesKey;
  Map<String, Map<String, dynamic>>? _cachedEntriesById;
  List<Map<String, dynamic>>? _cachedAllEntries;
  String? _cachedEntriesKey;

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
    await MacosSettings.openFullDiskAccessSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'If Volward is not listed: tap +, press Cmd+Shift+G, paste the copied .app path, enable the switch, then Check again.',
        ),
        action: SnackBarAction(
          label: 'Copy path',
          onPressed: () async {
            await MacosSettings.copyAppBundlePath();
          },
        ),
      ),
    );
  }

  Future<void> _copyAppBundlePath() async {
    await MacosSettings.copyAppBundlePath();
    if (!mounted) return;
    final path = MacosSettings.appBundlePath();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied: ${path ?? 'unknown'}')));
  }

  void _onSessionChanged() {
    if (!_prevScanning && _s.scanning) {
      setState(() {
        _selected.clear();
        _scanStatus = null;
        _columnChain.clear();
        _columnNavTick.value++;
        _invalidateSnapshotCaches();
        _lastRefreshedSnapshotId = _s.lastSnapshot?['snapshot_id']?.toString();
      });
    } else if (_prevScanning && !_s.scanning && _s.lastSnapshot != null) {
      _columnChain.clear();
      _columnNavTick.value++;
      _invalidateSnapshotCaches();
      _lastRefreshedSnapshotId = _s.lastSnapshot?['snapshot_id']?.toString();
    } else if (_columnChain.isNotEmpty) {
      // A background checkpoint (or Wave-2 peek) may have merged new data
      // into _lastSnapshot while the user is browsing. Only pay for a full
      // cache invalidation + tree re-sort/re-aggregate when the snapshot
      // actually changed — most VolwardSession.notifyListeners() calls
      // during an active scan are plain progress-percentage ticks (~3/sec)
      // that don't touch _lastSnapshot at all.
      final snapId = _s.lastSnapshot?['snapshot_id']?.toString();
      if (snapId != null && snapId != _lastRefreshedSnapshotId) {
        _lastRefreshedSnapshotId = snapId;
        _invalidateSnapshotCaches();
        final freshRoot = _getDisplayTree();
        if (freshRoot != null) {
          _setColumnChain(refreshColumnChain(freshRoot, _columnChain));
        }
      }
    }
    _prevScanning = _s.scanning;
    setState(() {});
  }

  String _scanRootPath() {
    if (_s.scanRoots.isNotEmpty) {
      return ScanTreeBuilder.normalizeRoot(_s.scanRoots.first);
    }
    return ScanTreeBuilder.normalizeRoot(Platform.environment['HOME'] ?? '/');
  }

  Map<String, Map<String, dynamic>> _entriesById() {
    final snapId = _s.lastSnapshot?['snapshot_id']?.toString() ?? '';
    if (_cachedEntriesById != null && _cachedEntriesKey == snapId) {
      return _cachedEntriesById!;
    }
    final snap = _s.lastSnapshot;
    if (snap == null || snap['entries'] is! List) {
      _cachedEntriesById = {};
      _cachedEntriesKey = snapId;
      return _cachedEntriesById!;
    }
    final out = <String, Map<String, dynamic>>{};
    for (final raw in snap['entries'] as List) {
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);
      final id = entry['id']?.toString();
      if (id != null) out[id] = entry;
    }
    _cachedEntriesById = out;
    _cachedEntriesKey = snapId;
    return out;
  }

  List<Map<String, dynamic>> _allSnapshotEntries() {
    final snapId = _s.lastSnapshot?['snapshot_id']?.toString() ?? '';
    if (_cachedAllEntries != null && _cachedEntriesKey == snapId) {
      return _cachedAllEntries!;
    }
    final snap = _s.lastSnapshot;
    if (snap == null || snap['entries'] is! List) {
      _cachedAllEntries = [];
      _cachedEntriesKey = snapId;
      return _cachedAllEntries!;
    }
    final list = (snap['entries'] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _cachedAllEntries = list;
    _cachedEntriesKey = snapId;
    return list;
  }

  ScanTreeNode? _resolveResultTree() {
    final snapId = _s.lastSnapshot?['snapshot_id']?.toString() ?? '';
    if (_cachedResolvedTree != null && _cachedResolvedTreeKey == snapId) {
      return _cachedResolvedTree;
    }

    final snap = _s.lastSnapshot;
    if (snap == null) return null;

    final entriesById = _entriesById();
    final entries = _allSnapshotEntries();
    ScanTreeNode? tree;

    if (snap['tree'] is Map) {
      tree = ScanTreeNode.fromSnapshotJson(
        Map<String, dynamic>.from(snap['tree'] as Map),
        entriesById: entriesById,
      );
    }

    final rootPath = (tree != null && tree.path.isNotEmpty)
        ? ScanTreeBuilder.normalizeRoot(tree.path)
        : _scanRootPath();

    if (entries.isNotEmpty && (tree == null || tree.children.isEmpty)) {
      tree = ScanTreeBuilder.build(entries: entries, rootPath: rootPath);
    }

    _cachedResolvedTree = tree;
    _cachedResolvedTreeKey = snapId;
    return tree;
  }

  ScanTreeNode _sortTree(ScanTreeNode node) {
    if (!node.isDirectory) return node;

    final sortedChildren = node.children.map(_sortTree).toList();
    sortedChildren.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      switch (_sort) {
        case ScanSortMode.sizeDesc:
          return b.displayBytes.compareTo(a.displayBytes);
        case ScanSortMode.sizeAsc:
          return a.displayBytes.compareTo(b.displayBytes);
        case ScanSortMode.nameAsc:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });

    return ScanTreeNode(
      name: node.name,
      path: node.path,
      isDirectory: true,
      sizeBytes: node.sizeBytes,
      entryId: node.entryId,
      entry: node.entry,
      scanned: node.scanned,
      children: sortedChildren,
    );
  }

  void _invalidateDisplayTreeCaches() {
    _cachedDisplayTree = null;
    _cachedDisplayTreeKey = null;
    _cachedFilteredEntries = null;
    _cachedFilteredEntriesKey = null;
  }

  void _invalidateSnapshotCaches() {
    _invalidateDisplayTreeCaches();
    _cachedResolvedTree = null;
    _cachedResolvedTreeKey = null;
    _cachedEntriesById = null;
    _cachedAllEntries = null;
    _cachedEntriesKey = null;
  }

  void _resetColumnNav() {
    _columnChain.clear();
    _columnNavTick.value++;
  }

  void _setColumnChain(List<ScanTreeNode> next) {
    _columnChain
      ..clear()
      ..addAll(next);
    _columnNavTick.value++;
  }

  ScanTreeNode? _computeDisplayTree() {
    final root = _resolveResultTree();
    if (root == null) return null;

    bool keep(Map<String, dynamic> entry) {
      if (_categoryFilter != null &&
          entry['category']?.toString() != _categoryFilter) {
        return false;
      }
      if (_deletableOnly && entry['deletable'] != true) return false;
      return true;
    }

    final filtered = (_categoryFilter == null && !_deletableOnly)
        ? root
        : pruneTree(root, keep);
    if (filtered == null) return null;
    return ScanTreeNode.withAggregatedCounts(_sortTree(filtered));
  }

  String _displayTreeCacheKey() {
    final snapId = _s.lastSnapshot?['snapshot_id']?.toString() ?? '';
    return '$snapId|$_categoryFilter|$_deletableOnly|$_sort';
  }

  ScanTreeNode? _getDisplayTree() {
    final key = _displayTreeCacheKey();
    if (_cachedDisplayTree != null && _cachedDisplayTreeKey == key) {
      return _cachedDisplayTree;
    }
    _cachedDisplayTree = _computeDisplayTree();
    _cachedDisplayTreeKey = key;
    return _cachedDisplayTree;
  }

  void _onColumnSelect(int columnIndex, ScanTreeNode node) {
    _setColumnChain(_columnChain.take(columnIndex).toList()..add(node));
    if (node.isDirectory && !node.scanned) {
      unawaited(_s.peekScan(node.path));
    }
  }

  void _toggleFocusedFileSelection(ScanTreeNode node) {
    final entry = node.entry;
    if (entry == null || entry['deletable'] != true) return;
    final id = entry['id']?.toString() ?? node.entryId;
    if (id == null || id.isEmpty) return;
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
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

  String _phaseLabel(String phase) =>
      const {
        'DiscoveringRoots': 'Discovering roots…',
        'Walking': 'Scanning files…',
        'Classifying': 'Classifying entries…',
        'Aggregating': 'Aggregating results…',
        'SavingResults': 'Saving results…',
        'LoadingResults': 'Loading results…',
        'Done': 'Done',
      }[phase] ??
      phase;

  String _scanProgressSummary() {
    final p = _s.scanProgress;
    if (p == null) return 'Starting…';
    final phase = _phaseLabel(p['phase']?.toString() ?? '');
    final paths = p['paths_seen'];
    final elapsed = _s.scanElapsedLabel;
    final buf = StringBuffer(phase);
    if (paths != null && paths != 0) buf.write(' · $paths items');
    if (elapsed != null) buf.write(' · $elapsed');
    final current = p['current_path']?.toString();
    if (current != null && current.isNotEmpty) {
      buf.write(' · $current');
    }
    return buf.toString();
  }

  int _selectedBytes(List<Map<String, dynamic>> entries) {
    var t = 0;
    for (final e in entries) {
      if (_selected.contains(e['id']?.toString())) {
        t += (e['size_bytes'] as num?)?.toInt() ?? 0;
      }
    }
    return t;
  }

  List<Map<String, dynamic>> _filteredSortedEntries() {
    final key = _displayTreeCacheKey();
    if (_cachedFilteredEntries != null && _cachedFilteredEntriesKey == key) {
      return _cachedFilteredEntries!;
    }

    Iterable<Map<String, dynamic>> out = _allSnapshotEntries();
    if (_categoryFilter != null) {
      out = out.where((e) => e['category']?.toString() == _categoryFilter);
    }
    if (_deletableOnly) out = out.where((e) => e['deletable'] == true);
    final list = out.toList();
    switch (_sort) {
      case ScanSortMode.sizeDesc:
        list.sort(
          (a, b) => ((b['size_bytes'] as num?) ?? 0).compareTo(
            (a['size_bytes'] as num?) ?? 0,
          ),
        );
      case ScanSortMode.sizeAsc:
        list.sort(
          (a, b) => ((a['size_bytes'] as num?) ?? 0).compareTo(
            (b['size_bytes'] as num?) ?? 0,
          ),
        );
      case ScanSortMode.nameAsc:
        list.sort(
          (a, b) => (a['display_name']?.toString() ?? '').compareTo(
            b['display_name']?.toString() ?? '',
          ),
        );
    }
    _cachedFilteredEntries = list;
    _cachedFilteredEntriesKey = key;
    return list;
  }

  Future<void> _pickFolder() async {
    final path = await getDirectoryPath(confirmButtonText: 'Select');
    if (path == null) return;
    _s.setScanRoots([path]);
    await _s.previewTarget();
  }

  Future<void> _startScan() async {
    if (!_s.ready) return;
    final incremental = _s.incrementalScan;
    try {
      final id = await _s.runScan();
      if (!mounted) return;
      final stats = _s.lastSnapshot?['stats'];
      final count = stats is Map
          ? (stats['files_in_snapshot'] as num?)?.toInt()
          : (_s.lastSnapshot?['entries'] is List
                ? (_s.lastSnapshot!['entries'] as List).length
                : 0);
      setState(() {
        _scanStatus =
            '${incremental ? 'Incremental' : 'Full'} scan: $count files · $id';
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e is ScanCancelledException
          ? 'Scan cancelled'
          : 'Scan failed: $e';
      setState(() => _scanStatus = msg);
    }
  }

  Future<void> _confirmDelete() async {
    if (_selected.isEmpty) return;
    final preview = await _s.deleteEntries(_selected.toList(), dryRun: true);
    if (!mounted) return;
    final count = (preview['deleted_count'] as num?)?.toInt() ?? 0;
    final freed = (preview['freed_bytes'] as num?)?.toInt() ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to Trash?'),
        content: Text(
          'Move $count item(s) to Trash and free about ${_fmt(freed)}?\n\nYou can restore them from Trash if needed.',
        ),
        actions: [
          AppleButton(
            label: 'Cancel',
            variant: AppleButtonVariant.pearl,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          AppleButton(
            label: 'Delete',
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final report = await _s.deleteEntries(
        _selected.toList(),
        rescanAfterDelete: true,
      );
      if (!mounted) return;
      setState(_selected.clear);
      final freedAfter = (report['freed_bytes'] as num?)?.toInt() ?? 0;
      final failed = report['failed_paths'];
      final failedCount = failed is List ? failed.length : 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failedCount > 0
                ? 'Deleted with $failedCount failure(s). Freed ${_fmt(freedAfter)}.'
                : 'Moved to Trash. Freed ${_fmt(freedAfter)}. Rescan complete.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
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
    required List<Map<String, dynamic>> entries,
    required ScanTreeNode? displayTree,
  }) {
    final showPermission =
        _s.ready && (!_s.hasSnapshotFileApi || !_s.deepScanReady);

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
                  _compactResultsSummary(displayTree, entries),
                  style: context.vwFinePrintInk,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppleSpacing.xs),
              Tooltip(
                message: _s.scanTargetLabel,
                child: Text(
                  _s.scanRoots.isEmpty ? 'Home' : 'Custom',
                  style: context.vwFinePrint,
                ),
              ),
              const SizedBox(width: AppleSpacing.xs),
              AppleButton(
                label: 'Folder…',
                icon: Icons.folder_open_outlined,
                variant: AppleButtonVariant.pearl,
                onPressed: _s.scanning ? null : _pickFolder,
              ),
              if (_s.scanRoots.isNotEmpty) ...[
                const SizedBox(width: AppleSpacing.xxs),
                AppleButton(
                  label: 'Home',
                  icon: Icons.home_outlined,
                  variant: AppleButtonVariant.pearl,
                  onPressed: _s.scanning
                      ? null
                      : () async {
                          _s.clearScanRoots();
                          setState(() => _scanStatus = null);
                          await _s.previewTarget();
                        },
                ),
              ],
              if (_s.scanning) ...[
                const SizedBox(width: AppleSpacing.xxs),
                AppleButton(
                  label: 'Cancel',
                  icon: Icons.stop_outlined,
                  variant: AppleButtonVariant.darkUtility,
                  onPressed: _s.cancelScan,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppleSpacing.xxs),
          ScanFilterBar(
            categoryFilter: _categoryFilter,
            onCategoryChanged: (cat) => setState(() {
              _categoryFilter = cat;
              _resetColumnNav();
              _invalidateDisplayTreeCaches();
            }),
            sortMode: _sort,
            onSortChanged: (mode) => setState(() {
              _sort = mode;
              _invalidateDisplayTreeCaches();
            }),
            deletableOnly: _deletableOnly,
            onDeletableOnlyChanged: (v) => setState(() {
              _deletableOnly = v;
              _resetColumnNav();
              _invalidateDisplayTreeCaches();
            }),
            incrementalScan: _s.incrementalScan,
            onIncrementalScanChanged: _s.setIncrementalScan,
            incrementalEnabled: _s.canUseIncrementalScan,
            scanning: _s.scanning,
          ),
          if (_s.scanning) ...[
            const SizedBox(height: AppleSpacing.xxs),
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(AppleRadius.pill)),
              child: LinearProgressIndicator(minHeight: 2),
            ),
            const SizedBox(height: 2),
            Text(
              _scanProgressSummary(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.vwFinePrint,
            ),
          ] else if (_scanStatus != null) ...[
            const SizedBox(height: 2),
            Text(
              _scanStatus!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.vwFinePrint,
            ),
          ],
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

  String _compactResultsSummary(
    ScanTreeNode? displayTree,
    List<Map<String, dynamic>> entries,
  ) {
    final snap = _s.lastSnapshot;
    final reclaimable = snap?['reclaimable_estimate_bytes'];
    final parts = <String>[];
    if (displayTree != null) {
      parts.add(_formatTreeSummary(displayTree));
    }
    parts.add('${entries.length} classified');
    if (reclaimable != null) {
      parts.add('${_fmt(reclaimable)} reclaimable');
    }
    return parts.join(' · ');
  }

  Widget _buildResultsBrowser(
    BuildContext context,
    ScanTreeNode? displayTree,
    List<Map<String, dynamic>> entries,
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
            entries.isEmpty
                ? 'No items match the current filters.'
                : 'No items match the current filters (${entries.length} in list).',
            style: context.vwFinePrint,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (displayTree.children.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: v.canvas,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(color: v.hairline),
        ),
        child: Center(
          child: Text(
            'Scan returned no files under ${displayTree.path}.',
            style: context.vwFinePrint,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ScanColumnView(
      root: displayTree,
      selectionChain: List.unmodifiable(_columnChain),
      onSelect: _onColumnSelect,
      formatBytes: _fmt,
      selectedEntryIds: _selected,
      busy: _s.deleting || _s.scanning,
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filteredSortedEntries();
    final hasResults = _s.lastSnapshot != null;
    final restoring = _s.restoringSnapshot;
    final displayTree = hasResults ? _getDisplayTree() : null;

    return Scaffold(
      backgroundColor: context.volward.canvasParchment,
      body: Column(
        children: [
          _buildTopNav(context),
          Expanded(
            child: hasResults
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCompactResultsChrome(
                        context,
                        entries: entries,
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
                                      entries,
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
                : restoring
                ? Center(
                    child: Text(
                      'Restoring previous scan…',
                      style: context.vwFinePrint,
                    ),
                  )
                : CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _buildScanSection(context)),
                      const SliverToBoxAdapter(child: SizedBox(height: 72)),
                    ],
                  ),
          ),
          _buildStickyBar(context, entries),
        ],
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
          Text(
            '·',
            style: context.vwNavLinkMuted,
          ),
          const SizedBox(width: AppleSpacing.sm),
          Text(
            'Storage steward',
            style: context.vwNavLinkMuted,
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Settings',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.settings_outlined, size: 18, color: v.bodyMuted),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(
                    themeSettings: widget.themeSettings,
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
    if (!_s.ready) {
      return Row(
        children: [
          Icon(Icons.hourglass_empty, size: 14, color: v.inkMuted48),
          const SizedBox(width: AppleSpacing.xxs),
          Expanded(
            child: Text(
              _s.initError ?? 'Loading engine…',
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
          border: Border.all(
            color: v.danger.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Native library outdated',
              style: context.vwCaptionStrong,
            ),
            const SizedBox(height: AppleSpacing.xxs),
            Text(
              'Rebuild Rust (apps/volward/macos/build_rust.sh) and fully restart (R).',
              style: context.vwFinePrint,
            ),
          ],
        ),
      );
    }

    if (_s.deepScanReady) {
      return Row(
        children: [
          Icon(Icons.check_circle, size: 14, color: v.primary),
          const SizedBox(width: AppleSpacing.xxs),
          Expanded(
            child: Text(
              'Full Disk Access enabled — deep scan on.',
              style: context.vwFinePrint,
            ),
          ),
        ],
      );
    }

    if (!_permissionBannerExpanded) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 14, color: v.warning),
          const SizedBox(width: AppleSpacing.xxs),
          Expanded(
            child: Text(
              'Full Disk Access recommended for ~/Library cache scan.',
              style: context.vwFinePrint,
            ),
          ),
          AppleButton(
            label: 'Open Settings',
            icon: Icons.open_in_new,
            variant: AppleButtonVariant.secondary,
            onPressed: _openFullDiskAccessSettings,
          ),
          IconButton(
            icon: Icon(Icons.expand_more, size: 18, color: v.inkMuted80),
            tooltip: 'Show details',
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
        border: Border.all(
          color: v.warning.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Full Disk Access recommended',
                  style: context.vwCaptionStrong,
                ),
              ),
              IconButton(
                icon: Icon(Icons.expand_less, size: 18, color: v.inkMuted80),
                tooltip: 'Hide details',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () =>
                    setState(() => _permissionBannerExpanded = false),
              ),
            ],
          ),
          const SizedBox(height: AppleSpacing.xxs),
          Text(
            'System Settings → Privacy & Security → Full Disk Access → enable Volward. '
            'Debug builds: tap +, Cmd+Shift+G, select volward.app.',
            style: context.vwFinePrint,
          ),
          if (MacosSettings.appBundlePath() case final path?) ...[
            const SizedBox(height: AppleSpacing.xxs),
            Text(
              'App path: $path',
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
                label: 'Open Settings',
                icon: Icons.open_in_new,
                variant: AppleButtonVariant.secondary,
                onPressed: _openFullDiskAccessSettings,
              ),
              AppleButton(
                label: 'Copy .app path',
                icon: Icons.copy,
                variant: AppleButtonVariant.pearl,
                onPressed: _copyAppBundlePath,
              ),
              AppleButton(
                label: 'Check again',
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
    return _pad(
      AppleUtilityCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPermissionBanner(context),
            const SizedBox(height: AppleSpacing.sm),
            Divider(height: 1, color: v.hairline),
            const SizedBox(height: AppleSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Target',
                        style: context.vwCaptionStrong,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _s.scanTargetLabel,
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
                      label: 'Folder…',
                      icon: Icons.folder_open_outlined,
                      variant: AppleButtonVariant.secondary,
                      onPressed: _s.scanning ? null : _pickFolder,
                    ),
                    if (_s.scanRoots.isNotEmpty)
                      AppleButton(
                        label: 'Home',
                        icon: Icons.home_outlined,
                        variant: AppleButtonVariant.pearl,
                        onPressed: _s.scanning
                            ? null
                            : () async {
                                _s.clearScanRoots();
                                setState(() => _scanStatus = null);
                                await _s.previewTarget();
                              },
                      ),
                    if (_s.scanning)
                      AppleButton(
                        label: 'Cancel',
                        icon: Icons.stop_outlined,
                        variant: AppleButtonVariant.darkUtility,
                        onPressed: _s.cancelScan,
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppleSpacing.sm),
            Tooltip(
              message: _s.canUseIncrementalScan
                  ? '复用未变化的文件夹，加快后续扫描（需先完成一次全量扫描）'
                  : '需要 rebuild Rust 后才可使用增量扫描',
              child: IgnorePointer(
                ignoring: _s.scanning || !_s.canUseIncrementalScan,
                child: Opacity(
                  opacity:
                      (_s.scanning || !_s.canUseIncrementalScan) ? 0.5 : 1,
                  child: AppleOptionChip(
                    label: '增量扫描',
                    selected: _s.incrementalScan,
                    onSelected: _s.setIncrementalScan,
                  ),
                ),
              ),
            ),
            if (_s.scanning) ...[
              const SizedBox(height: AppleSpacing.sm),
              const ClipRRect(
                borderRadius: BorderRadius.all(
                  Radius.circular(AppleRadius.pill),
                ),
                child: LinearProgressIndicator(minHeight: 3),
              ),
              const SizedBox(height: AppleSpacing.xxs),
              Text(
                _scanProgressSummary(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.vwFinePrint,
              ),
              if (_s.scanRoots.isEmpty) ...[
                const SizedBox(height: AppleSpacing.xxs),
                Text(
                  'Full Home scan can take many minutes on large accounts — watch the item count above.',
                  style: context.vwFinePrint,
                ),
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
    final stats = _s.lastSnapshot?['stats'];
    final filesSeen = stats is Map ? (stats['files_seen'] as num?)?.toInt() : null;
    final count = filesSeen ?? tree.subtreeFileCount ?? tree.fileCount;
    return '$count in tree · ${_fmt(tree.displayBytes)}';
  }

  Widget _buildItemPreview(BuildContext context, ScanTreeNode? focus) {
    final v = context.volward;
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
              child: Text(
                'Select a folder or file',
                style: context.vwFinePrint,
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

    final entry = focus.entry;
    final isDir = focus.isDirectory;
    final size = isDir
        ? focus.displayBytes
        : (entry?['size_bytes'] as num? ?? focus.sizeBytes);
    final subtreeItems = isDir ? focus.fileCount : 0;
    final category = entry?['category']?.toString() ?? (isDir ? 'Folder' : '—');
    final deletable = entry?['deletable'] == true;
    final entryId = entry?['id']?.toString() ?? focus.entryId;
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
                        '${isDir ? ' · $subtreeItems items' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.vwFinePrint,
                      ),
                    ],
                  ),
                ),
                if (!isDir && deletable && entryId != null)
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

  Widget _buildStickyBar(BuildContext context, List<Map<String, dynamic>> entries) {
    final busy = _s.deleting || _s.scanning;
    final String label;
    final String actionLabel;
    final VoidCallback? actionPressed;
    final IconData? actionIcon;

    if (_s.scanning) {
      label = _scanProgressSummary();
      actionLabel = 'Cancel';
      actionIcon = Icons.stop_outlined;
      actionPressed = _s.cancelScan;
    } else if (_selected.isNotEmpty) {
      label =
          'Selected: ${_selected.length} · ${_fmt(_selectedBytes(entries))}';
      actionLabel = busy ? 'Working…' : 'Move to Trash';
      actionIcon = busy ? null : Icons.delete_outline;
      actionPressed = busy ? null : _confirmDelete;
    } else {
      final hasResults = _s.lastSnapshot != null;
      label = hasResults
          ? 'Browse results · tap folders below'
          : (_s.ready ? 'Ready to scan' : 'Loading engine…');
      actionLabel = hasResults ? 'Rescan' : 'Start scan';
      actionIcon = Icons.search;
      actionPressed = (_s.ready && !busy && _s.hasSnapshotFileApi)
          ? _startScan
          : null;
    }

    return AppleStickyBar(
      leading: Text(label, style: context.vwCaption),
      action: AppleButton(
        label: actionLabel,
        icon: actionIcon,
        onPressed: actionPressed,
      ),
    );
  }
}
