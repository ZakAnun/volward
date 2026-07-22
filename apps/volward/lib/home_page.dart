import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'theme/apple_tokens.dart';
import 'volward_session.dart';
import 'widgets/apple_widgets.dart';

enum _SortMode { sizeDesc, sizeAsc, nameAsc }

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.session});
  final VolwardSession session;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _scanStatus;
  String? _categoryFilter;
  bool _deletableOnly = false;
  _SortMode _sort = _SortMode.sizeDesc;
  final Set<String> _selected = {};
  bool _prevScanning = false;

  VolwardSession get _s => widget.session;

  static const _categoryChips = [
    null, 'Cache', 'Temp', 'Media', 'Unknown', 'System',
  ];

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!_prevScanning && _s.scanning) {
      setState(() { _selected.clear(); _scanStatus = null; });
    }
    _prevScanning = _s.scanning;
    setState(() {});
  }

  static String _fmt(num? bytes) {
    if (bytes == null) return '—';
    final b = bytes.toInt();
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(2)} GB';
  }

  String? _progressLine() {
    final p = _s.scanProgress;
    if (p == null) return null;
    final phase = p['phase']?.toString() ?? '';
    final paths = p['paths_seen'];
    final current = p['current_path']?.toString();
    final buf = StringBuffer(_phaseLabel(phase));
    if (paths != null && paths != 0) buf.write(' · $paths items');
    if (current != null && current.isNotEmpty) buf.write('\n$current');
    return buf.toString();
  }

  String _phaseLabel(String phase) => const {
    'DiscoveringRoots': 'Discovering roots…',
    'Walking': 'Scanning files…',
    'Classifying': 'Classifying entries…',
    'Aggregating': 'Aggregating results…',
    'Done': 'Done',
  }[phase] ?? phase;

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
    final snap = _s.lastSnapshot;
    if (snap == null || snap['entries'] is! List) return [];
    Iterable<Map<String, dynamic>> out = (snap['entries'] as List)
        .whereType<Map>().map((e) => Map<String, dynamic>.from(e));
    if (_categoryFilter != null) {
      out = out.where((e) => e['category']?.toString() == _categoryFilter);
    }
    if (_deletableOnly) out = out.where((e) => e['deletable'] == true);
    final list = out.toList();
    switch (_sort) {
      case _SortMode.sizeDesc:
        list.sort((a, b) => ((b['size_bytes'] as num?) ?? 0).compareTo((a['size_bytes'] as num?) ?? 0));
      case _SortMode.sizeAsc:
        list.sort((a, b) => ((a['size_bytes'] as num?) ?? 0).compareTo((b['size_bytes'] as num?) ?? 0));
      case _SortMode.nameAsc:
        list.sort((a, b) => (a['display_name']?.toString() ?? '').compareTo(b['display_name']?.toString() ?? ''));
    }
    return list;
  }

  Future<void> _pickFolder() async {
    final path = await getDirectoryPath(confirmButtonText: 'Select');
    if (path != null) _s.setScanRoots([path]);
  }

  Future<void> _startScan() async {
    if (!_s.ready) return;
    try {
      final id = await _s.runScan();
      if (!mounted) return;
      final count = _s.lastSnapshot?['entries'] is List
          ? (_s.lastSnapshot!['entries'] as List).length : 0;
      setState(() => _scanStatus = 'Found $count items · $id');
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanStatus = 'Scan failed: $e');
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
          AppleButton(label: 'Cancel', variant: AppleButtonVariant.pearl, onPressed: () => Navigator.pop(ctx, false)),
          AppleButton(label: 'Delete', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final report = await _s.deleteEntries(_selected.toList(), rescanAfterDelete: true);
      if (!mounted) return;
      setState(_selected.clear);
      final freedAfter = (report['freed_bytes'] as num?)?.toInt() ?? 0;
      final failed = report['failed_paths'];
      final failedCount = failed is List ? failed.length : 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        failedCount > 0
            ? 'Deleted with $failedCount failure(s). Freed ${_fmt(freedAfter)}.'
            : 'Moved to Trash. Freed ${_fmt(freedAfter)}. Rescan complete.',
      )));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  // Simple section wrapper — no nested scroll view
  Widget _pad(Widget child, {EdgeInsets padding = const EdgeInsets.all(AppleSpacing.xl)}) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Padding(padding: padding, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filteredSortedEntries();
    final hasResults = _s.lastSnapshot != null;
    return Scaffold(
      backgroundColor: AppleColors.canvasParchment,
      body: Column(
        children: [
          _buildTopNav(),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildStatusCard()),
                SliverToBoxAdapter(child: _buildScanCard()),
                if (hasResults) ...[
                  SliverToBoxAdapter(child: _buildResultsHeader(entries)),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _buildResultsListItem(entries[i]),
                      childCount: entries.length,
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
          _buildStickyBar(entries),
        ],
      ),
    );
  }

  Widget _buildTopNav() {
    return Container(
      height: 44,
      color: AppleColors.surfaceBlack,
      padding: const EdgeInsets.symmetric(horizontal: AppleSpacing.lg),
      child: Row(
        children: [
          Text('Volward', style: AppleTypography.navLink.copyWith(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.14)),
          const Spacer(),
          Text('Storage steward', style: AppleTypography.navLink.copyWith(color: AppleColors.bodyMuted)),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return _pad(AppleUtilityCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Engine status', style: AppleTypography.bodyStrong),
                  const SizedBox(height: 4),
                  Text(_s.ready ? (_s.deepScanReady ? 'Full disk access granted' : 'Limited access — grant FDA') : (_s.initError ?? 'Loading…'), style: AppleTypography.caption),
                ],
              ),
            ),
            Icon(_s.deepScanReady ? Icons.check_circle : Icons.warning_amber_rounded, color: _s.deepScanReady ? AppleColors.primary : const Color(0xFFFF9500)),
          ],
        ),
      ),
    );
  }

  Widget _buildScanCard() {
    return _pad(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppleSectionHeader(title: 'Scan', subtitle: 'Choose a folder and scan for reclaimable storage.'),
          const SizedBox(height: AppleSpacing.lg),
          AppleUtilityCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Target', style: AppleTypography.captionStrong),
                const SizedBox(height: 4),
                Text(_s.scanTargetLabel, style: AppleTypography.body),
                if (_s.scanning) ...[
                  const SizedBox(height: AppleSpacing.lg),
                  const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(AppleRadius.pill)),
                    child: LinearProgressIndicator(minHeight: 4),
                  ),
                  if (_progressLine() != null) ...[
                    const SizedBox(height: AppleSpacing.sm),
                    Text(_progressLine()!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppleTypography.caption),
                  ],
                ],
                if (_scanStatus != null && !_s.scanning) ...[
                  const SizedBox(height: AppleSpacing.sm),
                  Text(_scanStatus!, style: AppleTypography.caption),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppleSpacing.lg),
          Wrap(
            spacing: AppleSpacing.sm,
            runSpacing: AppleSpacing.sm,
            children: [
              AppleButton(label: 'Choose folder…', icon: Icons.folder_open_outlined, variant: AppleButtonVariant.secondary, onPressed: _s.scanning ? null : _pickFolder),
              AppleButton(label: 'Reset to Home', icon: Icons.home_outlined, variant: AppleButtonVariant.pearl, onPressed: (_s.scanning || _s.scanRoots.isEmpty) ? null : () { _s.clearScanRoots(); setState(() => _scanStatus = null); }),
              if (_s.scanning)
                AppleButton(label: 'Cancel', icon: Icons.stop_outlined, variant: AppleButtonVariant.darkUtility, onPressed: _s.cancelScan),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsHeader(List<Map<String, dynamic>> entries) {
    final snap = _s.lastSnapshot;
    final reclaimable = snap?['reclaimable_estimate_bytes'];
    return _pad(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppleSectionHeader(title: 'Results', subtitle: '${entries.length} entries · Reclaimable: ${_fmt(reclaimable)}'),
          const SizedBox(height: AppleSpacing.lg),
          Wrap(spacing: AppleSpacing.xs, runSpacing: AppleSpacing.xs, children: [
            for (final cat in _categoryChips)
              AppleOptionChip(label: cat ?? 'All', selected: _categoryFilter == cat, onSelected: (_) => setState(() => _categoryFilter = cat)),
          ]),
          const SizedBox(height: AppleSpacing.xs),
          Wrap(spacing: AppleSpacing.xs, runSpacing: AppleSpacing.xs, children: [
            AppleOptionChip(label: 'Deletable only', selected: _deletableOnly, onSelected: (v) => setState(() => _deletableOnly = v)),
            AppleOptionChip(label: 'Size ↓', selected: _sort == _SortMode.sizeDesc, onSelected: (_) => setState(() => _sort = _SortMode.sizeDesc)),
            AppleOptionChip(label: 'Size ↑', selected: _sort == _SortMode.sizeAsc, onSelected: (_) => setState(() => _sort = _SortMode.sizeAsc)),
            AppleOptionChip(label: 'Name A–Z', selected: _sort == _SortMode.nameAsc, onSelected: (_) => setState(() => _sort = _SortMode.nameAsc)),
          ]),
          const SizedBox(height: AppleSpacing.sm),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(AppleSpacing.xl, 0, AppleSpacing.xl, AppleSpacing.sm),
    );
  }

  Widget _buildResultsListItem(Map<String, dynamic> e) {
    final id = e['id']?.toString() ?? '';
    final name = e['display_name']?.toString() ?? id;
    final category = e['category']?.toString() ?? '';
    final deletable = e['deletable'] == true;
    final selected = _selected.contains(id);
    final busy = _s.deleting || _s.scanning;
    return Container(
      decoration: BoxDecoration(
        color: selected ? AppleColors.primary.withValues(alpha: 0.06) : AppleColors.canvas,
        border: const Border(bottom: BorderSide(color: AppleColors.hairline, width: 0.5)),
      ),
      child: AppleListRow(
        title: name,
        subtitle: '$category · ${_fmt(e['size_bytes'] as num?)}',
        selected: selected,
        leading: Checkbox(
          value: selected,
          onChanged: (!deletable || busy) ? null : (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
        ),
        trailing: deletable ? Icon(Icons.delete_outline, size: 18, color: AppleColors.inkMuted48) : null,
        onTap: (!deletable || busy) ? null : () => setState(() => selected ? _selected.remove(id) : _selected.add(id)),
      ),
    );
  }

  Widget _buildStickyBar(List<Map<String, dynamic>> entries) {
    final busy = _s.deleting || _s.scanning;
    final String label;
    final String actionLabel;
    final VoidCallback? actionPressed;
    final IconData? actionIcon;

    if (_s.scanning) {
      label = 'Scan in progress…';
      actionLabel = 'Cancel';
      actionIcon = Icons.stop_outlined;
      actionPressed = _s.cancelScan;
    } else if (_selected.isNotEmpty) {
      label = 'Selected: ${_selected.length} · ${_fmt(_selectedBytes(entries))}';
      actionLabel = busy ? 'Working…' : 'Move to Trash';
      actionIcon = busy ? null : Icons.delete_outline;
      actionPressed = busy ? null : _confirmDelete;
    } else {
      label = _s.ready ? 'Ready to scan' : 'Loading engine…';
      actionLabel = 'Start scan';
      actionIcon = Icons.search;
      actionPressed = (_s.ready && !busy) ? _startScan : null;
    }

    return AppleStickyBar(
      leading: Text(label, style: AppleTypography.body),
      action: AppleButton(label: actionLabel, icon: actionIcon, onPressed: actionPressed),
    );
  }
}

