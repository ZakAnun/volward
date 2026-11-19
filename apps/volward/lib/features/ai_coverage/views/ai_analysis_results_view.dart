import 'package:flutter/material.dart';

import '../../../ai/ai_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/apple_tokens.dart';
import '../../../theme/volward_tokens.dart';
import '../../../widgets/apple_widgets.dart';
import '../../ai_coverage/ai_analysis_workspace_keys.dart';
import 'ai_analysis_workspace_view_state.dart';

/// Builds one review-queue item from a verdict, resolving selection, decision,
/// expansion and cleanup labels in the context-owning adapter.
typedef AiWorkspaceReviewItemBuilder = Widget Function(AiVerdict item);

/// Renders the AI workspace results surface from immutable view state.
final class AiAnalysisResultsView extends StatelessWidget {
  const AiAnalysisResultsView({
    super.key,
    required this.state,
    required this.reviewItemBuilder,
    required this.onBackToResults,
    required this.onNextDelete,
  });

  final AiAnalysisWorkspaceViewState state;
  final AiWorkspaceReviewItemBuilder reviewItemBuilder;
  final VoidCallback onBackToResults;
  final VoidCallback onNextDelete;

  @override
  Widget build(BuildContext context) {
    final results = state.results;
    final l10n = context.l10n;
    final pending = results.reviewQueuePending;
    final directory = results.reviewQueueDirectoryFilter;
    final initial = results.reviewQueueInitialPending;
    final decided = results.reviewQueueDecided;

    return Column(
      key: AiAnalysisWorkspaceKeys.reviewQueueKey,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppleSpacing.md,
            AppleSpacing.sm,
            AppleSpacing.md,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: AppleButton(
                  label: l10n.aiResultsBackToResults,
                  icon: Icons.arrow_back,
                  variant: AppleButtonVariant.pearl,
                  onPressed: onBackToResults,
                ),
              ),
              if (directory != null && directory.isNotEmpty) ...[
                const SizedBox(height: AppleSpacing.xs),
                Text(
                  l10n.aiReviewQueueFilteredDir(directory),
                  style: context.vwCaption,
                ),
              ],
              if (initial > 0) ...[
                const SizedBox(height: AppleSpacing.sm),
                Text(
                  l10n.aiResultsReviewQueueProgress(decided, initial),
                  style: context.vwBodyStrong,
                ),
                const SizedBox(height: AppleSpacing.xxs),
                LinearProgressIndicator(
                  value: initial == 0 ? 0 : decided / initial,
                  minHeight: 3,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: pending.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppleSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.aiResultsReviewQueueComplete,
                          style: context.vwBodyStrong,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppleSpacing.sm),
                        AppleButton(
                          label: l10n.aiResultsReviewQueueNextDelete,
                          onPressed: onNextDelete,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(AppleSpacing.md),
                  itemCount: pending.length,
                  itemBuilder: (context, index) {
                    return reviewItemBuilder(pending[index]);
                  },
                ),
        ),
      ],
    );
  }
}
