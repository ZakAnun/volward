import 'package:flutter/material.dart';

import '../../../ai/ai_settings_store.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/apple_tokens.dart';
import '../../../theme/volward_tokens.dart';
import '../../../widgets/apple_widgets.dart';
import '../ai_analysis_workspace_keys.dart';
import '../widgets/coverage_purchase_view.dart';
import 'ai_analysis_workspace_view_state.dart';

/// Renders the provider/credit purchase and settings prompt from an immutable
/// precheck snapshot. It renders nothing when the current provider and credit
/// context are already usable.
class AiAnalysisPurchaseView extends StatelessWidget {
  const AiAnalysisPurchaseView({
    super.key,
    required this.precheck,
    required this.onOpenSettings,
  });

  final AiWorkspacePrecheckState precheck;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.volward;
    final mode = precheck.mode;
    final needsSettings =
        !precheck.hasProvider ||
        (mode == AiMode.platform && precheck.platformCredits == 0);
    if (!needsSettings) return const SizedBox.shrink();

    final configurationMessage = !precheck.hasProvider
        ? (precheck.error ??
              (mode == AiMode.platform
                  ? l10n.aiSettingsSessionExpired
                  : l10n.aiNoApiKey))
        : l10n.aiInsufficientCredits;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CoveragePurchaseView(
          title: Text(l10n.aiSettingsBuyCredits, style: context.vwBodyStrong),
          body: Text(
            configurationMessage,
            style: AppleTypography.caption.copyWith(color: tokens.warning),
          ),
          action: AppleButton(
            key: AiAnalysisWorkspaceKeys.settingsKey,
            label: l10n.settingsTitle,
            icon: Icons.settings_outlined,
            variant: AppleButtonVariant.pearl,
            onPressed: onOpenSettings,
          ),
        ),
        const SizedBox(height: AppleSpacing.sm),
      ],
    );
  }
}
