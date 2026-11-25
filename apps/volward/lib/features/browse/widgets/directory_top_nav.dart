import 'package:flutter/material.dart';
import 'package:volward/l10n/l10n.dart';
import 'package:volward/theme/apple_tokens.dart';
import 'package:volward/theme/volward_tokens.dart';
import 'package:volward/widgets/volward_logo.dart';
import 'directory_section_layout.dart';

const Key directoryLogoKey = Key('volward-top-nav-home');

/// Top navigation shown while browsing. Owns no session or page state.
class DirectoryTopNav extends StatelessWidget {
  const DirectoryTopNav({
    super.key,
    required this.onShowHome,
    required this.onOpenSettings,
  });

  final VoidCallback onShowHome;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    return Container(
      height: 36,
      color: v.surfaceBlack,
      padding: const EdgeInsets.symmetric(
        horizontal: directoryDetailHorizontalInset,
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: context.l10n.scanActionHome,
            child: InkWell(
              key: directoryLogoKey,
              onTap: onShowHome,
              borderRadius: BorderRadius.circular(AppleRadius.sm),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    const VolwardLogoMark(size: 20),
                    const SizedBox(width: AppleSpacing.sm),
                    Text(
                      'Volward',
                      style: AppleTypography.navLink.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.12,
                        color: v.bodyOnDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppleSpacing.sm),
          Text('·', style: context.vwNavLinkMuted),
          const SizedBox(width: AppleSpacing.sm),
          Text(context.l10n.navSubtitle, style: context.vwNavLinkMuted),
          const Spacer(),
          Tooltip(
            message: context.l10n.settingsTooltip,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(Icons.settings_outlined, size: 18, color: v.bodyMuted),
              onPressed: onOpenSettings,
            ),
          ),
        ],
      ),
    );
  }
}
