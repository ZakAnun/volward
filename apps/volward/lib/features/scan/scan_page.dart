import 'package:file_selector/file_selector.dart';
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

  Future<void> _pickFolder() async {
    final path = await getDirectoryPath(confirmButtonText: 'Select');
    if (path != null) {
      widget.session.setScanRoots([path]);
      setState(() => _status = 'Scan target: $path');
    }
  }

  Future<void> _start() async {
    if (!widget.session.ready) {
      setState(() => _status = widget.session.initError ?? 'Engine not ready');
      return;
    }
    setState(
      () => _status = 'Scanning ${widget.session.scanTargetLabel} in background…',
    );
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

  String _phaseLabel(String phase) {
    switch (phase) {
      case 'DiscoveringRoots':
        return 'Discovering roots…';
      case 'Walking':
        return 'Scanning files';
      case 'Classifying':
        return 'Classifying entries';
      case 'Aggregating':
        return 'Aggregating results';
      case 'Done':
        return 'Done';
      default:
        return phase;
    }
  }

  String? _progressLine() {
    final p = widget.session.scanProgress;
    if (p == null) return null;
    final phase = p['phase']?.toString() ?? '';
    final paths = p['paths_seen'];
    final current = p['current_path']?.toString();
    final buf = StringBuffer(_phaseLabel(phase));
    if (paths != null && paths != 0) {
      buf.write(' · $paths items seen');
    }
    if (current != null && current.isNotEmpty) {
      buf.write('\n$current');
    }
    return buf.toString();
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
          const Text(
            'Scans via Rust Core + platform-desktop (max depth 8). '
            'The UI stays responsive while scanning.',
          ),
          const SizedBox(height: 12),
          Text('Target: ${widget.session.scanTargetLabel}'),
          if (widget.session.scanning) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            if (_progressLine() != null) ...[
              const SizedBox(height: 8),
              Text(
                _progressLine()!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
          const SizedBox(height: 24),
          if (_status != null) Text(_status!),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: widget.session.scanning ? null : _pickFolder,
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose folder…'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.session.scanning || widget.session.scanRoots.isEmpty
                ? null
                : () {
                    widget.session.clearScanRoots();
                    setState(() => _status = 'Reset to Home (default)');
                  },
            icon: const Icon(Icons.home),
            label: const Text('Reset to Home'),
          ),
          const SizedBox(height: 12),
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
