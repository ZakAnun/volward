import 'package:flutter/material.dart';

import '../../volward_session.dart';

class ResultsPage extends StatelessWidget {
  const ResultsPage({super.key, required this.session});

  final VolwardSession session;

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

  @override
  Widget build(BuildContext context) {
    final snap = session.lastSnapshot;
    if (snap == null) {
      return const Center(
        child: Text('No scan yet. Run a scan from the Scan tab.'),
      );
    }

    final entries = snap['entries'];
    final list = entries is List ? entries : <dynamic>[];
    final reclaimable = snap['reclaimable_estimate_bytes'];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          title: const Text('Reclaimable estimate'),
          subtitle: Text(_formatBytes(reclaimable)),
        ),
        ListTile(
          title: const Text('Entries (top files)'),
          subtitle: Text('${list.length} items'),
        ),
        const Divider(),
        ...list.take(50).map((e) {
          final m = e is Map ? e : <String, dynamic>{};
          final name = m['display_name']?.toString() ?? m['path_or_uri']?.toString() ?? '?';
          final size = m['size_bytes'];
          final category = m['category']?.toString() ?? '';
          final deletable = m['deletable'] == true;
          return ListTile(
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('$category · ${_formatBytes(size)}'),
            trailing: deletable ? const Icon(Icons.delete_outline) : null,
          );
        }),
      ],
    );
  }
}
