import 'dart:async';

import '../../../ai/ai_analysis_gateway.dart';
import '../../../ai/ai_provider.dart';
import '../../../ai/coverage_job_state.dart';
import '../../../ai/coverage_ui_helpers.dart';
import '../../../analytics/analytics_events.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../ports/workspace_ports.dart';

Future<void> recordByokTokenUsage({
  required AiAnalysisGateway gateway,
  required WorkspaceAnalyticsPort analytics,
  required int inputTokens,
  required int outputTokens,
  required int totalTokens,
  required bool estimated,
  required bool partial,
}) async {
  try {
    final totals = await gateway.recordByokTokenUsage(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTokens: totalTokens,
      estimated: estimated,
      partial: partial,
    );
    unawaited(
      analytics.track(AnalyticsEvents.aiByokTokenUsageRecorded, {
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        'total_tokens': totalTokens,
        'usage_source': partial
            ? estimated
                  ? 'estimate_partial'
                  : 'provider_partial'
            : estimated
            ? 'estimate'
            : 'provider',
        'cumulative_input_tokens': totals.inputTokens,
        'cumulative_output_tokens': totals.outputTokens,
        'cumulative_total_tokens': totals.totalTokens,
        'cumulative_analysis_count': totals.analysisCount,
        'cumulative_estimated_count': totals.estimatedAnalysisCount,
        'cumulative_partial_count': totals.partialAnalysisCount,
      }),
    );
  } catch (_) {
    // Usage accounting must not turn a completed AI request into failure.
  }
}

String normalizeAiError(Object error) {
  final message = error.toString();
  for (final key in const [
    'invalid_api_key',
    'request_timeout',
    'rate_limited_after_retries',
    'empty_api_key',
    'insufficient_credits',
    'link_account_required',
    'session_expired',
    'ai_contract_unavailable',
    'platform_api_unconfigured',
  ]) {
    if (message.contains(key)) return key;
  }
  if (message.contains('api_error:')) return 'api_error';
  if (message.contains('network_error')) return 'network_error';
  return 'unknown';
}

String localizedAiError(Object error, AppLocalizations l10n) {
  return switch (normalizeAiError(error)) {
    'request_timeout' => l10n.aiErrorTimeout,
    'rate_limited_after_retries' => l10n.aiErrorRateLimited,
    'network_error' => l10n.aiErrorNetwork,
    'invalid_api_key' || 'empty_api_key' => l10n.aiNoApiKey,
    'ai_contract_unavailable' ||
    'platform_api_unconfigured' => l10n.aiContractUnavailable,
    'link_account_required' => l10n.aiSettingsSessionExpired,
    _ => l10n.aiErrorUnknown,
  };
}

class PendingVerdictPreview {
  static const maxPreviewCandidates = 128;
  (List<AiCandidate>, Set<String>, String, int)? _key;
  List<AiVerdict> _rows = const [];
  List<AiVerdict> build({
    required bool useFullCoverage,
    required CoverageJobState? jobState,
    required List<AiCandidate> unknown,
    required Set<String> verdictPaths,
    required AppLocalizations l10n,
  }) {
    final pending = jobState == null
        ? 0
        : jobState.totalUnclassified - jobState.analyzedFiles;
    if (!useFullCoverage ||
        jobState?.status == CoverageJobStatus.completed ||
        pending <= 0) {
      _key = null;
      return _rows = const [];
    }
    final key = (unknown, verdictPaths, l10n.localeName, pending);
    if (_key == key) return _rows;
    _key = key;
    return _rows = List.unmodifiable(
      buildUnanalyzedDisplayVerdicts(
        pendingFileCount: pending,
        previewCandidates: unknown.take(maxPreviewCandidates),
        verdictPaths: verdictPaths,
        itemReason: l10n.aiCoverageUnanalyzedReason,
        aggregateSummaryReason: (remaining) =>
            l10n.aiCoverageUnanalyzedAggregate(remaining),
      ),
    );
  }
}
