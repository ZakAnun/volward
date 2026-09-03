import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apple_tokens.dart';
import 'volward_tokens.dart';

List<String> _volwardFontFamilyFallback() {
  if (Platform.isMacOS) {
    return ['.AppleSystemUIFont', ...AppleTypography.fontFamilyFallback];
  }
  return AppleTypography.fontFamilyFallback;
}

ThemeData buildVolwardTheme({
  required Brightness brightness,
  Color accent = VolwardTokens.defaultAccent,
}) {
  final tokens = VolwardTokens.forBrightness(brightness, accent);

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: tokens.primary,
    onPrimary: tokens.onPrimary,
    secondary: tokens.ink,
    onSecondary: tokens.bodyOnDark,
    error: const Color(0xFFD70015),
    onError: tokens.onPrimary,
    surface: tokens.canvasParchment,
    onSurface: tokens.ink,
    surfaceContainerHighest: tokens.canvas,
  );

  TextStyle inkStyle(TextStyle base) => base.copyWith(
    color: tokens.ink,
    fontFamilyFallback: _volwardFontFamilyFallback(),
  );
  TextStyle mutedStyle(TextStyle base) => base.copyWith(
    color: tokens.inkMuted80,
    fontFamilyFallback: _volwardFontFamilyFallback(),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: tokens.canvasParchment,
    dividerColor: tokens.hairline,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    extensions: [tokens],
    textTheme: TextTheme(
      headlineLarge: inkStyle(AppleTypography.heroDisplay),
      headlineMedium: inkStyle(AppleTypography.displayLg),
      headlineSmall: inkStyle(AppleTypography.tagline),
      titleMedium: inkStyle(AppleTypography.bodyStrong),
      titleSmall: inkStyle(AppleTypography.captionStrong),
      bodyLarge: inkStyle(AppleTypography.body),
      bodyMedium: inkStyle(AppleTypography.body),
      bodySmall: mutedStyle(AppleTypography.caption),
      labelLarge: inkStyle(AppleTypography.body),
      labelMedium: mutedStyle(AppleTypography.caption),
      labelSmall: mutedStyle(AppleTypography.finePrint),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.canvasParchment,
      foregroundColor: tokens.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 44,
      titleTextStyle: AppleTypography.navLink.copyWith(
        color: tokens.ink,
        fontFamilyFallback: _volwardFontFamilyFallback(),
      ),
      iconTheme: IconThemeData(color: tokens.inkMuted80),
      actionsIconTheme: IconThemeData(color: tokens.inkMuted80),
      systemOverlayStyle: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: tokens.canvas,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppleRadius.lg),
        side: BorderSide(color: tokens.hairline),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: tokens.hairline,
      thickness: 1,
      space: 1,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return tokens.primary;
        return tokens.canvas;
      }),
      checkColor: WidgetStateProperty.all(tokens.onPrimary),
      side: BorderSide(color: tokens.hairline, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: tokens.ink,
      contentTextStyle: AppleTypography.caption.copyWith(
        color: tokens.bodyOnDark,
        fontFamilyFallback: _volwardFontFamilyFallback(),
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppleRadius.sm),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.canvas,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppleRadius.lg),
        side: BorderSide(color: tokens.hairline),
      ),
      titleTextStyle: inkStyle(AppleTypography.bodyStrong),
      contentTextStyle: inkStyle(AppleTypography.body),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tokens.primary,
      linearTrackColor: tokens.dividerSoft,
    ),
    iconTheme: IconThemeData(color: tokens.inkMuted80),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(iconColor: WidgetStatePropertyAll(tokens.inkMuted80)),
    ),
  );
}
