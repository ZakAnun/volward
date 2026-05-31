import 'package:flutter/material.dart';

import '../../volward_session.dart';

class ConfirmPage extends StatelessWidget {
  const ConfirmPage({super.key, required this.session});

  final VolwardSession session;

  @override
  Widget build(BuildContext context) {
    final snap = session.lastSnapshot;
    final deletable = <Map<String, dynamic>>[];
    if (snap != null && snap['entries'] is List) {
      for (final e in snap['entries'] as List) {
        if (e is Map && e['deletable'] == true) {
          deletable.add(Map<String, dynamic>.from(e));
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Confirm cleanup', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            'MVP scaffold: deletion API is wired in Rust (trash). UI confirmation flow comes in W3.',
          ),
          const SizedBox(height: 16),
          Text('Deletable items in last snapshot: ${deletable.length}'),
          const Spacer(),
          FilledButton(
            onPressed: deletable.isEmpty
                ? null
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Delete not enabled in UI yet — use CLI or extend ConfirmPage.',
                        ),
                      ),
                    );
                  },
            child: const Text('Review & delete (stub)'),
          ),
        ],
      ),
    );
  }
}
