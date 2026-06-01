import 'package:flutter/material.dart';

import '../../volward_session.dart';

String _formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.toInt()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class ConfirmPage extends StatefulWidget {
  const ConfirmPage({super.key, required this.session});

  final VolwardSession session;

  @override
  State<ConfirmPage> createState() => _ConfirmPageState();
}

class _ConfirmPageState extends State<ConfirmPage> {
  final Set<String> _selected = {};

  List<Map<String, dynamic>> _deletableEntries() {
    final snap = widget.session.lastSnapshot;
    final out = <Map<String, dynamic>>[];
    if (snap != null && snap['entries'] is List) {
      for (final e in snap['entries'] as List) {
        if (e is Map && e['deletable'] == true) {
          out.add(Map<String, dynamic>.from(e));
        }
      }
    }
    return out;
  }

  int _selectedBytes() {
    final entries = _deletableEntries();
    var total = 0;
    for (final e in entries) {
      if (_selected.contains(e['id']?.toString())) {
        total += (e['size_bytes'] as num?)?.toInt() ?? 0;
      }
    }
    return total;
  }

  Future<void> _confirmDelete(BuildContext context) async {
    if (_selected.isEmpty) return;

    final preview = await widget.session.deleteEntries(
      _selected.toList(),
      dryRun: true,
    );
    if (!context.mounted) return;

    final count = (preview['deleted_count'] as num?)?.toInt() ?? 0;
    final freed = (preview['freed_bytes'] as num?)?.toInt() ?? 0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to Trash?'),
        content: Text(
          'Move $count item(s) to Trash and free about ${_formatBytes(freed)}?\n\n'
          'You can restore them from Trash if needed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true || !context.mounted) return;

    try {
      final report = await widget.session.deleteEntries(
        _selected.toList(),
        rescanAfterDelete: true,
      );
      if (!context.mounted) return;
      setState(_selected.clear);
      final freedAfter = (report['freed_bytes'] as num?)?.toInt() ?? 0;
      final failed = report['failed_paths'];
      final failedCount = failed is List ? failed.length : 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failedCount > 0
                ? 'Deleted with $failedCount failure(s). Freed ${_formatBytes(freedAfter)}. Rescan complete.'
                : 'Moved to Trash. Freed ${_formatBytes(freedAfter)}. Rescan complete.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final deletable = _deletableEntries();
    final busy = widget.session.deleting || widget.session.scanning;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Confirm cleanup', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            deletable.isEmpty
                ? 'Run a scan first, or no deletable items were found.'
                : 'Select items to move to Trash (${deletable.length} deletable).',
          ),
          if (widget.session.lastDeleteReport != null) ...[
            const SizedBox(height: 12),
            Text(
              'Last cleanup freed ${_formatBytes((widget.session.lastDeleteReport!['freed_bytes'] as num?) ?? 0)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: deletable.isEmpty
                ? const Center(child: Text('Nothing to delete yet.'))
                : ListView.builder(
                    itemCount: deletable.length,
                    itemBuilder: (context, i) {
                      final e = deletable[i];
                      final id = e['id']?.toString() ?? '$i';
                      final name = e['display_name']?.toString() ?? id;
                      final size = (e['size_bytes'] as num?)?.toInt() ?? 0;
                      return CheckboxListTile(
                        value: _selected.contains(id),
                        onChanged: busy
                            ? null
                            : (v) {
                                setState(() {
                                  if (v == true) {
                                    _selected.add(id);
                                  } else {
                                    _selected.remove(id);
                                  }
                                });
                              },
                        title: Text(name),
                        subtitle: Text(_formatBytes(size)),
                        secondary: const Icon(Icons.delete_outline),
                      );
                    },
                  ),
          ),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Selected: ${_selected.length} · ${_formatBytes(_selectedBytes())}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          FilledButton.icon(
            onPressed: busy || _selected.isEmpty ? null : () => _confirmDelete(context),
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_forever),
            label: Text(busy ? 'Working…' : 'Move selected to Trash'),
          ),
        ],
      ),
    );
  }
}
