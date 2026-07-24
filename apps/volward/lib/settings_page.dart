import 'package:flutter/material.dart';

import 'theme/apple_tokens.dart';
import 'theme/volward_theme_settings.dart';
import 'theme/volward_tokens.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.themeSettings});

  final VolwardThemeSettings themeSettings;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: v.canvasParchment,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListenableBuilder(
        listenable: themeSettings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppleSpacing.lg,
              AppleSpacing.sm,
              AppleSpacing.lg,
              AppleSpacing.xxl,
            ),
            children: [
              _SectionHeader(title: 'Appearance', tokens: v),
              const SizedBox(height: AppleSpacing.xs),
              _SettingsCard(
                tokens: v,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Theme',
                      style: context.vwCaptionStrong,
                    ),
                    const SizedBox(height: AppleSpacing.xs),
                    _ThemeModePicker(
                      value: themeSettings.preference,
                      onChanged: themeSettings.setPreference,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppleSpacing.sm),
              _SettingsCard(
                tokens: v,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Accent color',
                      style: context.vwCaptionStrong,
                    ),
                    const SizedBox(height: AppleSpacing.xs),
                    Text(
                      'Applies to buttons, selections, and progress indicators.',
                      style: context.vwFinePrint,
                    ),
                    const SizedBox(height: AppleSpacing.sm),
                    Wrap(
                      spacing: AppleSpacing.sm,
                      runSpacing: AppleSpacing.sm,
                      children: [
                        for (final preset in VolwardTokens.accentPresets)
                          _AccentSwatch(
                            label: preset.$1,
                            color: preset.$2,
                            selected: themeSettings.accentColor.toARGB32() ==
                                preset.$2.toARGB32(),
                            onTap: () => themeSettings.setAccentColor(preset.$2),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppleSpacing.sm),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppleRadius.sm),
                        border: Border.all(color: v.hairline),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppleSpacing.sm,
                          vertical: AppleSpacing.xs,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppleSpacing.xs),
                            Expanded(
                              child: Text(
                                'Preview',
                                style: context.vwCaption,
                              ),
                            ),
                            Text(
                              'Primary',
                              style: context.vwFinePrint,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.tokens});

  final String title;
  final VolwardTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppleSpacing.xxs),
      child: Text(
        title.toUpperCase(),
        style: context.vwFinePrint.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.tokens, required this.child});

  final VolwardTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(AppleRadius.lg),
        border: Border.all(color: tokens.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppleSpacing.md),
        child: child,
      ),
    );
  }
}

class _ThemeModePicker extends StatelessWidget {
  const _ThemeModePicker({required this.value, required this.onChanged});

  final VolwardThemePreference value;
  final ValueChanged<VolwardThemePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    final segments = [
      (VolwardThemePreference.system, 'System', Icons.brightness_auto_outlined),
      (VolwardThemePreference.light, 'Light', Icons.light_mode_outlined),
      (VolwardThemePreference.dark, 'Dark', Icons.dark_mode_outlined),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: v.surfacePearl,
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        border: Border.all(color: v.hairline),
      ),
      child: SizedBox(
        height: 64,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) Container(width: 1, color: v.hairline),
              Expanded(
                child: _ThemeModeSegment(
                  label: segments[i].$2,
                  icon: segments[i].$3,
                  selected: value == segments[i].$1,
                  onTap: () => onChanged(segments[i].$1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThemeModeSegment extends StatelessWidget {
  const _ThemeModeSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    final scheme = Theme.of(context).colorScheme;
    final bg = selected ? scheme.primary : Colors.transparent;
    final fg = selected ? scheme.onPrimary : v.inkMuted80;

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: v.dividerSoft,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(height: 4),
            Text(
              label,
              style: context.vwFinePrint.copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    return Semantics(
      button: true,
      label: label,
      selected: selected,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppleRadius.pill),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? v.ink : v.hairline,
                width: selected ? 2.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: selected
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}
