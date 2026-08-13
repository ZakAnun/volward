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
  String get settingsUpdateLater => 'Later';

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
  String get settingsOpenDownloadPage => 'Open download page';

  @override
  String updateAvailableTitle(Object version) {
    return 'Update available — $version';
  }

  @override
  String updateAvailableMessage(Object notes) {
    return '$notes';
  }

  @override
  String get updateNotesUnavailable =>
      'A newer Volward release is ready to install.';

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
  String aiPreCheckUnknownTitle(int count, int tokens) {
    return '$count items will be sent for AI analysis (~$tokens tokens)';
  }

  @override
  String get aiStartAnalysis => 'Start AI Analysis';

  @override
  String get aiNoApiKey => 'No API Key — configure in Settings';

  @override
  String aiDeleteSelected(int count) {
    return 'Delete $count Selected Items';
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
  String get aiSettingsPlatformLabel => 'Volward Platform (coming soon)';

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
  String get aiAnalysisFab => 'AI Analysis';

  @override
  String get aiPrivacyTitle => 'AI analysis privacy';

  @override
  String get aiPrivacyBody =>
      'Only paths, sizes, and file counts are sent. File contents are never uploaded. In BYOK mode data goes directly to your AI provider.';

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
  String aiTruncatedNotice(int shown, int total) {
    return 'Showing the $shown largest of $total items — the rest were skipped to keep the request small.';
  }

  @override
  String get back => 'Back';
}
