import 'package:flutter/widgets.dart';

import '../l10n/generated/app_localizations.dart';
import 'coverage_job_state.dart';

AppLocalizations coverageNotifyLocalizations() {
  final locale = WidgetsBinding.instance.platformDispatcher.locale;
  return lookupAppLocalizations(locale);
}

({String title, String body}) coverageCompleteNotification(
  AppLocalizations l10n,
  CoverageJobState state,
) => (
  title: l10n.aiCoverageNotifyTitle,
  body: l10n.aiCoverageNotifyComplete(
    state.analyzedFiles,
    state.totalUnclassified,
  ),
);

({String title, String body}) coverageBudgetPausedNotification(
  AppLocalizations l10n,
  CoverageJobState state,
) => (
  title: l10n.aiCoverageNotifyTitle,
  body: l10n.aiCoverageNotifyBudgetPaused(
    state.analyzedFiles,
    state.totalUnclassified,
  ),
);

({String title, String body}) coverageFailedNotification(
  AppLocalizations l10n,
) => (title: l10n.aiCoverageNotifyTitle, body: l10n.aiCoverageNotifyFailed);
