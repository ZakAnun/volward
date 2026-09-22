// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Volward';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearanceSection => 'Appearance';

  @override
  String get settingsThemeTitle => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsAccentColorTitle => 'Accent color';

  @override
  String get settingsAccentColorDescription =>
      'Applies to buttons, selections, and progress indicators.';

  @override
  String get settingsAccentPreview => 'Preview';

  @override
  String get settingsAccentPrimary => 'Primary';

  @override
  String get settingsLanguageTitle => 'Language';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get settingsLanguageChinese => 'Chinese';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsScanResultsSection => 'Scan & results';

  @override
  String get settingsDeletableOnlyTitle => 'Deletable only';

  @override
  String get settingsDeletableOnlyDescription =>
      'Only show entries Volward marks as low-risk cleanup candidates, currently cache and temp files.';

  @override
  String get settingsIncrementalScanTitle => 'Incremental scan';

  @override
  String get settingsIncrementalScanDescription =>
      'Reuse unchanged subdirectories from the previous scan of the same folder to speed up later scans.';

  @override
  String get settingsIncrementalScanUnsupported =>
      'The bundled Rust library does not support this scan mode yet. Rebuild Rust before using it.';

  @override
  String get filterAll => 'All';

  @override
  String get filterCategoryCache => 'Cache';

  @override
  String get filterCategoryTemp => 'Temp';

  @override
  String get filterCategoryMedia => 'Media';

  @override
  String get filterCategorySystem => 'System';

  @override
  String get homeCategoryOther => 'Other';

  @override
  String get sortSizeDesc => 'Size ↓';

  @override
  String get sortSizeAsc => 'Size ↑';

  @override
  String get sortNameAsc => 'Name';

  @override
  String get scanColumnPreparingFolder => 'Preparing folder…';

  @override
  String get scanColumnNoFilterMatches => 'No items match the current filters.';

  @override
  String get navSubtitle => 'Storage steward';

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get scanActionFolder => 'Folder…';

  @override
  String get scanActionHome => 'Home';

  @override
  String get scanActionCancel => 'Cancel';

  @override
  String get scanActionStart => 'Start scan';

  @override
  String get scanActionRescan => 'Refresh';

  @override
  String get trashActionEmpty => 'Empty Trash';

  @override
  String get trashEmptyConfirmTitle => 'Empty Trash?';

  @override
  String get trashEmptyConfirmMessage =>
      'Permanently delete everything in Trash? This cannot be undone.';

  @override
  String get trashEmptySuccess => 'Trash emptied. Results refreshed.';

  @override
  String trashEmptyFailed(Object error) {
    return 'Empty Trash failed: $error';
  }

  @override
  String get deleteActionMoveToTrash => 'Move to Trash';

  @override
  String get deleteActionWorking => 'Working…';

  @override
  String get deleteConfirmTitle => 'Move to Trash?';

  @override
  String deleteConfirmMessage(int count, Object bytes) {
    return 'Move $count item(s) to Trash and free about $bytes?\n\nYou can restore them from Trash if needed.';
  }

  @override
  String get deleteActionDelete => 'Delete';

  @override
  String deleteSuccessWithFailures(int failedCount, Object bytes) {
    return 'Deleted with $failedCount failure(s). Freed $bytes.';
  }

  @override
  String deleteSuccess(Object bytes) {
    return 'Moved to Trash. Freed $bytes. Rescan complete.';
  }

  @override
  String deleteFailed(Object error) {
    return 'Delete failed: $error';
  }

  @override
  String get permissionNativeOutdatedTitle => 'Native library outdated';

  @override
  String get permissionNativeOutdatedDescription =>
      'Rebuild the native Rust library for this platform and fully restart the app.';

  @override
  String get permissionDeepScanReady => 'Deep scan is available.';

  @override
  String get permissionFullDiskRecommended =>
      'Full Disk Access recommended for ~/Library cache scan.';

  @override
  String get permissionFullDiskRecommendedTitle =>
      'Full Disk Access recommended';

  @override
  String get permissionFullDiskInstructions =>
      'System Settings → Privacy & Security → Full Disk Access → enable Volward. Debug builds: tap +, Cmd+Shift+G, select volward.app.';

  @override
  String get permissionOpenSettings => 'Open Settings';

  @override
  String get permissionShowDetails => 'Show details';

  @override
  String get permissionHideDetails => 'Hide details';

  @override
  String get permissionCopyAppPath => 'Copy .app path';

  @override
  String get permissionCheckAgain => 'Check again';

  @override
  String permissionCopiedPath(Object path) {
    return 'Copied: $path';
  }

  @override
  String permissionAppPath(Object path) {
    return 'App path: $path';
  }

  @override
  String get permissionUnknownPath => 'unknown';

  @override
  String get folderPickerConfirm => 'Select';

  @override
  String get scanTargetTitle => 'Target';

  @override
  String get scanTargetHomeDefault => 'Home (default)';

  @override
  String get scanTargetHomeShort => 'Home';

  @override
  String get scanTargetCustomShort => 'Custom';

  @override
  String get scanHomeLongRunningHint =>
      'Full Home scan can take many minutes on large accounts — watch the item count above.';

  @override
  String resultsClassifiedCount(int count) {
    return '$count classified';
  }

  @override
  String resultsReclaimableBytes(Object bytes) {
    return '$bytes reclaimable';
  }

  @override
  String resultsTreeSummary(int count, Object bytes) {
    return '$count in tree · $bytes';
  }

  @override
  String get resultsUpdating => 'Updating results…';

  @override
  String get resultsNoFilterMatches => 'No items match the current filters.';

  @override
  String resultsNoFilterMatchesWithCount(int count) {
    return 'No items match the current filters ($count in list).';
  }

  @override
  String resultsNoFilesUnder(Object path) {
    return 'Scan returned no files under $path.';
  }

  @override
  String get resultsRestoringPreviousScan => 'Restoring previous scan…';

  @override
  String get previewSelectPrompt => 'Select a folder or file';

  @override
  String get previewFolderCategory => 'Folder';

  @override
  String previewItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get scanStatusScanning => 'Scanning…';

  @override
  String get scanPhaseDiscoveringRoots => 'Discovering roots…';

  @override
  String get scanPhaseWalking => 'Scanning files…';

  @override
  String get scanPhaseClassifying => 'Classifying entries…';

  @override
  String get scanPhaseAggregating => 'Aggregating results…';

  @override
  String get scanPhaseSavingResults => 'Saving results…';

  @override
  String get scanPhaseLoadingResults => 'Loading results…';

  @override
  String get scanPhaseDone => 'Done';

  @override
  String scanProgressItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get scanStatusCancelled => 'Scan cancelled';

  @override
  String scanStatusFailed(Object error) {
    return 'Scan failed: $error';
  }

  @override
  String get scanPauseFailed =>
      'Couldn\'t pause the current scan. Stay on this folder.';

  @override
  String get scanCacheUnreadable =>
      'This folder\'s cache is unreadable. Scanning again.';

  @override
  String get scanCacheTooLarge =>
      'This folder\'s cache is too large to restore. Scan again to refresh it.';

  @override
  String get scanCacheRestoreTimeout =>
      'This folder\'s cache took too long to restore. Scanning again.';

  @override
  String get scanStatusFull => 'Full';

  @override
  String get scanStatusIncremental => 'Incremental';

  @override
  String scanStatusFiles(Object mode, int count) {
    return '$mode scan: $count files';
  }

  @override
  String stickySelected(int count, Object bytes) {
    return 'Selected: $count · $bytes';
  }

  @override
  String stickyDirectoriesLoading(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count directories loading…',
      one: '1 directory loading…',
    );
    return '$_temp0';
  }

  @override
  String get stickyBrowseResults => 'Select items to move to Trash';

  @override
  String get stickyReadyToScan => 'Ready to scan';

  @override
  String get stickyLoadingEngine => 'Loading engine…';

  @override
  String get settingsAboutSection => 'About';

  @override
  String settingsCurrentVersion(Object version) {
    return 'Version $version';
  }

  @override
  String get settingsCheckForUpdates => 'Check for updates';

  @override
  String get settingsCheckingForUpdates => 'Checking…';

  @override
  String get settingsUpToDate => 'You\'re up to date.';

  @override
  String settingsUpdateAvailable(Object version) {
    return 'Update available: $version';
  }

  @override
  String get settingsUpdateNow => 'Update now';

  @override
  String settingsDownloadingUpdate(int percent) {
    return 'Downloading update… $percent%';
  }

  @override
  String get settingsInstallingUpdate => 'Installing update…';

  @override
  String settingsUpdateError(Object error) {
    return 'Update check failed: $error';
  }

  @override
  String settingsUpdateActionError(Object error) {
    return 'Update failed: $error';
  }

  @override
  String get settingsAutoDownloadUpdatesTitle =>
      'Download updates in background';

  @override
  String get settingsAutoDownloadUpdatesDescription =>
      'Automatically download updates so they\'re ready to install.';

  @override
  String get settingsOpenDownloadPage => 'Open download page';

  @override
  String get settingsUpdateReady => 'A new version is downloaded and ready.';

  @override
  String get updateReadyAction => 'Complete update';

  @override
  String get updateReadyDismissTooltip => 'Dismiss';

  @override
  String updateReadyTooltip(Object version) {
    return 'Update to version $version';
  }

  @override
  String get homeOverviewLive => 'Live disk data';

  @override
  String get homeOverviewCached => 'Cached disk data';

  @override
  String get homeOverviewLoading => 'Reading disk…';

  @override
  String get homeOverviewUnavailable => 'Disk capacity unavailable';

  @override
  String get homeCapacityUsed => 'Used';

  @override
  String get homeCapacityTotal => 'Total capacity';

  @override
  String get homeCapacityAvailable => 'Available';

  @override
  String homeCapacitySemantics(String used, String total, String available) {
    return '$used used of $total, $available available';
  }

  @override
  String get homeScanTargets => 'Scan range';

  @override
  String get homeLocationHome => 'Home';

  @override
  String get homeLocationApplications => 'Applications';

  @override
  String get homeLocationDesktop => 'Desktop';

  @override
  String get homeLocationDownloads => 'Downloads';

  @override
  String get homeLocationDocuments => 'Documents';

  @override
  String homeLocationVolume(String name) {
    return 'Disk $name';
  }

  @override
  String homeLocationCustom(String name) {
    return '$name';
  }

  @override
  String get homeChooseFolder => 'Choose Folder';

  @override
  String get homeCurrentTarget => 'Current target';

  @override
  String get homeRecentFolders => 'Recent Folders';

  @override
  String homeLastScan(String time) {
    return 'Last scan $time';
  }

  @override
  String get homeNeverScanned => 'Not scanned yet';

  @override
  String homeReclaimable(String size) {
    return '$size reclaimable';
  }

  @override
  String homeScannedSize(String size) {
    return '$size scanned';
  }

  @override
  String get homeLargestItems => 'Largest items';

  @override
  String homeLargestItemsTotal(String size) {
    return '$size total';
  }

  @override
  String get homeLargestItemsEmpty => 'Shown after scanning';

  @override
  String get homeFolderEmpty => 'This folder is empty';

  @override
  String homeLargestItemsSemantics(
    String name,
    String size,
    int rank,
    int count,
  ) {
    return '$name, $size, $rank of $count';
  }

  @override
  String get aiAnalysisTitle => 'AI Disk Analysis';

  @override
  String aiPreCheckSafeTitle(int count) {
    return '$count items pre-identified as safe to remove';
  }

  @override
  String aiPreCheckSafeSelectable(int count) {
    return '$count items already marked safe by local rules';
  }

  @override
  String aiPreCheckUnknownTitle(int count, int tokens, int batchSize, int cap) {
    return '$count items still need AI (BYOK ~$tokens input tokens per API call, up to $batchSize items each; $cap items max per analysis)';
  }

  @override
  String get aiPreCheckCoverageEstimatePending =>
      'Estimating full coverage cost…';

  @override
  String aiPreCheckAiScope(int tree, int tail) {
    return '$tree files need directory AI, $tail loose files in tail queue';
  }

  @override
  String aiPreCheckAiScopeV2(int treePending, int tail, int apiCalls) {
    return 'Directory AI scope: ~$treePending files · tail queue: $tail files · about $apiCalls API calls (minimum)';
  }

  @override
  String get aiPreCheckLocalOnlyTitle => 'No API calls needed for this scan';

  @override
  String get aiPreCheckLocalOnlyBody =>
      'Local rules already cover the directory and tail queues. Review local results without starting full coverage.';

  @override
  String get aiStartLocalOnly => 'Review local results';

  @override
  String aiPreCheckFullCoverageEstimate(int credits, int calls) {
    return '~$credits credits minimum ($calls API calls from plan; tree BFS may add more)';
  }

  @override
  String get aiPreCheckTreeCreditsMayGrow =>
      'Directory tree analysis may use more credits than this plan minimum.';

  @override
  String get aiPreCheckSelectAllShown => 'Select all shown';

  @override
  String get aiPreCheckClearSelection => 'Clear selection';

  @override
  String get aiStartAnalysis => 'Start AI Analysis';

  @override
  String get aiNoApiKey => 'No API Key — configure in Settings';

  @override
  String get aiContractUnavailable =>
      'The installed native library is out of date. Please update Volward to use AI analysis.';

  @override
  String aiDeleteSelected(int count) {
    return 'Move $count Selected to Trash';
  }

  @override
  String aiVerdictSafe(int count) {
    return 'Safe to Remove ($count)';
  }

  @override
  String aiVerdictReview(int count) {
    return 'Review Needed ($count)';
  }

  @override
  String aiVerdictKeep(int count) {
    return 'Keep ($count)';
  }

  @override
  String get aiSettingsTitle => 'AI Analysis';

  @override
  String get aiSettingsModeLabel => 'Mode';

  @override
  String get aiSettingsByokLabel => 'Bring Your Own Key (DeepSeek)';

  @override
  String get aiSettingsOffLabel => 'Off';

  @override
  String get aiSettingsPlatformLabel => 'Volward Platform';

  @override
  String get aiSettingsPlatformLoading => 'Connecting platform account…';

  @override
  String get aiSettingsApiKeyHint => 'sk-...';

  @override
  String get aiSettingsApiKeySaved => 'API key saved';

  @override
  String get aiSettingsApiKeyCleared => 'API key cleared';

  @override
  String get aiSettingsSaveKey => 'Save';

  @override
  String get aiSettingsClearKey => 'Clear';

  @override
  String get aiSettingsLinkEmail => 'Link email';

  @override
  String get aiSettingsEnterEmail => 'Email address';

  @override
  String get aiSettingsEnterOtp => 'Enter the 6-digit code from your email';

  @override
  String get aiSettingsSendOtp => 'Send code';

  @override
  String get aiSettingsVerifyOtp => 'Verify';

  @override
  String get aiSettingsLinkSuccess => 'Email linked successfully';

  @override
  String get aiSettingsResendOtp => 'Resend code';

  @override
  String aiSettingsResendCooldown(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get aiSettingsInvalidEmail => 'Enter a valid email address';

  @override
  String aiSettingsLinkedAs(String email) {
    return 'Linked as $email';
  }

  @override
  String aiSettingsCreditsRemaining(int count) {
    return '$count credits remaining';
  }

  @override
  String get aiSettingsBuyCredits => 'Buy credits';

  @override
  String get aiPurchasePayHint =>
      'Pay with WeChat on the checkout page. Balance updates after payment.';

  @override
  String get aiPurchaseWaitingHint =>
      'Payment may still be processing. Wait a moment, then refresh your credits in Settings.';

  @override
  String aiPurchasePackCredits(int count) {
    return '$count credits';
  }

  @override
  String aiPurchasePriceCny(String price) {
    return '¥$price';
  }

  @override
  String get aiPurchaseNoPacks => 'No credit packs available.';

  @override
  String get aiPurchaseOpenInBrowser => 'Open payment page in browser';

  @override
  String get aiPurchaseScanQrHint => 'Or scan with your phone (WeChat)';

  @override
  String get aiPurchaseWaitingPayment => 'Waiting for payment confirmation…';

  @override
  String aiPurchaseSelectedSummary(String label, int credits, String price) {
    return '$label · $credits credits · ¥$price';
  }

  @override
  String get aiPurchaseBackToPacks => 'Choose another pack';

  @override
  String get aiSettingsSessionExpired =>
      'Login expired — please link your email again.';

  @override
  String get aiErrorOtpResendTooSoon =>
      'Too many requests. Try again in 60 seconds.';

  @override
  String get aiErrorOtpRequestFailed =>
      'Failed to send code. Check your email and try again.';

  @override
  String get aiErrorOtpVerifyFailed =>
      'Invalid or expired code. Request a new one.';

  @override
  String get aiErrorDeviceRegisterFailed =>
      'Device registration failed. Check your connection.';

  @override
  String get aiErrorLinkAccountRequired => 'Link your email to continue.';

  @override
  String get aiErrorPlatformApiUnconfigured =>
      'Platform API is not configured.';

  @override
  String get aiErrorDeviceNotFound => 'Device not registered. Restart the app.';

  @override
  String get aiErrorRefreshRateLimited =>
      'Refresh too frequent. Try again shortly.';

  @override
  String get aiErrorCheckoutFailed => 'Checkout failed. Try again later.';

  @override
  String get aiErrorCheckoutUrlInvalid =>
      'Payment page is unavailable. Please try again later.';

  @override
  String get aiErrorPacksFailed =>
      'Could not load packs. Check your connection.';

  @override
  String get aiErrorPlatformGeneric => 'Something went wrong. Try again later.';

  @override
  String aiPrecheckCreditsCost(int balance) {
    return 'Estimated cost: 1 credit (balance $balance)';
  }

  @override
  String get aiInsufficientCredits => 'No credits left — buy more in Settings.';

  @override
  String get aiAnalysisFab => 'AI Analysis';

  @override
  String get aiPrivacyTitle => 'AI analysis privacy';

  @override
  String get aiPrivacyBody =>
      'Only paths, sizes, and file counts are sent. File contents are never uploaded. BYOK sends data to DeepSeek; Platform mode sends data to Volward servers which forward to DeepSeek.';

  @override
  String get aiPrivacyAccept => 'I understand';

  @override
  String get aiOverwriteTitle => 'Previous analysis available';

  @override
  String get aiOverwriteBody =>
      'This scan already has an AI result. Load it, or re-analyze to overwrite.';

  @override
  String get aiActionContinue => 'Re-analyze';

  @override
  String get aiActionLoadPrevious => 'Load previous';

  @override
  String get aiLoadPreviousFailed => 'Could not load the previous AI result.';

  @override
  String get aiAnalyzing => 'Analyzing with AI…';

  @override
  String get aiActionRetry => 'Retry';

  @override
  String get aiErrorUnknown => 'Unknown error';

  @override
  String get aiErrorNativeUnavailable =>
      'Failed to load AI candidates (native API unavailable).';

  @override
  String get aiErrorInvalidPayload => 'Invalid candidates payload.';

  @override
  String aiTruncatedNotice(int shown, int total, int cap) {
    return 'Including the $shown largest of $total items ($cap cap) — the rest are skipped.';
  }

  @override
  String aiCoverageProgress(int analyzed, int total) {
    return 'Coverage: $analyzed / $total unclassified files resolved';
  }

  @override
  String aiCoverageFunnelBreakdown(
    int localSafe,
    int localKeep,
    int treePending,
    int tail,
  ) {
    return 'Local $localSafe safe · $localKeep keep · ~$treePending via directory AI · $tail tail files';
  }

  @override
  String aiCoverageApiCallsEstimate(int used, int min, int remaining) {
    return 'API calls this run: $used used · at least $min planned ($remaining left at plan minimum)';
  }

  @override
  String aiCoverageRemainingApiCalls(int remaining) {
    return 'About $remaining API calls left (plan minimum; directory drill-down may add more)';
  }

  @override
  String get aiCoveragePausedBeforeProgress =>
      'Local previews below are ready. Resume to flush local verdicts and run directory/tail AI on the rest.';

  @override
  String aiCoverageRemainingEstimate(int credits) {
    return 'About $credits credits remaining';
  }

  @override
  String aiCoverageAccountBalance(int credits) {
    return 'Account balance: $credits credits';
  }

  @override
  String aiCoverageEstimatedCredits(int credits) {
    return 'Estimated for full analysis: ~$credits credits';
  }

  @override
  String aiCoverageLocalResolved(int count) {
    return 'Locally resolved: $count files';
  }

  @override
  String aiCoverageEstimatedTreeRounds(int rounds) {
    return 'Estimated tree rounds: ~$rounds';
  }

  @override
  String aiCoverageEstimatedTailRounds(int rounds) {
    return 'Estimated tail rounds: ~$rounds';
  }

  @override
  String aiCoverageEstimatedCreditsTotal(int credits) {
    return 'Total estimated credits: ~$credits';
  }

  @override
  String get aiCoveragePurchaseFooter =>
      'Full analysis typically uses about 30–80 credits. You will see an estimate before starting.';

  @override
  String get aiCoveragePurchaseFooterConditional =>
      'Estimated API usage is shown above. Large home-folder scans often use about 30–80 credits.';

  @override
  String aiCoverageInsufficientForEstimate(int needed, int available) {
    return 'Need about $needed credits; you have $available.';
  }

  @override
  String aiCoverageFailedReason(Object reason) {
    return 'Analysis paused: $reason';
  }

  @override
  String get aiCoverageFailedReasonParse => 'AI response could not be parsed';

  @override
  String get aiCoverageFailedReasonNetwork => 'network or server error';

  @override
  String get aiCoverageFailedReasonApi => 'analysis service error';

  @override
  String get aiCoverageFailedReasonGeneric => 'analysis request failed';

  @override
  String aiCoverageFailedBatchItemsOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items did not receive results.',
      one: '1 item did not receive results.',
    );
    return '$_temp0';
  }

  @override
  String aiCoverageFailedBatchCredits(int credits, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      credits,
      locale: localeName,
      other:
          '$credits credits were used but $count items did not receive results.',
      one: '1 credit was used but $count items did not receive results.',
    );
    return '$_temp0';
  }

  @override
  String aiCoverageFailedBatchPathsPreview(Object paths) {
    return 'Affected: $paths';
  }

  @override
  String aiCoverageFailedBatchPathsOverflow(int count) {
    return '…and $count more';
  }

  @override
  String aiCoverageIncompleteGroupTitle(int count) {
    return 'Incomplete AI response ($count)';
  }

  @override
  String get aiCoverageFailedResumeTitle => 'Retry analysis?';

  @override
  String aiCoverageFailedResumeBody(int credits, int count) {
    return 'The last batch failed after using $credits credit(s). $count items were not saved. Retry may use additional credits.';
  }

  @override
  String aiCoverageFailedResumeBodyNoCredit(int count) {
    return 'The last batch failed. $count items were not saved. Retry may use additional credits.';
  }

  @override
  String get aiCoverageFailedResumeConfirm => 'Retry';

  @override
  String get aiCoverageLegacyJobHint =>
      'This job was paused under older analysis logic. Resume applies new rules (incomplete API responses are saved as review needed).';

  @override
  String get aiCoverageLegacyResumeTitle => 'Apply updated analysis logic?';

  @override
  String get aiCoverageLegacyResumeBody =>
      'Saved progress is from an older client. Resume continues from the cursor with new batch rules; verdicts already on disk are kept.';

  @override
  String get aiCoverageLegacyResumeConfirm => 'Continue';

  @override
  String get aiCoverageRestartFull => 'Restart full coverage';

  @override
  String get aiCoverageRestartFullTitle => 'Restart full coverage?';

  @override
  String get aiCoverageRestartFullBody =>
      'Clears coverage progress and saved verdicts for this snapshot and starts over. This may use credits or tokens again.';

  @override
  String get aiCoverageRestartFullConfirm => 'Restart';

  @override
  String get aiCoverageRaiseBudgetToEstimate => 'Raise limit to match estimate';

  @override
  String aiCoverageRunCapConfigured(int cap) {
    return 'Run cap for this scan: $cap credits';
  }

  @override
  String get aiCoverageFullRunHint =>
      'Full-coverage analysis runs in the background until every unclassified file has a verdict.';

  @override
  String get aiCoverageFullRunPlatformHint =>
      'Full-coverage runs in the background. Each AI request uses 1 platform credit from your balance. The run budget below caps credits spent on this scan.';

  @override
  String aiCoverageBudgetCreditsUsage(int used, int budget) {
    return 'Credits this run: $used / $budget';
  }

  @override
  String aiCoverageBudgetTokensUsage(int used, int budget) {
    return 'Tokens this run: $used / $budget';
  }

  @override
  String aiCoverageRunBudgetConfigured(int budget) {
    return 'Run budget for this scan: $budget credits';
  }

  @override
  String get aiCoveragePause => 'Pause coverage';

  @override
  String get aiCoverageResume => 'Resume coverage';

  @override
  String get aiCoverageCompletedNotice =>
      'This scan is fully covered by AI analysis.';

  @override
  String aiCoverageUnanalyzedCount(int count) {
    return '$count files not yet analyzed';
  }

  @override
  String aiCoverageSourceStats(int file, int group, int local) {
    return 'Verdict sources: $file file AI · $group directory AI · $local local';
  }

  @override
  String aiCoverageBudgetPausedCredits(int used, int budget) {
    return 'Run credit budget reached ($used/$budget). Raise the limit to continue, or adjust it in Settings.';
  }

  @override
  String aiCoverageBudgetPausedTokens(int used, int budget) {
    return 'Run token budget reached ($used/$budget). Raise the limit to continue, or adjust it in Settings.';
  }

  @override
  String get aiCoverageLegacyResultNotice =>
      'Showing a previous Top-150 result. Start full coverage for complete analysis.';

  @override
  String get aiCoverageUnanalyzedReason => 'Waiting for AI coverage analysis';

  @override
  String aiCoverageUnanalyzedAggregate(int count) {
    return 'Plus $count more files awaiting analysis';
  }

  @override
  String get aiCoverageCancel => 'Stop coverage';

  @override
  String get aiCoverageRaiseBudget => 'Raise limit & resume';

  @override
  String get aiCoverageRaiseBudgetTitle => 'Raise coverage budget';

  @override
  String get aiCoverageNotifyTitle => 'Volward AI';

  @override
  String aiCoverageNotifyComplete(int analyzed, int total) {
    return 'Coverage complete: $analyzed/$total files analyzed.';
  }

  @override
  String aiCoverageNotifyBudgetPausedCredits(int used, int budget) {
    return 'Coverage paused at run budget: $used/$budget credits used.';
  }

  @override
  String aiCoverageNotifyBudgetPausedTokens(int used, int budget) {
    return 'Coverage paused at run budget: $used/$budget tokens used.';
  }

  @override
  String get aiCoverageNotifyFailed =>
      'Coverage paused due to an error. Open AI results to retry.';

  @override
  String get aiCoverageBudgetInvalid =>
      'Enter a budget higher than the current limit.';

  @override
  String get aiCoverageJobBillingModeMismatchTitle =>
      'Coverage run uses a different billing mode';

  @override
  String aiCoverageJobBillingModeMismatchPlatform(int budget, int used) {
    return 'This run was started with a BYOK token limit ($budget tokens, $used used). You are in Platform mode, which bills credits. Restart full coverage to start a Platform run, or switch back to BYOK to resume this job.';
  }

  @override
  String aiCoverageJobBillingModeMismatchByok(int used, int budget) {
    return 'This run uses Platform credits ($used/$budget). You are in BYOK mode now. Restart full coverage to apply your token budget, or switch back to Platform to resume.';
  }

  @override
  String aiCoverageJobBillingModeMismatchBanner(String mode) {
    return 'Billing mode changed since this run started. Restart full coverage for $mode, or switch AI mode to match this job.';
  }

  @override
  String get aiCoverageHydrating => 'Loading coverage job status…';

  @override
  String get aiCandidatesBootstrapLoading => 'Loading candidate list…';

  @override
  String get aiCoverageUnavailable =>
      'Full-coverage analysis is unavailable right now. Try again after the scan finishes loading.';

  @override
  String get aiCoverageBusyOtherSnapshot =>
      'Another scan is running full-coverage analysis. Wait for it to finish or pause it first.';

  @override
  String aiCoveragePlatformBudgetWarning(int available, int budget) {
    return 'Platform balance ($available) is below the full-run budget ($budget). Analysis may pause early.';
  }

  @override
  String get aiSettingsCoverageBudgetInvalid => 'Enter a positive number.';

  @override
  String get aiSettingsCoverageBudgetTokensLabel =>
      'Full-coverage token budget (BYOK)';

  @override
  String get aiSettingsCoverageBudgetTokensHint => '500000';

  @override
  String get aiSettingsCoverageBudgetCreditsLabel =>
      'Full-coverage credit budget (Platform)';

  @override
  String get aiSettingsCoverageBudgetCreditsHint => '50';

  @override
  String get aiSettingsCoverageBudgetCreditsDescription =>
      'Per-scan credit spending cap (safety limit, not your account balance). Full-run estimate is shown before you start; raise this if the estimate exceeds the cap.';

  @override
  String get aiSettingsCoverageBudgetTokensDescription =>
      'Maximum tokens to spend on one full-coverage run. The job pauses when this cap is reached.';

  @override
  String get aiSettingsCoverageBudgetSave => 'Save budget';

  @override
  String get aiSettingsCoverageBudgetSaved => 'Coverage budget saved';

  @override
  String get aiCleanupSourceAiToolCache => 'AI tool cache/temp';

  @override
  String get aiCleanupSourceAiGeneratedOutput => 'AI-generated output';

  @override
  String get aiCleanupSourceSystemTemp => 'Temporary file';

  @override
  String aiCleanupRetentionDays(int days) {
    return 'Review after $days days';
  }

  @override
  String get aiWorkspaceTitle => 'AI Cleanup Suggestions';

  @override
  String get aiWorkspaceBack => 'Back to Overview';

  @override
  String get aiWorkspacePhaseLoading => 'Preparing candidates';

  @override
  String get aiWorkspacePhasePrecheck => 'Pre-check';

  @override
  String get aiWorkspacePhasePrivacy => 'Privacy';

  @override
  String get aiWorkspacePhaseAnalyzing => 'Analyzing';

  @override
  String get aiWorkspacePhaseReview => 'Review';

  @override
  String get aiWorkspacePhaseDeleting => 'Moving to Trash';

  @override
  String get aiWorkspacePhaseRecovery => 'Recovery';

  @override
  String get aiWorkspaceLoadPrevious => 'Load Previous Result';

  @override
  String get aiWorkspaceAnalyzeAgain => 'Analyze Again';

  @override
  String aiResultsAnalyzedSummary(
    int analyzed,
    String bytes,
    int safe,
    int review,
    int keep,
  ) {
    return '$analyzed analyzed · $bytes total · $safe safe · $review pending review · $keep kept';
  }

  @override
  String aiResultsDecisionSummary(String bytes, int review) {
    return '$bytes reclaimable · $review need review';
  }

  @override
  String get aiResultsLocalPreviewHint =>
      'Safe and keep counts below include local rules from the latest scan, not only finished AI coverage.';

  @override
  String get aiResultsMetricAnalyzed => 'Analyzed';

  @override
  String get aiResultsMetricSafe => 'Safe to remove';

  @override
  String get aiResultsMetricReview => 'Needs review';

  @override
  String get aiResultsMetricKept => 'Kept';

  @override
  String aiResultsTotalSize(String bytes) {
    return '$bytes total';
  }

  @override
  String get aiResultsNeedsDecision => 'Needs decision';

  @override
  String get aiResultsSearchHint => 'Search path, reason, source, or hint';

  @override
  String get aiResultsClearSearch => 'Clear search';

  @override
  String get aiResultsNoMatches => 'No matching results';

  @override
  String get aiResultsEmpty => 'No cleanup suggestions were found';

  @override
  String get aiResultsResetFilters => 'Reset search and filters';

  @override
  String get aiResultsFilterAll => 'All';

  @override
  String get aiResultsFilterReview => 'Review';

  @override
  String get aiResultsFilterSelected => 'Selected';

  @override
  String get aiResultsSortPriority => 'Priority';

  @override
  String get aiResultsSortSize => 'Size';

  @override
  String aiResultsGroupItems(int count, String bytes) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0 · $bytes';
  }

  @override
  String aiResultsGroupSafe(int count) {
    return 'Safe $count';
  }

  @override
  String aiResultsGroupReview(int count) {
    return 'Review $count';
  }

  @override
  String aiResultsGroupKeep(int count) {
    return 'Keep $count';
  }

  @override
  String aiResultsShowMoreInGroup(int count) {
    return 'Show $count more in this folder';
  }

  @override
  String aiResultsSelectedForCleanup(int count, String bytes) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items selected',
      one: '1 item selected',
    );
    return '$_temp0 · $bytes';
  }

  @override
  String aiResultsPendingReviewExcluded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pending review items are excluded until you decide.',
      one: '1 pending review item is excluded until you decide.',
    );
    return '$_temp0';
  }

  @override
  String get aiResultsMetricProtected => 'Protected';

  @override
  String get aiResultsNeedsYourDecision => 'Needs your decision';

  @override
  String get aiResultsAddToCleanup => 'Add to cleanup';

  @override
  String get aiResultsKeepItem => 'Keep this item';

  @override
  String get aiResultsAddedToCleanup => 'Added to cleanup';

  @override
  String get aiResultsKeptOutOfCleanup => 'Kept out of cleanup';

  @override
  String aiResultsSelectedInGroup(int count) {
    return 'Selected $count';
  }

  @override
  String get aiResultsClearGroupSelection => 'Clear group selection';

  @override
  String get aiResultsDetailSize => 'Size';

  @override
  String get aiResultsDetailConfidence => 'Confidence';

  @override
  String get aiResultsDetailReason => 'Reason';

  @override
  String get aiResultsDetailCleanupSource => 'Cleanup source';

  @override
  String get aiResultsDetailRetentionHint => 'Retention hint';

  @override
  String aiWorkspacePartialDelete(int count, String size) {
    return '$count items could not be removed · $size freed';
  }

  @override
  String get aiErrorTimeout => 'The AI request timed out. Try again.';

  @override
  String get aiErrorRateLimited => 'The AI service is busy. Try again shortly.';

  @override
  String get aiErrorNetwork =>
      'Could not reach the AI service. Check your connection.';

  @override
  String get aiWorkspaceReturn => 'Return to Overview';

  @override
  String get back => 'Back';

  @override
  String get homeBrowseFiles => 'Browse Files';

  @override
  String get homeStartScan => 'Start Scan';

  @override
  String get homeRescan => 'Rescan';

  @override
  String get homeCancelScan => 'Cancel Scan';
}
