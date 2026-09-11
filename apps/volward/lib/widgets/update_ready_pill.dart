import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/apple_tokens.dart';
import '../theme/volward_tokens.dart';
import '../updater/app_updater.dart';
import 'home/dashboard_theme.dart';

/// Circular install affordance on the home sidebar once a background update has
/// been downloaded and verified. Tapping installs and relaunches immediately —
/// there is deliberately no confirmation step.
///
/// Visibility is driven solely by [AppUpdater.showsReadyBanner] (download parked
/// at [UpdatePhase.readyToInstall]). Hover copy is rendered inline (not
/// [Tooltip]) to avoid the desktop overlay jank documented in [main.dart].
class UpdateReadyPill extends StatefulWidget {
  const UpdateReadyPill({super.key, required this.updater});

  static const actionKey = ValueKey<String>('update-ready-pill-action');
  static const hoverHintKey = ValueKey<String>('update-ready-pill-hover-hint');
  static const iconSize = 36.0;

  final AppUpdater updater;

  @override
  State<UpdateReadyPill> createState() => _UpdateReadyPillState();
}

class _UpdateReadyPillState extends State<UpdateReadyPill> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.updater,
      builder: (context, _) {
        if (!widget.updater.showsReadyBanner) {
          return const SizedBox.shrink();
        }
        final version = widget.updater.readyInstallVersion;
        if (version == null) {
          return const SizedBox.shrink();
        }
        final v = context.volward;
        final l10n = context.l10n;
        final hoverMessage = l10n.updateReadyTooltip(version);
        final highlightColor = v.onPrimary.withValues(alpha: 0.12);
        final hintBackground = dashboardGlass(context, 0.14);
        final hintBorder = Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.12)
            : v.hairline;
        return Semantics(
          button: true,
          label: hoverMessage,
          child: MouseRegion(
            onEnter: (_) {
              if (!_hovering) setState(() => _hovering = true);
            },
            onExit: (_) {
              if (_hovering) setState(() => _hovering = false);
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Material(
                  color: v.primary,
                  elevation: 6,
                  shadowColor: v.surfaceBlack.withValues(alpha: 0.24),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: UpdateReadyPill.actionKey,
                    onTap: () => unawaited(widget.updater.installDownloaded()),
                    customBorder: const CircleBorder(),
                    splashColor: Colors.transparent,
                    highlightColor: highlightColor,
                    child: SizedBox(
                      width: UpdateReadyPill.iconSize,
                      height: UpdateReadyPill.iconSize,
                      child: Icon(
                        Icons.system_update_alt_rounded,
                        size: 18,
                        color: v.onPrimary,
                      ),
                    ),
                  ),
                ),
                if (_hovering)
                  Positioned(
                    left: 0,
                    bottom: UpdateReadyPill.iconSize + 8,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        key: UpdateReadyPill.hoverHintKey,
                        opacity: 1,
                        duration: const Duration(milliseconds: 120),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: hintBackground,
                            borderRadius: BorderRadius.circular(AppleRadius.sm),
                            border: Border.all(color: hintBorder),
                            boxShadow: [
                              BoxShadow(
                                color: v.surfaceBlack.withValues(alpha: 0.18),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppleSpacing.sm,
                              vertical: AppleSpacing.xs,
                            ),
                            child: Text(
                              hoverMessage,
                              style: AppleTypography.captionStrong.copyWith(
                                color: dashboardOn(context),
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
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
