import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

const kDashboardInk = Color(0xFF111113);
const kOnDashboard = Color(0xFFF4F4F5);

/// Frosted fill used by every dashboard panel.
Color dashboardGlass(double whiteAlpha) {
  return Color.alphaBlend(
    Colors.white.withValues(alpha: whiteAlpha),
    kDashboardInk,
  );
}

/// The shared rounded-glass panel chrome.
BoxDecoration dashboardPanelDecoration() {
  return BoxDecoration(
    color: dashboardGlass(0.08),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
