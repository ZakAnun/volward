import 'package:flutter/material.dart';

import '../../theme/apple_tokens.dart';
import '../../volward_session.dart';
import '../../widgets/apple_widgets.dart';

String _formatBytes(num? bytes) {
  if (bytes == null) return '—';
  final b = bytes.toInt();
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) {
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

enum _SortMode { sizeDesc, sizeAsc, nameAsc }

class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key, required this.session});

  final VolwardSession session;

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  String? _categoryFilter;
  bool _deletableOnly = false;
  _SortMode _sort = _SortMode.sizeDesc;
  final Set<String> _localSelected = {};

  static const _categoryChips = [
    null,
    'Cache',
    'Temp',
    'Media',
    'Unknown',
    'System',
  ];

  List<Map<String, dynamic>> _filteredSortedEntries() {
    final snap = widget.session.lastSnapshot;
    if (snap == null || snap['entries'] is! List) return [];
    final raw = (snap['entries'] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    Iterable<Map<String, dynamic>> out = raw;
    if (_categoryFilter != null) {
      out = out.where((e) => e['category']?.toString() == _categoryFilter);
    }
    if (_deletableOnly) {
      out = out.where((e) => e['deletable'] == true);
    }
    final list = out.toList();
    switch (_sort) {
      case _SortMode.sizeDesc:
        list.sort(
          (a, b) => ((b['size_bytes'] as num?) ?? 0).compareTo((a['size_bytes'] as num?) ?? 0),
        );
      case _SortMode.sizeAsc:
        list.sort(
          (a, b) => ((a['size_bytes'] as num?) ?? 0).compareTo((b['size_bytes'] as num?) ?? 0),
        );
      case _SortMode.nameAsc:
        list.sort(
          (a, b) => (a['display_name']?.toString() ?? '')
              .compareTo(b['display_name']?.toString() ?? ''),
        );
    }
    return list;
  }

  int _selectedBytes(List<Map<String, dynamic>> entries) {
    var total = 0;
    for (final e in entries) {
      final id = e['id']?.toString();
      if (id != null && _localSelected.contains(id)) {
        total += (e['size_bytes'] as num?)?.toInt() ?? 0;
      }
    }
    return total;
  }

  String _sortLabel(_SortMode mode) {
    switch (mode) {
      case _SortMode.sizeDesc:
        return 'Size ↓';
      case _SortMode.sizeAsc:
        return 'Size ↑';
      case _SortMode.nameAsc:
        return 'Name A–Z';
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.session.lastSnapshot;
    if (snap == null) {
      return const ColoredBox(
        color: AppleColors.canvasParchment,
        child: Center(
          child: Text(
            'No scan yet. Run a scan from the Scan tab.',
            style: AppleTypography.body,
          ),
        ),
      );
    }

    final entries = _filteredSortedEntries();
    final reclaimable = snap['reclaimable_estimate_bytes'];

    return ColoredBox(
      color: AppleColors.canvasParchment,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppleSpacing.xl,
              AppleSpacing.xl,
              AppleSpacing.xl,
              AppleSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppleSectionHeader(title: 'Results'),
                const SizedBox(height: AppleSpacing.sm),
                Text(
                  'Reclaimable estimate: ${_formatBytes(reclaimable)}',
                  style: AppleTypography.body,
                ),
                Text(
                  'Showing ${entries.length} entries',
                  style: AppleTypography.caption,
                ),
                const SizedBox(height: AppleSpacing.lg),
                Wrap(
                  spacing: AppleSpacing.xs,
                  runSpacing: AppleSpacing.xs,
                  children: _categoryChips.map((cat) {
                    final label = cat ?? 'All';
                    return AppleOptionChip(
                      label: label,
                      selected: _categoryFilter == cat,
                      onSelected: (_) => setState(() => _categoryFilter = cat),
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppleSpacing.sm),
                Wrap(
                  spacing: AppleSpacing.xs,
                  runSpacing: AppleSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppleOptionChip(
                      label: 'Deletable only',
                      selected: _deletableOnly,
                      onSelected: (v) => setState(() => _deletableOnly = v),
                    ),
                    for (final mode in _SortMode.values)
                      AppleOptionChip(
                        label: _sortLabel(mode),
                        selected: _sort == mode,
                        onSelected: (_) => setState(() => _sort = mode),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: Text('No entries match the current filters.', style: AppleTypography.body),
                  )
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppleColors.canvas,
                      border: Border.all(color: AppleColors.hairline),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppleRadius.lg)),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppleRadius.lg)),
                      child: ListView.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final e = entries[i];
                          final id = e['id']?.toString() ?? '$i';
                          final name = e['display_name']?.toString() ?? id;
                          final category = e['category']?.toString() ?? '';
                          final deletable = e['deletable'] == true;
                          final selected = _localSelected.contains(id);

                          return AppleListRow(
                            title: name,
                            subtitle: '$category · ${_formatBytes(e['size_bytes'])}',
                            selected: selected,
                            leading: Checkbox(
                              value: selected,
                              onChanged: !deletable
                                  ? null
                                  : (v) {
                                      setState(() {
                                        if (v == true) {
                                          _localSelected.add(id);
                                        } else {
                                          _localSelected.remove(id);
                                        }
                                      });
                                    },
                            ),
                            trailing: deletable
                                ? Icon(Icons.delete_outline, size: 20, color: AppleColors.inkMuted48)
                                : null,
                            onTap: !deletable
                                ? null
                                : () {
                                    setState(() {
                                      if (selected) {
                                        _localSelected.remove(id);
                                      } else {
                                        _localSelected.add(id);
                                      }
                                    });
                                  },
                          );
                        },
                      ),
                    ),
                  ),
          ),
          if (_localSelected.isNotEmpty)
            AppleStickyBar(
              leading: Text(
                'Selected: ${_localSelected.length} · ${_formatBytes(_selectedBytes(entries))}',
                style: AppleTypography.body,
              ),
              action: AppleButton(
                label: 'Continue (${_localSelected.length})',
                onPressed: () {
                  widget.session.setSelectedEntryIds(_localSelected);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${_localSelected.length} items ready on Confirm tab',
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
