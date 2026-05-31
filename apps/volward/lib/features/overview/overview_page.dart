import 'package:flutter/material.dart';

import '../../volward_session.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.session});

  final VolwardSession session;

  @override
  Widget build(BuildContext context) {
    if (session.initError != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Native engine failed', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(session.initError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 16),
          const Text(
            'Rebuild with: fvm flutter run -d macos\n'
            'Ensure macos/build_rust.sh copied libvolward_facade.dylib into the app bundle.',
          ),
        ],
      );
    }

    if (!session.ready) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading Rust engine…'),
          ],
        ),
      );
    }

    final caps = session.capabilities;
    final level = caps['level']?.toString() ?? 'unknown';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Volward', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Your storage steward.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            title: const Text('Capability level'),
            subtitle: Text(level),
            trailing: Icon(
              session.deepScanReady ? Icons.check_circle : Icons.warning_amber,
              color: session.deepScanReady ? Colors.green : Colors.orange,
            ),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Deep scan ready'),
            subtitle: Text(session.deepScanReady ? 'Yes' : 'No — see hints below'),
          ),
        ),
        if (session.permissionHints.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Permission hints', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...session.permissionHints.map(
            (h) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('• $h'),
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () async {
            await session.refreshCapabilities();
            if (!context.mounted) return;
            final msg = session.lastError ?? 'Capabilities refreshed';
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh capabilities'),
        ),
      ],
    );
  }
}
