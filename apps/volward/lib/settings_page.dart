import 'package:flutter/material.dart';

import 'l10n/l10n.dart';
import 'theme/apple_tokens.dart';
import 'theme/volward_theme_settings.dart';
import 'theme/volward_tokens.dart';
import 'volward_session.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.themeSettings,
    required this.session,
    required this.deletableOnly,
    required this.onDeletableOnlyChanged,
  });

  final VolwardThemeSettings themeSettings;
  final VolwardSession session;
  final bool deletableOnly;
  final ValueChanged<bool> onDeletableOnlyChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _deletableOnly;

  @override
  void initState() {
    super.initState();
    _deletableOnly = widget.deletableOnly;
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deletableOnly != widget.deletableOnly) {
      _deletableOnly = widget.deletableOnly;
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: v.canvasParchment,
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.themeSettings, widget.session]),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppleSpacing.lg,
              AppleSpacing.sm,
              AppleSpacing.lg,
              AppleSpacing.xxl,
            ),
            children: [
              _SectionHeader(title: l10n.settingsAppearanceSection, tokens: v),
              const SizedBox(height: AppleSpacing.xs),
              _SettingsCard(
                tokens: v,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.settingsThemeTitle,
                      style: context.vwCaptionStrong,
                    ),
                    const SizedBox(height: AppleSpacing.xs),
                    _ThemeModePicker(
                      value: widget.themeSettings.preference,
                      onChanged: widget.themeSettings.setPreference,
                    ),
                    const Divider(height: AppleSpacing.lg),
                    Text(
                      l10n.settingsLanguageTitle,
                      style: context.vwCaptionStrong,
                    ),
                    const SizedBox(height: AppleSpacing.xs),
                    _LocaleModePicker(
                      value: widget.themeSettings.localePreference,
                      onChanged: widget.themeSettings.setLocalePreference,
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
                      l10n.settingsAccentColorTitle,
                      style: context.vwCaptionStrong,
                    ),
                    const SizedBox(height: AppleSpacing.xs),
                    Text(
                      l10n.settingsAccentColorDescription,
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
                            selected:
                                widget.themeSettings.accentColor.toARGB32() ==
                                preset.$2.toARGB32(),
                            onTap: () =>
                                widget.themeSettings.setAccentColor(preset.$2),
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
                                l10n.settingsAccentPreview,
                                style: context.vwCaption,
                              ),
                            ),
                            Text(
                              l10n.settingsAccentPrimary,
                              style: context.vwFinePrint,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppleSpacing.lg),
              _SectionHeader(title: l10n.settingsScanResultsSection, tokens: v),
              const SizedBox(height: AppleSpacing.xs),
              _SettingsCard(
                tokens: v,
                child: Column(
                  children: [
                    _SettingsSwitch(
                      title: l10n.settingsDeletableOnlyTitle,
                      subtitle: l10n.settingsDeletableOnlyDescription,
                      value: _deletableOnly,
                      enabled: !widget.session.scanning,
                      onChanged: (value) {
                        setState(() => _deletableOnly = value);
                        widget.onDeletableOnlyChanged(value);
                      },
                    ),
                    const Divider(height: AppleSpacing.lg),
                    _SettingsSwitch(
                      title: l10n.settingsIncrementalScanTitle,
                      subtitle: widget.session.canUseIncrementalScan
                          ? l10n.settingsIncrementalScanDescription
                          : l10n.settingsIncrementalScanUnsupported,
                      value: widget.session.incrementalScan,
                      enabled:
                          !widget.session.scanning &&
                          widget.session.canUseIncrementalScan,
                      onChanged: widget.session.setIncrementalScan,
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

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.vwCaptionStrong),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: context.vwFinePrint.copyWith(color: v.inkMuted48),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppleSpacing.md),
          Switch.adaptive(value: value, onChanged: enabled ? onChanged : null),
        ],
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
    final l10n = context.l10n;
    final segments = [
      (
        VolwardThemePreference.system,
        l10n.settingsThemeSystem,
        Icons.brightness_auto_outlined,
      ),
      (
        VolwardThemePreference.light,
        l10n.settingsThemeLight,
        Icons.light_mode_outlined,
      ),
      (
        VolwardThemePreference.dark,
        l10n.settingsThemeDark,
        Icons.dark_mode_outlined,
      ),
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

class _LocaleModePicker extends StatelessWidget {
  const _LocaleModePicker({required this.value, required this.onChanged});

  final VolwardLocalePreference value;
  final ValueChanged<VolwardLocalePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = context.volward;
    final l10n = context.l10n;
    final segments = [
      (
        VolwardLocalePreference.system,
        l10n.settingsLanguageSystem,
        Icons.language_outlined,
      ),
      (
        VolwardLocalePreference.zh,
        l10n.settingsLanguageChinese,
        Icons.translate_outlined,
      ),
      (
        VolwardLocalePreference.en,
        l10n.settingsLanguageEnglish,
        Icons.translate_outlined,
      ),
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
