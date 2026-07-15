import 'package:flutter/material.dart';

import '../../theme/apple_tokens.dart';
import '../../volward_session.dart';
import '../../widgets/apple_widgets.dart';

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

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.session.selectedEntryIds);
    widget.session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (widget.session.selectedEntryIds.isEmpty) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(widget.session.selectedEntryIds);
    });
  }

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

    if (ok != true || !context.mounted) return;

    try {
      final report = await widget.session.deleteEntries(
        _selected.toList(),
        rescanAfterDelete: true,
      );
      if (!context.mounted) return;
      setState(_selected.clear);
      widget.session.clearSelectedEntryIds();
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

    return ColoredBox(
      color: AppleColors.canvasParchment,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ApplePageShell(
              maxWidth: 980,
              padding: const EdgeInsets.fromLTRB(
                AppleSpacing.xl,
                AppleSpacing.xl,
                AppleSpacing.xl,
                AppleSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppleSectionHeader(
                    title: 'Confirm cleanup',
                    subtitle: deletable.isEmpty
                        ? 'Run a scan first, or no deletable items were found.'
                        : 'Select items to move to Trash (${deletable.length} deletable).',
                  ),
                  if (widget.session.lastDeleteReport != null) ...[
                    const SizedBox(height: AppleSpacing.sm),
                    Text(
                      'Last cleanup freed ${_formatBytes((widget.session.lastDeleteReport!['freed_bytes'] as num?) ?? 0)}',
                      style: AppleTypography.caption,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: deletable.isEmpty
                ? const Center(
                    child: Text('Nothing to delete yet.', style: AppleTypography.body),
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
                        itemCount: deletable.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final e = deletable[i];
                          final id = e['id']?.toString() ?? '$i';
                          final name = e['display_name']?.toString() ?? id;
                          final size = (e['size_bytes'] as num?)?.toInt() ?? 0;
                          final selected = _selected.contains(id);

                          return AppleListRow(
                            title: name,
                            subtitle: _formatBytes(size),
                            selected: selected,
                            leading: Checkbox(
                              value: selected,
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
                            ),
                            trailing: const Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: AppleColors.inkMuted48,
                            ),
                            onTap: busy
                                ? null
                                : () {
                                    setState(() {
                                      if (selected) {
                                        _selected.remove(id);
                                      } else {
                                        _selected.add(id);
                                      }
                                    });
                                  },
                          );
                        },
                      ),
                    ),
                  ),
          ),
          AppleStickyBar(
            leading: Text(
              _selected.isEmpty
                  ? 'Select items to delete'
                  : 'Selected: ${_selected.length} · ${_formatBytes(_selectedBytes())}',
              style: AppleTypography.body,
            ),
            action: AppleButton(
              label: busy ? 'Working…' : 'Move to Trash',
              icon: busy ? null : Icons.delete_outline,
              onPressed: busy || _selected.isEmpty ? null : () => _confirmDelete(context),
            ),
          ),
        ],
      ),
    );
  }
}
