import 'package:flutter/material.dart';

/// Design tokens from DESIGN-apple.md
abstract final class AppleColors {
  static const primary = Color(0xFF0066CC);
  static const primaryFocus = Color(0xFF0071E3);
  static const primaryOnDark = Color(0xFF2997FF);

  static const ink = Color(0xFF1D1D1F);
  static const body = Color(0xFF1D1D1F);
  static const bodyOnDark = Color(0xFFFFFFFF);
  static const bodyMuted = Color(0xFFCCCCCC);
  static const inkMuted80 = Color(0xFF333333);
  static const inkMuted48 = Color(0xFF7A7A7A);

  static const dividerSoft = Color(0xFFF0F0F0);
  static const hairline = Color(0xFFE0E0E0);

  static const canvas = Color(0xFFFFFFFF);
  static const canvasParchment = Color(0xFFF5F5F7);
  static const surfacePearl = Color(0xFFFAFAFC);
  static const surfaceTile1 = Color(0xFF272729);
  static const surfaceBlack = Color(0xFF000000);

  static const onPrimary = Color(0xFFFFFFFF);
}

abstract final class AppleSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 17.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const section = 80.0;
}

abstract final class AppleRadius {
  static const none = 0.0;
  static const sm = 8.0;
  static const md = 11.0;
  static const lg = 18.0;
  static const pill = 9999.0;
}

abstract final class AppleTypography {
  static const displayFamily = '.AppleSystemUIFont';
  static const textFamily = '.AppleSystemUIFont';

  static const heroDisplay = TextStyle(
    fontFamily: displayFamily,
    fontSize: 40,
    fontWeight: FontWeight.w600,
    height: 1.1,
    letterSpacing: -0.28,
    color: AppleColors.ink,
  );

  static const displayLg = TextStyle(
    fontFamily: displayFamily,
    fontSize: 34,
    fontWeight: FontWeight.w600,
    height: 1.1,
    color: AppleColors.ink,
  );

  static const tagline = TextStyle(
    fontFamily: displayFamily,
    fontSize: 21,
    fontWeight: FontWeight.w600,
    height: 1.19,
    letterSpacing: 0.231,
    color: AppleColors.ink,
  );

  static const lead = TextStyle(
    fontFamily: displayFamily,
    fontSize: 28,
    fontWeight: FontWeight.w400,
    height: 1.14,
    letterSpacing: 0.196,
    color: AppleColors.inkMuted80,
  );

  static const body = TextStyle(
    fontFamily: textFamily,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.47,
    letterSpacing: -0.374,
    color: AppleColors.ink,
  );

  static const bodyStrong = TextStyle(
    fontFamily: textFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.24,
    letterSpacing: -0.374,
    color: AppleColors.ink,
  );

  static const caption = TextStyle(
    fontFamily: textFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.43,
    letterSpacing: -0.224,
    color: AppleColors.inkMuted80,
  );

  static const captionStrong = TextStyle(
    fontFamily: textFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.29,
    letterSpacing: -0.224,
    color: AppleColors.ink,
  );

  static const navLink = TextStyle(
    fontFamily: textFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.0,
    letterSpacing: -0.12,
    color: AppleColors.bodyOnDark,
  );

  static const finePrint = TextStyle(
    fontFamily: textFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.0,
    letterSpacing: -0.12,
    color: AppleColors.inkMuted48,
  );
}
