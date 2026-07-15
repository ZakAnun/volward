import 'package:flutter/material.dart';

import '../theme/apple_tokens.dart';

class VolwardShell extends StatelessWidget {
  const VolwardShell({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.body,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<(String label, IconData icon)> destinations;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppleColors.canvasParchment,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _GlobalNav(),
          _SubNav(
            selectedIndex: selectedIndex,
            destinations: destinations,
            onDestinationSelected: onDestinationSelected,
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _GlobalNav extends StatelessWidget {
  const _GlobalNav();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      color: AppleColors.surfaceBlack,
      padding: const EdgeInsets.symmetric(horizontal: AppleSpacing.lg),
      child: Row(
        children: [
          Text(
            'Volward',
            style: AppleTypography.navLink.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.14,
            ),
          ),
          const Spacer(),
          Text(
            'Storage steward',
            style: AppleTypography.navLink.copyWith(color: AppleColors.bodyMuted),
          ),
        ],
      ),
    );
  }
}

class _SubNav extends StatelessWidget {
  const _SubNav({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final List<(String label, IconData icon)> destinations;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppleColors.canvasParchment.withValues(alpha: 0.92),
        border: const Border(bottom: BorderSide(color: AppleColors.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppleSpacing.lg),
      child: Row(
        children: [
          Text(
            destinations[selectedIndex].$1,
            style: AppleTypography.tagline,
          ),
          const SizedBox(width: AppleSpacing.xl),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < destinations.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppleSpacing.lg),
                    _SubNavLink(
                      label: destinations[i].$1,
                      selected: i == selectedIndex,
                      onTap: () => onDestinationSelected(i),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubNavLink extends StatelessWidget {
  const _SubNavLink({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppleRadius.sm),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(
          label,
          style: AppleTypography.caption.copyWith(
            color: selected ? AppleColors.primary : AppleColors.inkMuted80,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
