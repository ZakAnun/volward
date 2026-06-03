import 'package:flutter/material.dart';

import '../../volward_session.dart';

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

  @override
  Widget build(BuildContext context) {
    final snap = widget.session.lastSnapshot;
    if (snap == null) {
      return const Center(
        child: Text('No scan yet. Run a scan from the Scan tab.'),
      );
    }

    final entries = _filteredSortedEntries();
    final reclaimable = snap['reclaimable_estimate_bytes'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Results', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('Reclaimable estimate: ${_formatBytes(reclaimable)}'),
              Text('Showing ${entries.length} entries'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _categoryChips.map((cat) {
                  final label = cat ?? 'All';
                  final selected = _categoryFilter == cat;
                  return FilterChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _categoryFilter = cat);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  FilterChip(
                    label: const Text('Deletable only'),
                    selected: _deletableOnly,
                    onSelected: (v) => setState(() => _deletableOnly = v),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<_SortMode>(
                    value: _sort,
                    items: const [
                      DropdownMenuItem(value: _SortMode.sizeDesc, child: Text('Size ↓')),
                      DropdownMenuItem(value: _SortMode.sizeAsc, child: Text('Size ↑')),
                      DropdownMenuItem(value: _SortMode.nameAsc, child: Text('Name A–Z')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _sort = v);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              final id = e['id']?.toString() ?? '$i';
              final name = e['display_name']?.toString() ?? id;
              final category = e['category']?.toString() ?? '';
              final deletable = e['deletable'] == true;
              return CheckboxListTile(
                value: _localSelected.contains(id),
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
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('$category · ${_formatBytes(e['size_bytes'])}'),
                secondary: deletable ? const Icon(Icons.delete_outline) : null,
              );
            },
          ),
        ),
        if (_localSelected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Selected: ${_localSelected.length} · ${_formatBytes(_selectedBytes(entries))}',
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _localSelected.isEmpty
                ? null
                : () {
                    widget.session.setSelectedEntryIds(_localSelected);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${_localSelected.length} items ready on Confirm tab',
                        ),
                      ),
                    );
                  },
            child: Text('Continue to Confirm (${_localSelected.length})'),
          ),
        ),
      ],
    );
  }
}
