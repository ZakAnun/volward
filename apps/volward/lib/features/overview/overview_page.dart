import 'package:flutter/material.dart';

import '../../theme/apple_tokens.dart';
import '../../volward_session.dart';
import '../../widgets/apple_widgets.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.session});

  final VolwardSession session;

  @override
  Widget build(BuildContext context) {
    if (session.initError != null) {
      return ApplePageShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppleSectionHeader(
              title: 'Engine unavailable',
              subtitle: 'The native Rust engine could not be loaded.',
            ),
            const SizedBox(height: AppleSpacing.lg),
            AppleUtilityCard(
              child: Text(
                session.initError!,
                style: AppleTypography.body.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
            const SizedBox(height: AppleSpacing.lg),
            Text(
              'Rebuild with: fvm flutter run -d macos\n'
              'Ensure macos/build_rust.sh copied libvolward_facade.dylib into the app bundle.',
              style: AppleTypography.caption,
            ),
          ],
        ),
      );
    }

    if (!session.ready) {
      return const ColoredBox(
        color: AppleColors.canvasParchment,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: AppleSpacing.lg),
              Text('Loading Rust engine…', style: AppleTypography.body),
            ],
          ),
        ),
      );
    }

    final caps = session.capabilities;
    final level = caps['level']?.toString() ?? 'unknown';

    return ApplePageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppleSectionHeader(
            title: 'Volward',
            subtitle: 'Your storage steward.',
          ),
          const SizedBox(height: AppleSpacing.xxl),
          AppleUtilityCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Capability level', style: AppleTypography.bodyStrong),
                      const SizedBox(height: 4),
                      Text(level, style: AppleTypography.caption),
                    ],
                  ),
                ),
                Icon(
                  session.deepScanReady ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: session.deepScanReady ? AppleColors.primary : const Color(0xFFFF9500),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppleSpacing.sm),
          AppleUtilityCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Deep scan ready', style: AppleTypography.bodyStrong),
                const SizedBox(height: 4),
                Text(
                  session.deepScanReady ? 'Yes — full disk access granted.' : 'No — see hints below.',
                  style: AppleTypography.caption,
                ),
              ],
            ),
          ),
          if (session.permissionHints.isNotEmpty) ...[
            const SizedBox(height: AppleSpacing.xl),
            Text('Permission hints', style: AppleTypography.captionStrong),
            const SizedBox(height: AppleSpacing.sm),
            AppleUtilityCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final h in session.permissionHints) ...[
                    Text('• $h', style: AppleTypography.body),
                    if (h != session.permissionHints.last) const SizedBox(height: AppleSpacing.xs),
                  ],
                ],
              ),
            ),
            if (!session.deepScanReady) ...[
              const SizedBox(height: AppleSpacing.lg),
              AppleButton(
                label: 'Open Full Disk Access settings',
                icon: Icons.settings_outlined,
                variant: AppleButtonVariant.secondary,
                onPressed: () async {
                  final ok = await session.openPermissionSettings();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? 'Opened Full Disk Access settings — grant access, then refresh.'
                            : session.lastError ?? 'Could not open system settings',
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
          const SizedBox(height: AppleSpacing.xxl),
          AppleButton(
            label: 'Refresh capabilities',
            icon: Icons.refresh,
            onPressed: () async {
              await session.refreshCapabilities();
              if (!context.mounted) return;
              final msg = session.lastError ?? 'Capabilities refreshed';
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
            },
          ),
        ],
      ),
    );
  }
}
