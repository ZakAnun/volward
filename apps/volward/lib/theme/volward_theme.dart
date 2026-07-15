import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apple_tokens.dart';

ThemeData buildVolwardTheme() {
  const colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppleColors.primary,
    onPrimary: AppleColors.onPrimary,
    secondary: AppleColors.ink,
    onSecondary: AppleColors.bodyOnDark,
    error: Color(0xFFD70015),
    onError: AppleColors.onPrimary,
    surface: AppleColors.canvasParchment,
    onSurface: AppleColors.ink,
    surfaceContainerHighest: AppleColors.canvas,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppleColors.canvasParchment,
    dividerColor: AppleColors.hairline,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textTheme: const TextTheme(
      headlineLarge: AppleTypography.heroDisplay,
      headlineMedium: AppleTypography.displayLg,
      headlineSmall: AppleTypography.tagline,
      titleMedium: AppleTypography.bodyStrong,
      titleSmall: AppleTypography.captionStrong,
      bodyLarge: AppleTypography.body,
      bodyMedium: AppleTypography.body,
      bodySmall: AppleTypography.caption,
      labelLarge: AppleTypography.body,
      labelMedium: AppleTypography.caption,
      labelSmall: AppleTypography.finePrint,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppleColors.surfaceBlack,
      foregroundColor: AppleColors.bodyOnDark,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 44,
      titleTextStyle: AppleTypography.navLink,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    cardTheme: CardThemeData(
      color: AppleColors.canvas,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppleRadius.lg),
        side: const BorderSide(color: AppleColors.hairline),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppleColors.hairline,
      thickness: 1,
      space: 1,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppleColors.primary;
        return AppleColors.canvas;
      }),
      checkColor: WidgetStateProperty.all(AppleColors.onPrimary),
      side: const BorderSide(color: AppleColors.hairline, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppleColors.ink,
      contentTextStyle: AppleTypography.caption.copyWith(color: AppleColors.bodyOnDark),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppleRadius.sm)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppleColors.canvas,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppleRadius.lg),
        side: const BorderSide(color: AppleColors.hairline),
      ),
      titleTextStyle: AppleTypography.bodyStrong,
      contentTextStyle: AppleTypography.body,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppleColors.primary,
      linearTrackColor: AppleColors.dividerSoft,
    ),
  );
}
