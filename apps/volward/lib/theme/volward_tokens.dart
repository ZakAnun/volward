import 'package:flutter/material.dart';

import 'apple_tokens.dart';

/// Semantic colors for Volward UI, attached to [ThemeData] as a [ThemeExtension].
@immutable
class VolwardTokens extends ThemeExtension<VolwardTokens> {
  const VolwardTokens({
    required this.primary,
    required this.primaryFocus,
    required this.onPrimary,
    required this.ink,
    required this.body,
    required this.bodyOnDark,
    required this.bodyMuted,
    required this.inkMuted80,
    required this.inkMuted48,
    required this.dividerSoft,
    required this.hairline,
    required this.canvas,
    required this.canvasParchment,
    required this.surfacePearl,
    required this.surfaceBlack,
    required this.folderIcon,
    required this.folderIconOnPrimary,
    required this.warning,
    required this.danger,
  });

  final Color primary;
  final Color primaryFocus;
  final Color onPrimary;
  final Color ink;
  final Color body;
  final Color bodyOnDark;
  final Color bodyMuted;
  final Color inkMuted80;
  final Color inkMuted48;
  final Color dividerSoft;
  final Color hairline;
  final Color canvas;
  final Color canvasParchment;
  final Color surfacePearl;
  final Color surfaceBlack;
  final Color folderIcon;
  final Color folderIconOnPrimary;
  final Color warning;
  final Color danger;

  static const defaultAccent = Color(0xFF0066CC);

  static const accentPresets = <(String label, Color color)>[
    ('Blue', Color(0xFF0066CC)),
    ('Purple', Color(0xFFAF52DE)),
    ('Pink', Color(0xFFFF2D55)),
    ('Orange', Color(0xFFFF9500)),
    ('Green', Color(0xFF34C759)),
    ('Teal', Color(0xFF32ADE6)),
  ];

  factory VolwardTokens.forBrightness(
    Brightness brightness,
    Color accent,
  ) {
    return brightness == Brightness.dark
        ? VolwardTokens.dark(accent)
        : VolwardTokens.light(accent);
  }

  static Color folderIconFor(Color accent, Brightness brightness) {
    const cyan = Color(0xFF5AC8FA);
    final blended = Color.lerp(accent, cyan, 0.38) ?? cyan;
    return brightness == Brightness.dark
        ? (Color.lerp(blended, Colors.white, 0.18) ?? blended)
        : blended;
  }

  static Color folderIconOnPrimaryFor(Color accent) {
    return Color.lerp(folderIconFor(accent, Brightness.dark), Colors.white, 0.32) ??
        const Color(0xFF7CB3FF);
  }

  factory VolwardTokens.light(Color accent) {
    final focus = Color.lerp(accent, Colors.black, 0.08) ?? accent;
    return VolwardTokens(
      primary: accent,
      primaryFocus: focus,
      onPrimary: Colors.white,
      ink: AppleColors.ink,
      body: AppleColors.body,
      bodyOnDark: AppleColors.bodyOnDark,
      bodyMuted: AppleColors.bodyMuted,
      inkMuted80: AppleColors.inkMuted80,
      inkMuted48: AppleColors.inkMuted48,
      dividerSoft: AppleColors.dividerSoft,
      hairline: AppleColors.hairline,
      canvas: AppleColors.canvas,
      canvasParchment: AppleColors.canvasParchment,
      surfacePearl: AppleColors.surfacePearl,
      surfaceBlack: AppleColors.surfaceBlack,
      folderIcon: folderIconFor(accent, Brightness.light),
      folderIconOnPrimary: folderIconOnPrimaryFor(accent),
      warning: const Color(0xFFFF9500),
      danger: const Color(0xFFFF3B30),
    );
  }

  factory VolwardTokens.dark(Color accent) {
    final focus = Color.lerp(accent, Colors.white, 0.18) ?? accent;
    return VolwardTokens(
      primary: focus,
      primaryFocus: focus,
      onPrimary: Colors.white,
      ink: const Color(0xFFF5F5F7),
      body: const Color(0xFFF5F5F7),
      bodyOnDark: const Color(0xFFF5F5F7),
      bodyMuted: const Color(0xFF98989D),
      inkMuted80: const Color(0xFFEBEBF5),
      inkMuted48: const Color(0xFF8E8E93),
      dividerSoft: const Color(0xFF2C2C2E),
      hairline: const Color(0xFF38383A),
      canvas: const Color(0xFF1C1C1E),
      canvasParchment: const Color(0xFF000000),
      surfacePearl: const Color(0xFF2C2C2E),
      surfaceBlack: const Color(0xFF000000),
      folderIcon: folderIconFor(accent, Brightness.dark),
      folderIconOnPrimary: folderIconOnPrimaryFor(accent),
      warning: const Color(0xFFFF9F0A),
      danger: const Color(0xFFFF453A),
    );
  }

