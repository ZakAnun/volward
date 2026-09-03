import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/volward_tokens.dart';

const kDashboardInkDark = Color(0xFF111113);
const kDashboardSoftDark = Color(0xFF1A1A1E);
const kOnDashboardDark = Color(0xFFF4F4F5);

Color dashboardPageBackground(BuildContext context) {
  final brightness = Theme.of(context).brightness;
  if (brightness == Brightness.dark) return kDashboardInkDark;
  return context.volward.canvasParchment;
}

Color dashboardInk(BuildContext context) => dashboardPageBackground(context);

Color dashboardOn(BuildContext context) {
  if (Theme.of(context).brightness == Brightness.dark) return kOnDashboardDark;
  return context.volward.ink;
}

Color dashboardGlass(BuildContext context, double overlayAlpha) {
  final overlay = Theme.of(context).brightness == Brightness.dark
      ? Colors.white
      : context.volward.ink;
  return Color.alphaBlend(
    overlay.withValues(alpha: overlayAlpha),
    dashboardInk(context),
  );
}

BoxDecoration dashboardPanelDecoration(BuildContext context) {
  final v = context.volward;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: dashboardGlass(context, isDark ? 0.08 : 0.04),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: isDark ? Colors.white.withValues(alpha: 0.08) : v.hairline,
    ),
  );
}

String localizedScanPhase(BuildContext context, String? phase) {
  final l10n = context.l10n;
  return switch (phase) {
    'DiscoveringRoots' => l10n.scanPhaseDiscoveringRoots,
    'Walking' => l10n.scanPhaseWalking,
    'Classifying' => l10n.scanPhaseClassifying,
    'Aggregating' => l10n.scanPhaseAggregating,
    'SavingResults' => l10n.scanPhaseSavingResults,
    'LoadingResults' => l10n.scanPhaseLoadingResults,
    'Done' => l10n.scanPhaseDone,
    _ => phase == null || phase.isEmpty ? l10n.scanStatusScanning : phase,
  };
}
