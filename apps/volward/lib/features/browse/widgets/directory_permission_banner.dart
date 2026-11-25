import 'package:flutter/material.dart';
import 'package:volward/l10n/l10n.dart';
import 'package:volward/macos_settings.dart';
import 'package:volward/theme/apple_tokens.dart';
import 'package:volward/theme/volward_tokens.dart';
import 'package:volward/widgets/apple_widgets.dart';

/// Permission status banner for the directory page. Purely data in, callbacks
/// out — no session or page State access.
class DirectoryPermissionBanner extends StatelessWidget {
  const DirectoryPermissionBanner({
    super.key,
    required this.ready,
    required this.initError,
    required this.hasSnapshotFileApi,
    required this.deepScanReady,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onOpenFullDiskAccess,
    required this.onCopyAppPath,
    required this.onCheckAgain,
  });

  final bool ready;
  final String? initError;
  final bool hasSnapshotFileApi;
  final bool deepScanReady;
  final bool expanded;
  final ValueChanged<bool> onToggleExpanded;
  final VoidCallback onOpenFullDiskAccess;
  final VoidCallback onCopyAppPath;
  final VoidCallback onCheckAgain;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    final l10n = context.l10n;
    if (!ready) {
      return Row(
        children: [
          Icon(Icons.hourglass_empty, size: 14, color: v.inkMuted48),
          const SizedBox(width: AppleSpacing.xxs),
          Expanded(
            child: Text(
              initError ?? l10n.stickyLoadingEngine,
              style: context.vwFinePrint,
            ),
          ),
        ],
      );
    }

    if (!hasSnapshotFileApi) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppleSpacing.sm),
        decoration: BoxDecoration(
          color: v.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          border: Border.all(color: v.danger.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.permissionNativeOutdatedTitle,
              style: context.vwCaptionStrong,
            ),
            const SizedBox(height: AppleSpacing.xxs),
            Text(
              l10n.permissionNativeOutdatedDescription,
              style: context.vwFinePrint,
            ),
          ],
        ),
      );
    }

    if (deepScanReady) {
      return const SizedBox.shrink();
    }

    if (!expanded) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 14, color: v.warning),
          const SizedBox(width: AppleSpacing.xxs),
          Expanded(
            child: Text(
              l10n.permissionFullDiskRecommended,
              style: context.vwFinePrint,
            ),
          ),
          AppleButton(
            label: l10n.permissionOpenSettings,
            icon: Icons.open_in_new,
            variant: AppleButtonVariant.secondary,
            onPressed: onOpenFullDiskAccess,
          ),
          Tooltip(
            message: l10n.permissionShowDetails,
            child: IconButton(
              icon: Icon(Icons.expand_more, size: 18, color: v.inkMuted80),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => onToggleExpanded(true),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppleSpacing.sm),
      decoration: BoxDecoration(
        color: v.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        border: Border.all(color: v.warning.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.permissionFullDiskRecommendedTitle,
                  style: context.vwCaptionStrong,
                ),
              ),
              Tooltip(
                message: l10n.permissionHideDetails,
                child: IconButton(
                  icon: Icon(Icons.expand_less, size: 18, color: v.inkMuted80),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: () => onToggleExpanded(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppleSpacing.xxs),
          Text(l10n.permissionFullDiskInstructions, style: context.vwFinePrint),
          if (MacosSettings.appBundlePath() case final path?) ...[
            const SizedBox(height: AppleSpacing.xxs),
            Text(
              l10n.permissionAppPath(path),
              style: context.vwFinePrint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppleSpacing.sm),
          Wrap(
            spacing: AppleSpacing.xs,
            runSpacing: AppleSpacing.xs,
            children: [
              AppleButton(
                label: l10n.permissionOpenSettings,
                icon: Icons.open_in_new,
                variant: AppleButtonVariant.secondary,
                onPressed: onOpenFullDiskAccess,
              ),
              AppleButton(
                label: l10n.permissionCopyAppPath,
                icon: Icons.copy,
                variant: AppleButtonVariant.pearl,
                onPressed: onCopyAppPath,
              ),
              AppleButton(
                label: l10n.permissionCheckAgain,
                icon: Icons.refresh,
                variant: AppleButtonVariant.pearl,
                onPressed: onCheckAgain,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