  @override
  VolwardTokens copyWith({
    Color? primary,
    Color? primaryFocus,
    Color? onPrimary,
    Color? ink,
    Color? body,
    Color? bodyOnDark,
    Color? bodyMuted,
    Color? inkMuted80,
    Color? inkMuted48,
    Color? dividerSoft,
    Color? hairline,
    Color? canvas,
    Color? canvasParchment,
    Color? surfacePearl,
    Color? surfaceBlack,
    Color? folderIcon,
    Color? folderIconOnPrimary,
    Color? warning,
    Color? danger,
  }) {
    return VolwardTokens(
      primary: primary ?? this.primary,
      primaryFocus: primaryFocus ?? this.primaryFocus,
      onPrimary: onPrimary ?? this.onPrimary,
      ink: ink ?? this.ink,
      body: body ?? this.body,
      bodyOnDark: bodyOnDark ?? this.bodyOnDark,
      bodyMuted: bodyMuted ?? this.bodyMuted,
      inkMuted80: inkMuted80 ?? this.inkMuted80,
      inkMuted48: inkMuted48 ?? this.inkMuted48,
      dividerSoft: dividerSoft ?? this.dividerSoft,
      hairline: hairline ?? this.hairline,
      canvas: canvas ?? this.canvas,
      canvasParchment: canvasParchment ?? this.canvasParchment,
      surfacePearl: surfacePearl ?? this.surfacePearl,
      surfaceBlack: surfaceBlack ?? this.surfaceBlack,
      folderIcon: folderIcon ?? this.folderIcon,
      folderIconOnPrimary: folderIconOnPrimary ?? this.folderIconOnPrimary,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  VolwardTokens lerp(ThemeExtension<VolwardTokens>? other, double t) {
    if (other is! VolwardTokens) return this;
    Color lerpColor(Color a, Color b) => Color.lerp(a, b, t)!;
    return VolwardTokens(
      primary: lerpColor(primary, other.primary),
      primaryFocus: lerpColor(primaryFocus, other.primaryFocus),
      onPrimary: lerpColor(onPrimary, other.onPrimary),
      ink: lerpColor(ink, other.ink),
      body: lerpColor(body, other.body),
      bodyOnDark: lerpColor(bodyOnDark, other.bodyOnDark),
      bodyMuted: lerpColor(bodyMuted, other.bodyMuted),
      inkMuted80: lerpColor(inkMuted80, other.inkMuted80),
      inkMuted48: lerpColor(inkMuted48, other.inkMuted48),
      dividerSoft: lerpColor(dividerSoft, other.dividerSoft),
      hairline: lerpColor(hairline, other.hairline),
      canvas: lerpColor(canvas, other.canvas),
      canvasParchment: lerpColor(canvasParchment, other.canvasParchment),
      surfacePearl: lerpColor(surfacePearl, other.surfacePearl),
      surfaceBlack: lerpColor(surfaceBlack, other.surfaceBlack),
      folderIcon: lerpColor(folderIcon, other.folderIcon),
      folderIconOnPrimary: lerpColor(folderIconOnPrimary, other.folderIconOnPrimary),
      warning: lerpColor(warning, other.warning),
      danger: lerpColor(danger, other.danger),
    );
  }
}

extension VolwardContext on BuildContext {
  VolwardTokens get volward =>
      Theme.of(this).extension<VolwardTokens>() ??
      VolwardTokens.light(VolwardTokens.defaultAccent);
}

/// Theme-aware typography helpers (AppleTypography embeds light-mode ink colors).
extension VolwardTypography on BuildContext {
  TextStyle get vwBody => AppleTypography.body.copyWith(color: volward.ink);
  TextStyle get vwBodyStrong =>
      AppleTypography.bodyStrong.copyWith(color: volward.ink);
  TextStyle get vwCaption =>
      AppleTypography.caption.copyWith(color: volward.inkMuted80);
  TextStyle get vwCaptionStrong =>
      AppleTypography.captionStrong.copyWith(color: volward.ink);
  TextStyle get vwFinePrint =>
      AppleTypography.finePrint.copyWith(color: volward.inkMuted48);
  TextStyle get vwFinePrintInk =>
      AppleTypography.finePrint.copyWith(color: volward.ink);
  TextStyle get vwDisplayLg =>
      AppleTypography.displayLg.copyWith(color: volward.ink);
  TextStyle get vwLead =>
      AppleTypography.lead.copyWith(color: volward.inkMuted80);
  TextStyle get vwNavLinkMuted =>
      AppleTypography.navLink.copyWith(color: volward.bodyMuted);
}
