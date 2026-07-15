import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../theme/apple_tokens.dart';
import '../../volward_session.dart';
import '../../widgets/apple_widgets.dart';

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
    return ColoredBox(
      color: AppleColors.canvasParchment,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ApplePageShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppleSectionHeader(
                    title: 'Scan',
                    subtitle: 'Scans via Rust Core + platform-desktop (max depth 8). '
                        'The UI stays responsive while scanning.',
                  ),
                  const SizedBox(height: AppleSpacing.xxl),
                  AppleUtilityCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Target', style: AppleTypography.captionStrong),
                        const SizedBox(height: 4),
                        Text(widget.session.scanTargetLabel, style: AppleTypography.body),
                        if (widget.session.scanning) ...[
                          const SizedBox(height: AppleSpacing.lg),
                          const ClipRRect(
                            borderRadius: BorderRadius.all(Radius.circular(AppleRadius.pill)),
                            child: LinearProgressIndicator(minHeight: 4),
                          ),
                          if (_progressLine() != null) ...[
                            const SizedBox(height: AppleSpacing.sm),
                            Text(
                              _progressLine()!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppleTypography.caption,
                            ),
                          ],
                        ],
                        if (_status != null) ...[
                          const SizedBox(height: AppleSpacing.lg),
                          Text(_status!, style: AppleTypography.caption),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppleSpacing.xxl),
                  Wrap(
                    spacing: AppleSpacing.sm,
                    runSpacing: AppleSpacing.sm,
                    children: [
                      AppleButton(
                        label: 'Choose folder…',
                        icon: Icons.folder_open_outlined,
                        variant: AppleButtonVariant.secondary,
                        onPressed: widget.session.scanning ? null : _pickFolder,
                      ),
                      AppleButton(
                        label: 'Reset to Home',
                        icon: Icons.home_outlined,
                        variant: AppleButtonVariant.pearl,
                        onPressed: widget.session.scanning || widget.session.scanRoots.isEmpty
                            ? null
                            : () {
                                widget.session.clearScanRoots();
                                setState(() => _status = 'Reset to Home (default)');
                              },
                      ),
                      if (widget.session.scanning)
                        AppleButton(
                          label: 'Cancel',
                          icon: Icons.stop_outlined,
                          variant: AppleButtonVariant.darkUtility,
                          onPressed: widget.session.cancelScan,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          AppleStickyBar(
            leading: Text(
              widget.session.scanning ? 'Scan in progress…' : 'Ready to scan',
              style: AppleTypography.body,
            ),
            action: AppleButton(
              label: widget.session.scanning ? 'Scanning…' : 'Start scan',
              icon: Icons.search,
              onPressed: widget.session.scanning ? null : _start,
            ),
          ),
        ],
      ),
    );
  }
}
