import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ai/ai_settings_store.dart';
import '../../../ai/ai_token_estimate.dart';
import '../../../ai/coverage_client_logic.dart';
import '../../../ai/coverage_job_state.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/apple_tokens.dart';
import '../../../theme/volward_tokens.dart';
import '../../../widgets/ai_analysis_activity_card.dart';
import '../../../widgets/ai_results_hub.dart';
import '../../../widgets/apple_widgets.dart';
import 'ai_analysis_purchase_view.dart';
import '../ai_analysis_workspace_keys.dart';
import 'ai_analysis_workspace_view_actions.dart';
import 'ai_analysis_workspace_view_state.dart';

/// Renders precheck scope, coverage estimates, budget warnings and settings
/// prompts from immutable precheck and coverage snapshots.
class AiAnalysisPrecheckView extends StatelessWidget {
  const AiAnalysisPrecheckView({
    super.key,
    required this.precheck,
    required this.coverage,
    required this.actions,
    required this.onOpenSettings,
  });

  final AiWorkspacePrecheckState precheck;
  final AiWorkspaceCoverageState coverage;
  final AiAnalysisWorkspaceViewActions actions;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _buildChildren(context),
    );
  }

  List<Widget> _buildChildren(BuildContext context) {
    if (precheck.useFullCoverage) {
      return _buildFullCoverageChildren(context);
    }
    return _buildLegacyChildren(context);
  }

  List<Widget> _buildLegacyChildren(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.volward;
    final mode = precheck.mode;
    final summary = coverage.planSummary;
    final minApiCalls = summary == null
        ? null
        : coveragePlanMinApiCalls(summary);
    final showsV3Breakdown = coveragePlanSummaryShowsV3PrecheckBreakdown(
      summary,
    );
    final planIsLocalOnly =
        summary != null &&
        summary.planVersion >= 3 &&
        !coveragePlanRequiresApi(summary);

    return [
      if (precheck.candidatesBootstrapPending) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AiAnalysisActivityInlineSpinner(
              color: tokens.primary,
              size: 14,
              strokeWidth: 2,
            ),
            const SizedBox(width: AppleSpacing.sm),
            Expanded(
              child: Text(
                l10n.aiCandidatesBootstrapLoading,
                style: context.vwCaption,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppleSpacing.sm),
      ],
      AiAnalysisPurchaseView(
        precheck: precheck,
        onOpenSettings: onOpenSettings,
      ),
      if (precheck.error != null &&
          (precheck.hasProvider ||
              (mode == AiMode.platform && precheck.platformCredits != 0))) ...[
        Text(
          precheck.error!,
          style: AppleTypography.caption.copyWith(color: tokens.danger),
        ),
        const SizedBox(height: AppleSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: AppleButton(
            label: l10n.aiActionRetry,
            icon: Icons.refresh_outlined,
            variant: AppleButtonVariant.pearl,
            onPressed: () => unawaited(
              actions.startAnalysis(fullCoverage: precheck.useFullCoverage),
            ),
          ),
        ),
        const SizedBox(height: AppleSpacing.sm),
      ],
      Text(
        l10n.aiPreCheckSafeTitle(precheck.displayPreClassifiedCount),
        style: context.vwBodyStrong,
      ),
      const SizedBox(height: AppleSpacing.xs),
      if (precheck.useFullCoverage)
        Text(l10n.aiPrecheckDataScopeHint, style: context.vwCaption),
      if (precheck.useFullCoverage) const SizedBox(height: AppleSpacing.xs),
      ..._buildEstimateLines(context, minApiCalls, showsV3Breakdown),
      ..._buildUnknownScopeSampleSection(context),
      if (mode == AiMode.platform && precheck.narrativeEnabled) ...[
        const SizedBox(height: AppleSpacing.xs),
        Text(l10n.aiPrecheckNarrativeCreditHint, style: context.vwCaption),
      ],
      if (mode == AiMode.platform &&
          precheck.platformCredits != null &&
          !(precheck.useFullCoverage &&
              precheck.estimatedCoverageCredits != null)) ...[
        const SizedBox(height: AppleSpacing.xs),
        Text(
          l10n.aiPrecheckCreditsCost(precheck.platformCredits!),
          style: context.vwCaption,
        ),
      ],
      if (precheck.useFullCoverage &&
          mode == AiMode.platform &&
          showsV3Breakdown) ...[
        const SizedBox(height: AppleSpacing.xs),
        Text(
          l10n.aiCoverageLocalResolved(
            summary!.localSafeFiles! + summary.localKeepFiles!,
          ),
        ),
        if ((minApiCalls ?? 0) > 0) ...[
          Text(
            l10n.aiCoverageEstimatedTreeRounds(summary.estimatedTreeCredits!),
          ),
          Text(
            l10n.aiCoverageEstimatedTailRounds(summary.estimatedTailCredits!),
          ),
          Text(
            l10n.aiCoverageEstimatedCreditsTotal(
              precheck.estimatedCoverageCredits!,
            ),
          ),
          Text(
            l10n.aiCoverageBufferedCreditsMinimum(
              coverageBufferedEstimate(precheck.estimatedCoverageCredits!),
            ),
          ),
        ],
        if (precheck.coverageBudgetCredits != null)
          Text(
            l10n.aiCoverageRunCapConfigured(precheck.coverageBudgetCredits!),
          ),
        if (precheck.platformCredits != null)
          Text(l10n.aiCoverageAccountBalance(precheck.platformCredits!)),
        if (coverage.runBudgetCredits != null &&
            coverage.runBudgetCredits != precheck.coverageBudgetCredits)
          Text(l10n.aiCoverageRunCapConfigured(coverage.runBudgetCredits!)),
        if ((minApiCalls ?? 0) >= 10)
          Text(
            l10n.aiCoveragePurchaseFooterConditional,
            style: context.vwCaption,
          ),
      ] else if (precheck.useFullCoverage &&
          mode == AiMode.platform &&
          precheck.estimatedCoverageCredits != null &&
          !planIsLocalOnly) ...[
        const SizedBox(height: AppleSpacing.xs),
        Text(
          l10n.aiCoverageEstimatedCredits(precheck.estimatedCoverageCredits!),
        ),
        Text(
          l10n.aiCoverageBufferedCreditsMinimum(
            coverageBufferedEstimate(precheck.estimatedCoverageCredits!),
          ),
        ),
        if (precheck.coverageBudgetCredits != null)
          Text(
            l10n.aiCoverageRunCapConfigured(precheck.coverageBudgetCredits!),
          ),
        if (precheck.platformCredits != null)
          Text(l10n.aiCoverageAccountBalance(precheck.platformCredits!)),
        if (coverage.runBudgetCredits != null &&
            coverage.runBudgetCredits != precheck.coverageBudgetCredits)
          Text(l10n.aiCoverageRunCapConfigured(coverage.runBudgetCredits!)),
        if ((minApiCalls ?? precheck.estimatedCoverageCredits!) >= 10)
          Text(
            l10n.aiCoveragePurchaseFooterConditional,
            style: context.vwCaption,
          ),
      ],
      if (precheck.useFullCoverage &&
          precheck.platformCredits != null &&
          precheck.estimatedCoverageCredits != null &&
          precheck.platformCredits! < precheck.estimatedCoverageCredits!) ...[
        const SizedBox(height: AppleSpacing.xs),
        Text(
          l10n.aiCoverageInsufficientForEstimate(
            precheck.estimatedCoverageCredits!,
            precheck.platformCredits!,
          ),
          style: AppleTypography.caption.copyWith(color: tokens.warning),
        ),
      ],
      if (precheck.useFullCoverage &&
          mode == AiMode.platform &&
          coverage.coverageCapBelowEstimate &&
          precheck.estimatedCoverageCredits != null &&
          precheck.coverageBudgetCredits != null) ...[
        const SizedBox(height: AppleSpacing.xs),
        Text(
          l10n.aiCoverageRunCapBelowBufferedEstimate(
            precheck.coverageBudgetCredits!,
            coverageBufferedEstimate(precheck.estimatedCoverageCredits!),
            precheck.estimatedCoverageCredits!,
          ),
          style: AppleTypography.caption.copyWith(color: tokens.warning),
        ),
        const SizedBox(height: AppleSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: AppleButton(
            label: l10n.aiCoverageRaiseBudgetToEstimate,
            icon: Icons.trending_up_outlined,
            variant: AppleButtonVariant.pearl,
            onPressed: () => unawaited(actions.raiseConfiguredCoverageCap()),
          ),
        ),
      ],
      if (precheck.useFullCoverage) ...[
        const SizedBox(height: AppleSpacing.xs),
        Text(
          mode == AiMode.platform
              ? l10n.aiCoverageFullRunPlatformHint
              : l10n.aiCoverageFullRunHint,
          style: context.vwCaption,
        ),
        if (mode == AiMode.platform &&
            precheck.coverageBudgetCredits != null &&
            (coverage.jobState == null ||
                coverage.jobState!.status == CoverageJobStatus.idle)) ...[
          const SizedBox(height: AppleSpacing.xxs),
          Text(
            l10n.aiCoverageRunBudgetConfigured(precheck.coverageBudgetCredits!),
            style: context.vwCaptionStrong,
          ),
        ],
        if (precheck.coverageHydrating) ...[
          const SizedBox(height: AppleSpacing.xs),
          Text(l10n.aiCoverageHydrating, style: context.vwCaption),
        ],
        if (precheck.planLoadError != null) ...[
          const SizedBox(height: AppleSpacing.xs),
          Text(
            precheck.planLoadError!,
            style: AppleTypography.caption.copyWith(color: tokens.warning),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: AppleButton(
              label: l10n.aiActionRetry,
              icon: Icons.refresh_outlined,
              variant: AppleButtonVariant.pearl,
              onPressed: () => unawaited(actions.refreshPrecheck()),
            ),
          ),
        ],
        if (mode == AiMode.platform &&
            precheck.platformCredits != null &&
            precheck.coverageBudgetCredits != null &&
            precheck.platformCredits! < precheck.coverageBudgetCredits!) ...[
          const SizedBox(height: AppleSpacing.xs),
          Text(
            l10n.aiCoveragePlatformBudgetWarning(
              precheck.platformCredits!,
              precheck.coverageBudgetCredits!,
            ),
            style: AppleTypography.caption.copyWith(color: tokens.warning),
          ),
        ],
      ],
      if (precheck.useFullCoverage &&
          precheck.coverageHydrated &&
          planIsLocalOnly) ...[
        const SizedBox(height: AppleSpacing.md),
        Text(l10n.aiPreCheckLocalOnlyTitle, style: context.vwBodyStrong),
        const SizedBox(height: AppleSpacing.xxs),
        Text(l10n.aiPreCheckLocalOnlyBody, style: context.vwCaption),
        const SizedBox(height: AppleSpacing.sm),
        AppleButton(
          label: l10n.aiStartLocalOnly,
          icon: Icons.checklist_outlined,
          expanded: true,
          onPressed: () => unawaited(actions.openLocalOnlyResults()),
        ),
      ],
    ];
  }

  List<Widget> _buildFullCoverageChildren(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.volward;
    final summary = coverage.planSummary;
    final localPlanned = summary == null || summary.planVersion < 3
        ? null
        : (summary.localSafeFiles ?? 0) + (summary.localKeepFiles ?? 0);
    final localResolved = coverage.jobState?.localRuleFiles ?? 0;
    final localComplete =
        coverage.jobState?.localPhaseComplete == true ||
        (localPlanned != null &&
            localPlanned > 0 &&
            localResolved >= localPlanned);
    final aiPlanned = summary == null
        ? precheck.displayUnknownCount
        : (summary.treePendingFiles ?? 0) +
              (summary.tailFiles ?? summary.tailFileCount ?? 0);
    final aiResolved = coverage.jobState?.aiResolvedFiles ?? 0;

    return [
      if (precheck.candidatesBootstrapPending) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AiAnalysisActivityInlineSpinner(
              color: tokens.primary,
              size: 14,
              strokeWidth: 2,
            ),
            const SizedBox(width: AppleSpacing.sm),
            Expanded(
              child: Text(
                l10n.aiCandidatesBootstrapLoading,
                style: context.vwCaption,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppleSpacing.sm),
      ],
      AiAnalysisPurchaseView(
        precheck: precheck,
        onOpenSettings: onOpenSettings,
      ),
      if (precheck.error != null &&
          (precheck.hasProvider ||
              (precheck.mode == AiMode.platform &&
                  precheck.platformCredits != 0))) ...[
        Text(
          precheck.error!,
          style: AppleTypography.caption.copyWith(color: tokens.danger),
        ),
        const SizedBox(height: AppleSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: AppleButton(
            label: l10n.aiActionRetry,
            icon: Icons.refresh_outlined,
            variant: AppleButtonVariant.pearl,
            onPressed: () => unawaited(
              actions.startAnalysis(fullCoverage: precheck.useFullCoverage),
            ),
          ),
        ),
        const SizedBox(height: AppleSpacing.sm),
      ],
      _CoverageStageRow(
        icon: Icons.shield_outlined,
        title: l10n.aiAnalysisStageCandidateTitle,
        detail: l10n.aiAnalysisStageCandidateDetail(
          precheck.displayPreClassifiedCount,
        ),
        color: Colors.green.shade700,
      ),
      const SizedBox(height: AppleSpacing.sm),
      _CoverageStageRow(
        icon: Icons.rule_folder_outlined,
        title: l10n.aiAnalysisStageLocalTitle,
        detail: localPlanned == null || localPlanned <= 0
            ? l10n.aiAnalysisStageLocalPreparing
            : l10n.aiAnalysisStageLocalProgress(localResolved, localPlanned),
        color: localComplete ? Colors.green.shade700 : tokens.primary,
        progress: localPlanned == null || localPlanned <= 0
            ? null
            : (localResolved / localPlanned).clamp(0, 1).toDouble(),
      ),
      const SizedBox(height: AppleSpacing.sm),
      _CoverageStageRow(
        icon: Icons.auto_awesome_outlined,
        title: l10n.aiAnalysisStageAiTitle,
        detail: localComplete
            ? l10n.aiAnalysisStageAiProgress(aiResolved, aiPlanned)
            : l10n.aiClassificationAiWaitingForLocal,
        color: localComplete ? tokens.primary : AppleColors.inkMuted48,
      ),
      if (precheck.platformCredits != null &&
          precheck.estimatedCoverageCredits != null &&
          precheck.platformCredits! < precheck.estimatedCoverageCredits!) ...[
        const SizedBox(height: AppleSpacing.xs),
        Text(
          l10n.aiCoverageInsufficientForEstimate(
            precheck.estimatedCoverageCredits!,
            precheck.platformCredits!,
          ),
          style: AppleTypography.caption.copyWith(color: tokens.warning),
        ),
      ],
      const SizedBox(height: AppleSpacing.sm),
      _PlanDetailsDisclosure(
        key: AiAnalysisWorkspaceKeys.coveragePlanDetailsKey,
        title: l10n.aiAnalysisPlanDetails,
        children: _buildPlanDetailLines(context),
      ),
    ];
  }

  List<Widget> _buildPlanDetailLines(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.volward;
    final summary = coverage.planSummary;
    final minApiCalls = summary == null
        ? null
        : coveragePlanMinApiCalls(summary);
    return [
      ..._buildEstimateLines(
        context,
        minApiCalls,
        coveragePlanSummaryShowsV3PrecheckBreakdown(summary),
      ),
      const SizedBox(height: AppleSpacing.xs),
      Text(l10n.aiCoverageFullRunPlatformHint, style: context.vwCaption),
      if (precheck.mode == AiMode.platform &&
          precheck.estimatedCoverageCredits != null) ...[
        const SizedBox(height: AppleSpacing.xxs),
        Text(
          l10n.aiCoverageEstimatedCredits(precheck.estimatedCoverageCredits!),
          style: context.vwCaption,
        ),
      ],
      if (precheck.mode == AiMode.platform &&
          precheck.coverageBudgetCredits != null)
        Text(
          l10n.aiCoverageRunCapConfigured(precheck.coverageBudgetCredits!),
          style: context.vwCaption,
        ),
      if (precheck.mode == AiMode.platform && precheck.platformCredits != null)
        Text(
          l10n.aiCoverageAccountBalance(precheck.platformCredits!),
          style: context.vwCaption,
        ),
      if (precheck.planLoadError != null) ...[
        const SizedBox(height: AppleSpacing.xs),
        Text(
          precheck.planLoadError!,
          style: AppleTypography.caption.copyWith(color: tokens.warning),
        ),
      ],
    ];
  }

  List<Widget> _buildEstimateLines(
    BuildContext context,
    int? minApiCalls,
    bool showsV3Breakdown,
  ) {
    final l10n = context.l10n;
    final tokens = context.volward;
    if (precheck.useFullCoverage) {
      if (precheck.coverageHydrating &&
          precheck.estimatedCoverageCredits == null) {
        return [
          Text(
            l10n.aiPreCheckCoverageEstimatePending,
            style: context.vwCaption,
          ),
        ];
      }
      final summary = coverage.planSummary;
      if (summary != null && summary.planVersion >= 3) {
        final treePending = summary.treePendingFiles ?? 0;
        final tailFiles = summary.tailFiles ?? summary.tailFileCount ?? 0;
        final minCalls = coveragePlanMinApiCalls(summary);
        final credits = precheck.estimatedCoverageCredits ?? minCalls;
        if (showsV3Breakdown) {
          return [
            Text(
              l10n.aiPreCheckAiScopeV2(treePending, tailFiles, minCalls),
              style: context.vwCaption,
            ),
            if (treePending > 0) ...[
              const SizedBox(height: AppleSpacing.xxs),
              Text(
                l10n.aiPreCheckTreeCreditsMayGrow,
                style: context.vwFinePrint.copyWith(color: tokens.inkMuted80),
              ),
            ],
          ];
        }
        return [
          Text(
            l10n.aiPreCheckAiScopeV2(treePending, tailFiles, minCalls),
            style: context.vwCaption,
          ),
          if (minCalls > 0)
            Text(
              l10n.aiPreCheckFullCoverageEstimate(credits, minCalls),
              style: context.vwCaptionStrong,
            ),
          if (treePending > 0) ...[
            const SizedBox(height: AppleSpacing.xxs),
            Text(
              l10n.aiPreCheckTreeCreditsMayGrow,
              style: context.vwFinePrint.copyWith(color: tokens.inkMuted80),
            ),
          ],
        ];
      }
    }
    final unknown = precheck.unknown;
    final batchCount = precheck.truncated
        ? unknown.length.clamp(0, kDefaultAiCandidateCap)
        : (unknown.isNotEmpty
              ? unknown.length
              : precheck.displayUnknownCount.clamp(0, kDefaultAiCandidateCap));
    final batchTokens = precheck.estimatedByokBatchTokens > 0
        ? precheck.estimatedByokBatchTokens
        : (unknown.isNotEmpty
              ? estimateByokBatchInputTokens(unknown, kByokAnalyzeBatchSize)
              : precheck.estimatedTokens);
    return [
      Text(
        l10n.aiPreCheckUnknownTitle(
          precheck.displayUnknownCount,
          batchTokens,
          kByokAnalyzeBatchSize,
          kDefaultAiCandidateCap,
        ),
        style: context.vwCaption,
      ),
      if (precheck.truncated && !precheck.useFullCoverage)
        Text(
          l10n.aiTruncatedNotice(
            batchCount,
            precheck.candidatesBeforeCap,
            kDefaultAiCandidateCap,
          ),
          style: AppleTypography.caption.copyWith(color: tokens.warning),
        ),
    ];
  }

  List<Widget> _buildUnknownScopeSampleSection(BuildContext context) {
    final l10n = context.l10n;
    if (precheck.displayUnknownCount == 0 ||
        precheck.displayUnknownCount > kDefaultAiCandidateCap) {
      return const [];
    }
    if (precheck.unknownCandidatesSpillPath != null &&
        precheck.unknown.isEmpty) {
      unawaited(actions.loadUnknownCandidateSample());
      return const [];
    }
    final sample = precheck.unknown
        .take(kAiResultsScopeUnknownSampleCap)
        .toList();
    if (sample.isEmpty) return const [];
    final remaining = precheck.displayUnknownCount - sample.length;
    return [
      const SizedBox(height: AppleSpacing.md),
      Text(
        l10n.aiResultsScopeUnknownSampleHeader,
        style: context.vwCaptionStrong,
      ),
      const SizedBox(height: AppleSpacing.xxs),
      for (final candidate in sample)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: _PathLabel(candidate.path),
          subtitle: Text(_formatBytes(candidate.sizeBytes)),
        ),
      if (remaining > 0)
        Text(
          l10n.aiResultsScopeUnknownSampleFooter(remaining),
          style: context.vwFinePrint,
        ),
    ];
  }

  static String _formatBytes(num? bytes) {
    if (bytes == null) return '-';
    final value = bytes.toInt();
    if (value < 1024) return '$value B';
    if (value < 1048576) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1073741824) {
      return '${(value / 1048576).toStringAsFixed(1)} MB';
    }
    return '${(value / 1073741824).toStringAsFixed(2)} GB';
  }
}

