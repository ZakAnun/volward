import 'package:flutter/material.dart';

import '../../volward_session.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.session});

  final VolwardSession session;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  String? _status;

  Future<void> _start() async {
    if (!widget.session.ready) {
      setState(() => _status = widget.session.initError ?? 'Engine not ready');
      return;
    }
    setState(() => _status = 'Scanning home directory in background (may take ~1 min)…');
    try {
      final id = await widget.session.runScan();
      if (!mounted) return;
      final count = widget.session.lastSnapshot?['entries'] is List
          ? (widget.session.lastSnapshot!['entries'] as List).length
          : 0;
      setState(() => _status = 'Done — snapshot $id ($count entries). See Results tab.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Scan failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Scan', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            'Scans your home directory via Rust Core + platform-desktop (max depth 8). '
            'The UI stays responsive while scanning.',
          ),
          if (widget.session.scanning) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 24),
          if (_status != null) Text(_status!),
          const Spacer(),
          FilledButton.icon(
            onPressed: widget.session.scanning ? null : _start,
            icon: const Icon(Icons.search),
            label: Text(widget.session.scanning ? 'Scanning…' : 'Start scan'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.session.scanning ? widget.session.cancelScan : null,
            icon: const Icon(Icons.stop),
            label: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
