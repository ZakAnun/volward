import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';
import '../updater/app_updater.dart';

/// A bottom-right floating affordance offered once a background update has been
/// downloaded and verified. Tapping it installs and relaunches immediately —
/// there is deliberately no confirmation step.
class UpdateReadyPill extends StatelessWidget {
  const UpdateReadyPill({super.key, required this.updater});

  static const actionKey = ValueKey<String>('update-ready-pill-action');
  static const dismissKey = ValueKey<String>('update-ready-pill-dismiss');

  final AppUpdater updater;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: updater,
      builder: (context, _) {
        if (!updater.showsReadyBanner) return const SizedBox.shrink();
        final v = context.volward;
        final l10n = context.l10n;
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          opacity: 1,
          child: Material(
            // The pill floats over a dark dashboard on the home screen and a
            // light parchment canvas while browsing, so it paints its own
            // surface instead of inheriting either.
            color: v.primary,
            elevation: 6,
            shadowColor: v.surfaceBlack.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(AppleRadius.pill),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  key: actionKey,
                  borderRadius: BorderRadius.circular(AppleRadius.pill),
                  onTap: () => unawaited(updater.installDownloaded()),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppleSpacing.md,
                      AppleSpacing.sm,
                      AppleSpacing.sm,
                      AppleSpacing.sm,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.system_update_alt_rounded,
                          size: 18,
                          color: v.onPrimary,
                        ),
                        const SizedBox(width: AppleSpacing.xs),
                        Text(
                          l10n.updateReadyAction,
                          style: AppleTypography.captionStrong.copyWith(
                            color: v.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: AppleSpacing.xxs),
                  child: IconButton(
                    key: dismissKey,
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.updateReadyDismissTooltip,
                    color: v.onPrimary,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: updater.dismissReadyToInstall,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