class _CoverageStageRow extends StatelessWidget {
  const _CoverageStageRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color color;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppleSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.vwCaptionStrong),
              const SizedBox(height: AppleSpacing.xxs),
              Text(detail, style: context.vwCaption),
              if (progress case final value?) ...[
                const SizedBox(height: AppleSpacing.xxs),
                LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(AppleRadius.pill),
                  color: color,
                  backgroundColor: AppleColors.dividerSoft,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanDetailsDisclosure extends StatefulWidget {
  const _PlanDetailsDisclosure({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  State<_PlanDetailsDisclosure> createState() => _PlanDetailsDisclosureState();
}

class _PlanDetailsDisclosureState extends State<_PlanDetailsDisclosure> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.volward;
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppleRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppleSpacing.sm,
                horizontal: AppleSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title, style: context.vwBodyStrong),
                  ),
                  Text(
                    _expanded ? '▴' : '▾',
                    style: context.vwBodyStrong.copyWith(
                      color: tokens.inkMuted80,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(
                      top: AppleSpacing.xs,
                      bottom: AppleSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: widget.children,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _PathLabel extends StatelessWidget {
  const _PathLabel(this.path);

  final String path;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      value: path,
      child: Text(
        path,
        maxLines: 2,
        softWrap: true,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
