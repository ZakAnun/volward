import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Volward'**
  String get appTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAppearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceSection;

  /// No description provided for @settingsThemeTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsThemeTitle;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsAccentColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get settingsAccentColorTitle;

  /// No description provided for @settingsAccentColorDescription.
  ///
  /// In en, this message translates to:
  /// **'Applies to buttons, selections, and progress indicators.'**
  String get settingsAccentColorDescription;

  /// No description provided for @settingsAccentPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get settingsAccentPreview;

  /// No description provided for @settingsAccentPrimary.
  ///
  /// In en, this message translates to:
  /// **'Primary'**
  String get settingsAccentPrimary;

  /// No description provided for @settingsLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageTitle;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get settingsLanguageChinese;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsScanResultsSection.
  ///
  /// In en, this message translates to:
  /// **'Scan & results'**
  String get settingsScanResultsSection;

  /// No description provided for @settingsDeletableOnlyTitle.
  ///
  /// In en, this message translates to:
  /// **'Deletable only'**
  String get settingsDeletableOnlyTitle;

  /// No description provided for @settingsDeletableOnlyDescription.
  ///
  /// In en, this message translates to:
  /// **'Only show entries Volward marks as low-risk cleanup candidates, currently cache and temp files.'**
  String get settingsDeletableOnlyDescription;

  /// No description provided for @settingsIncrementalScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Incremental scan'**
  String get settingsIncrementalScanTitle;

  /// No description provided for @settingsIncrementalScanDescription.
  ///
  /// In en, this message translates to:
  /// **'Reuse unchanged subdirectories from the previous scan of the same folder to speed up later scans.'**
  String get settingsIncrementalScanDescription;

  /// No description provided for @settingsIncrementalScanUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The bundled Rust library does not support this scan mode yet. Rebuild Rust before using it.'**
  String get settingsIncrementalScanUnsupported;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterCategoryCache.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get filterCategoryCache;

  /// No description provided for @filterCategoryTemp.
  ///
  /// In en, this message translates to:
  /// **'Temp'**
  String get filterCategoryTemp;

  /// No description provided for @filterCategoryMedia.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get filterCategoryMedia;

  /// No description provided for @filterCategorySystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get filterCategorySystem;

  /// No description provided for @homeCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get homeCategoryOther;

  /// No description provided for @sortSizeDesc.
  ///
  /// In en, this message translates to:
  /// **'Size ↓'**
  String get sortSizeDesc;

  /// No description provided for @sortSizeAsc.
  ///
  /// In en, this message translates to:
  /// **'Size ↑'**
  String get sortSizeAsc;

  /// No description provided for @sortNameAsc.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sortNameAsc;

  /// No description provided for @scanColumnPreparingFolder.
  ///
  /// In en, this message translates to:
  /// **'Preparing folder…'**
  String get scanColumnPreparingFolder;

  /// No description provided for @scanColumnNoFilterMatches.
  ///
  /// In en, this message translates to:
  /// **'No items match the current filters.'**
  String get scanColumnNoFilterMatches;

  /// No description provided for @navSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Storage steward'**
  String get navSubtitle;

  /// No description provided for @settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// No description provided for @scanActionFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder…'**
  String get scanActionFolder;

  /// No description provided for @scanActionHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get scanActionHome;

  /// No description provided for @scanActionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get scanActionCancel;

  /// No description provided for @scanActionStart.
  ///
  /// In en, this message translates to:
  /// **'Start scan'**
  String get scanActionStart;

  /// No description provided for @scanActionRescan.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get scanActionRescan;

  /// No description provided for @trashActionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash'**
  String get trashActionEmpty;

  /// No description provided for @trashEmptyConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash?'**
  String get trashEmptyConfirmTitle;

  /// No description provided for @trashEmptyConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete everything in Trash? This cannot be undone.'**
  String get trashEmptyConfirmMessage;

  /// No description provided for @trashEmptySuccess.
  ///
  /// In en, this message translates to:
  /// **'Trash emptied. Results refreshed.'**
  String get trashEmptySuccess;

  /// No description provided for @trashEmptyFailed.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash failed: {error}'**
  String trashEmptyFailed(Object error);

  /// No description provided for @deleteActionMoveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get deleteActionMoveToTrash;

  /// No description provided for @deleteActionWorking.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get deleteActionWorking;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash?'**
  String get deleteConfirmTitle;

  /// No description provided for @deleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Move {count} item(s) to Trash and free about {bytes}?\n\nYou can restore them from Trash if needed.'**
  String deleteConfirmMessage(int count, Object bytes);

  /// No description provided for @deleteActionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteActionDelete;

  /// No description provided for @deleteSuccessWithFailures.
  ///
  /// In en, this message translates to:
  /// **'Deleted with {failedCount} failure(s). Freed {bytes}.'**
  String deleteSuccessWithFailures(int failedCount, Object bytes);

  /// No description provided for @deleteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Moved to Trash. Freed {bytes}. Rescan complete.'**
  String deleteSuccess(Object bytes);

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String deleteFailed(Object error);

  /// No description provided for @permissionNativeOutdatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Native library outdated'**
  String get permissionNativeOutdatedTitle;

  /// No description provided for @permissionNativeOutdatedDescription.
  ///
  /// In en, this message translates to:
  /// **'Rebuild the native Rust library for this platform and fully restart the app.'**
  String get permissionNativeOutdatedDescription;

  /// No description provided for @permissionDeepScanReady.
  ///
  /// In en, this message translates to:
  /// **'Deep scan is available.'**
  String get permissionDeepScanReady;

  /// No description provided for @permissionFullDiskRecommended.
  ///
  /// In en, this message translates to:
  /// **'Full Disk Access recommended for ~/Library cache scan.'**
  String get permissionFullDiskRecommended;

  /// No description provided for @permissionFullDiskRecommendedTitle.
  ///
  /// In en, this message translates to:
  /// **'Full Disk Access recommended'**
  String get permissionFullDiskRecommendedTitle;

  /// No description provided for @permissionFullDiskInstructions.
  ///
  /// In en, this message translates to:
  /// **'System Settings → Privacy & Security → Full Disk Access → enable Volward. Debug builds: tap +, Cmd+Shift+G, select volward.app.'**
  String get permissionFullDiskInstructions;

  /// No description provided for @permissionOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get permissionOpenSettings;

  /// No description provided for @permissionShowDetails.
  ///
  /// In en, this message translates to:
  /// **'Show details'**
  String get permissionShowDetails;

  /// No description provided for @permissionHideDetails.
  ///
  /// In en, this message translates to:
  /// **'Hide details'**
  String get permissionHideDetails;

  /// No description provided for @permissionCopyAppPath.
  ///
  /// In en, this message translates to:
  /// **'Copy .app path'**
  String get permissionCopyAppPath;

  /// No description provided for @permissionCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get permissionCheckAgain;

  /// No description provided for @permissionCopiedPath.
  ///
  /// In en, this message translates to:
  /// **'Copied: {path}'**
  String permissionCopiedPath(Object path);

  /// No description provided for @permissionAppPath.
  ///
  /// In en, this message translates to:
  /// **'App path: {path}'**
  String permissionAppPath(Object path);

  /// No description provided for @permissionUnknownPath.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get permissionUnknownPath;

  /// No description provided for @folderPickerConfirm.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get folderPickerConfirm;

  /// No description provided for @scanTargetTitle.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get scanTargetTitle;

  /// No description provided for @scanTargetHomeDefault.
  ///
  /// In en, this message translates to:
  /// **'Home (default)'**
  String get scanTargetHomeDefault;

  /// No description provided for @scanTargetHomeShort.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get scanTargetHomeShort;

  /// No description provided for @scanTargetCustomShort.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get scanTargetCustomShort;

  /// No description provided for @scanHomeLongRunningHint.
  ///
  /// In en, this message translates to:
  /// **'Full Home scan can take many minutes on large accounts — watch the item count above.'**
  String get scanHomeLongRunningHint;

  /// No description provided for @resultsClassifiedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} classified'**
  String resultsClassifiedCount(int count);

  /// No description provided for @resultsReclaimableBytes.
  ///
  /// In en, this message translates to:
  /// **'{bytes} reclaimable'**
  String resultsReclaimableBytes(Object bytes);

  /// No description provided for @resultsTreeSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} in tree · {bytes}'**
  String resultsTreeSummary(int count, Object bytes);

  /// No description provided for @resultsUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating results…'**
  String get resultsUpdating;

  /// No description provided for @resultsNoFilterMatches.
  ///
  /// In en, this message translates to:
  /// **'No items match the current filters.'**
  String get resultsNoFilterMatches;

  /// No description provided for @resultsNoFilterMatchesWithCount.
  ///
  /// In en, this message translates to:
  /// **'No items match the current filters ({count} in list).'**
  String resultsNoFilterMatchesWithCount(int count);

  /// No description provided for @resultsNoFilesUnder.
  ///
  /// In en, this message translates to:
  /// **'Scan returned no files under {path}.'**
  String resultsNoFilesUnder(Object path);

  /// No description provided for @resultsRestoringPreviousScan.
  ///
  /// In en, this message translates to:
  /// **'Restoring previous scan…'**
  String get resultsRestoringPreviousScan;

  /// No description provided for @previewSelectPrompt.
  ///
  /// In en, this message translates to:
  /// **'Select a folder or file'**
  String get previewSelectPrompt;

  /// No description provided for @previewFolderCategory.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get previewFolderCategory;

  /// No description provided for @previewItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String previewItemCount(int count);

  /// No description provided for @scanStatusScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get scanStatusScanning;

  /// No description provided for @scanPhaseDiscoveringRoots.
  ///
  /// In en, this message translates to:
  /// **'Discovering roots…'**
  String get scanPhaseDiscoveringRoots;

  /// No description provided for @scanPhaseWalking.
  ///
  /// In en, this message translates to:
  /// **'Scanning files…'**
  String get scanPhaseWalking;

  /// No description provided for @scanPhaseClassifying.
  ///
  /// In en, this message translates to:
  /// **'Classifying entries…'**
  String get scanPhaseClassifying;

  /// No description provided for @scanPhaseAggregating.
  ///
  /// In en, this message translates to:
  /// **'Aggregating results…'**
  String get scanPhaseAggregating;

  /// No description provided for @scanPhaseSavingResults.
  ///
  /// In en, this message translates to:
  /// **'Saving results…'**
  String get scanPhaseSavingResults;

  /// No description provided for @scanPhaseLoadingResults.
  ///
  /// In en, this message translates to:
  /// **'Loading results…'**
  String get scanPhaseLoadingResults;

  /// No description provided for @scanPhaseDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get scanPhaseDone;

  /// No description provided for @scanProgressItems.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String scanProgressItems(int count);

  /// No description provided for @scanStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Scan cancelled'**
  String get scanStatusCancelled;

  /// No description provided for @scanStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Scan failed: {error}'**
  String scanStatusFailed(Object error);

  /// No description provided for @scanStatusFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get scanStatusFull;

  /// No description provided for @scanStatusIncremental.
  ///
  /// In en, this message translates to:
  /// **'Incremental'**
  String get scanStatusIncremental;

  /// No description provided for @scanStatusFiles.
  ///
  /// In en, this message translates to:
  /// **'{mode} scan: {count} files'**
  String scanStatusFiles(Object mode, int count);

  /// No description provided for @stickySelected.
  ///
  /// In en, this message translates to:
  /// **'Selected: {count} · {bytes}'**
  String stickySelected(int count, Object bytes);

  /// No description provided for @stickyDirectoriesLoading.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 directory loading…} other{{count} directories loading…}}'**
  String stickyDirectoriesLoading(int count);

  /// No description provided for @stickyBrowseResults.
  ///
  /// In en, this message translates to:
  /// **'Select items to move to Trash'**
  String get stickyBrowseResults;

  /// No description provided for @stickyReadyToScan.
  ///
  /// In en, this message translates to:
  /// **'Ready to scan'**
  String get stickyReadyToScan;

  /// No description provided for @stickyLoadingEngine.
  ///
  /// In en, this message translates to:
  /// **'Loading engine…'**
  String get stickyLoadingEngine;

  /// No description provided for @settingsAboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAboutSection;

  /// No description provided for @settingsCurrentVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsCurrentVersion(Object version);

  /// No description provided for @settingsCheckForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsCheckForUpdates;

  /// No description provided for @settingsCheckingForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get settingsCheckingForUpdates;

  /// No description provided for @settingsUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You\'re up to date.'**
  String get settingsUpToDate;

  /// No description provided for @settingsUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available: {version}'**
  String settingsUpdateAvailable(Object version);

  /// No description provided for @settingsUpdateNow.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get settingsUpdateNow;

  /// No description provided for @settingsDownloadingUpdate.
  ///
  /// In en, this message translates to:
  /// **'Downloading update… {percent}%'**
  String settingsDownloadingUpdate(int percent);

  /// No description provided for @settingsInstallingUpdate.
  ///
  /// In en, this message translates to:
  /// **'Installing update…'**
  String get settingsInstallingUpdate;

  /// No description provided for @settingsUpdateError.
  ///
  /// In en, this message translates to:
  /// **'Update check failed: {error}'**
  String settingsUpdateError(Object error);

  /// No description provided for @settingsUpdateActionError.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {error}'**
  String settingsUpdateActionError(Object error);

  /// No description provided for @settingsAutoDownloadUpdatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Download updates in background'**
  String get settingsAutoDownloadUpdatesTitle;

  /// No description provided for @settingsAutoDownloadUpdatesDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatically download updates so they\'re ready to install.'**
  String get settingsAutoDownloadUpdatesDescription;

  /// No description provided for @settingsOpenDownloadPage.
  ///
  /// In en, this message translates to:
  /// **'Open download page'**
  String get settingsOpenDownloadPage;

  /// No description provided for @settingsUpdateReady.
  ///
  /// In en, this message translates to:
  /// **'A new version is downloaded and ready.'**
  String get settingsUpdateReady;

  /// No description provided for @updateReadyAction.
  ///
  /// In en, this message translates to:
  /// **'Complete update'**
  String get updateReadyAction;

  /// No description provided for @updateReadyDismissTooltip.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get updateReadyDismissTooltip;

  /// No description provided for @homeOverviewLive.
  ///
  /// In en, this message translates to:
  /// **'Live disk data'**
  String get homeOverviewLive;

  /// No description provided for @homeOverviewCached.
  ///
  /// In en, this message translates to:
  /// **'Cached disk data'**
  String get homeOverviewCached;

  /// No description provided for @homeOverviewLoading.
  ///
  /// In en, this message translates to:
  /// **'Reading disk…'**
  String get homeOverviewLoading;

  /// No description provided for @homeOverviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Disk capacity unavailable'**
  String get homeOverviewUnavailable;

  /// No description provided for @homeCapacityUsed.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get homeCapacityUsed;

  /// No description provided for @homeCapacityTotal.
  ///
  /// In en, this message translates to:
  /// **'Total capacity'**
  String get homeCapacityTotal;

  /// No description provided for @homeCapacityAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get homeCapacityAvailable;

  /// No description provided for @homeCapacitySemantics.
  ///
  /// In en, this message translates to:
  /// **'{used} used of {total}, {available} available'**
  String homeCapacitySemantics(String used, String total, String available);

  /// No description provided for @homeScanTargets.
  ///
  /// In en, this message translates to:
  /// **'Scan range'**
  String get homeScanTargets;

  /// No description provided for @homeLocationHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeLocationHome;

  /// No description provided for @homeLocationApplications.
  ///
  /// In en, this message translates to:
  /// **'Applications'**
  String get homeLocationApplications;

  /// No description provided for @homeLocationDesktop.
  ///
  /// In en, this message translates to:
  /// **'Desktop'**
  String get homeLocationDesktop;

  /// No description provided for @homeLocationDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get homeLocationDownloads;

  /// No description provided for @homeLocationDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get homeLocationDocuments;

  /// No description provided for @homeLocationVolume.
  ///
  /// In en, this message translates to:
  /// **'Disk {name}'**
  String homeLocationVolume(String name);

  /// No description provided for @homeLocationCustom.
  ///
  /// In en, this message translates to:
  /// **'{name}'**
  String homeLocationCustom(String name);

  /// No description provided for @homeChooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose Folder'**
  String get homeChooseFolder;

  /// No description provided for @homeCurrentTarget.
  ///
  /// In en, this message translates to:
  /// **'Current target'**
  String get homeCurrentTarget;

  /// No description provided for @homeRecentFolders.
  ///
  /// In en, this message translates to:
  /// **'Recent Folders'**
  String get homeRecentFolders;

  /// No description provided for @homeLastScan.
  ///
  /// In en, this message translates to:
  /// **'Last scan {time}'**
  String homeLastScan(String time);

  /// No description provided for @homeNeverScanned.
  ///
  /// In en, this message translates to:
  /// **'Not scanned yet'**
  String get homeNeverScanned;

  /// No description provided for @homeReclaimable.
  ///
  /// In en, this message translates to:
  /// **'{size} reclaimable'**
  String homeReclaimable(String size);

  /// No description provided for @homeScannedSize.
  ///
  /// In en, this message translates to:
  /// **'{size} scanned'**
  String homeScannedSize(String size);

  /// No description provided for @homeLargestItems.
  ///
  /// In en, this message translates to:
  /// **'Largest items'**
  String get homeLargestItems;

  /// No description provided for @homeLargestItemsTotal.
  ///
  /// In en, this message translates to:
  /// **'{size} total'**
  String homeLargestItemsTotal(String size);

  /// No description provided for @homeLargestItemsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Shown after scanning'**
  String get homeLargestItemsEmpty;

  /// No description provided for @homeFolderEmpty.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get homeFolderEmpty;

  /// No description provided for @homeLargestItemsSemantics.
  ///
  /// In en, this message translates to:
  /// **'{name}, {size}, {rank} of {count}'**
  String homeLargestItemsSemantics(
    String name,
    String size,
    int rank,
    int count,
  );

  /// No description provided for @aiAnalysisTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Disk Analysis'**
  String get aiAnalysisTitle;

  /// No description provided for @aiPreCheckSafeTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} items pre-identified as safe to remove'**
  String aiPreCheckSafeTitle(int count);

  /// No description provided for @aiPreCheckSafeSelectable.
  ///
  /// In en, this message translates to:
  /// **'{count} items already marked safe by local rules'**
  String aiPreCheckSafeSelectable(int count);

  /// No description provided for @aiPreCheckUnknownTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} items will be sent for AI analysis (~{tokens} tokens)'**
  String aiPreCheckUnknownTitle(int count, int tokens);

  /// No description provided for @aiStartAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Start AI Analysis'**
  String get aiStartAnalysis;

  /// No description provided for @aiNoApiKey.
  ///
  /// In en, this message translates to:
  /// **'No API Key — configure in Settings'**
  String get aiNoApiKey;

  /// No description provided for @aiContractUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The installed native library is out of date. Please update Volward to use AI analysis.'**
  String get aiContractUnavailable;

  /// No description provided for @aiDeleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} Selected Items'**
  String aiDeleteSelected(int count);

  /// No description provided for @aiVerdictSafe.
  ///
  /// In en, this message translates to:
  /// **'Safe to Remove ({count})'**
  String aiVerdictSafe(int count);

  /// No description provided for @aiVerdictReview.
  ///
  /// In en, this message translates to:
  /// **'Review Needed ({count})'**
  String aiVerdictReview(int count);

  /// No description provided for @aiVerdictKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep ({count})'**
  String aiVerdictKeep(int count);

  /// No description provided for @aiSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Analysis'**
  String get aiSettingsTitle;

  /// No description provided for @aiSettingsModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get aiSettingsModeLabel;

  /// No description provided for @aiSettingsByokLabel.
  ///
  /// In en, this message translates to:
  /// **'Bring Your Own Key (DeepSeek)'**
  String get aiSettingsByokLabel;

  /// No description provided for @aiSettingsOffLabel.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get aiSettingsOffLabel;

  /// No description provided for @aiSettingsPlatformLabel.
  ///
  /// In en, this message translates to:
  /// **'Volward Platform'**
  String get aiSettingsPlatformLabel;

  /// No description provided for @aiSettingsApiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'sk-...'**
  String get aiSettingsApiKeyHint;

  /// No description provided for @aiSettingsApiKeySaved.
  ///
  /// In en, this message translates to:
  /// **'API key saved'**
  String get aiSettingsApiKeySaved;

  /// No description provided for @aiSettingsApiKeyCleared.
  ///
  /// In en, this message translates to:
  /// **'API key cleared'**
  String get aiSettingsApiKeyCleared;

  /// No description provided for @aiSettingsSaveKey.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get aiSettingsSaveKey;

  /// No description provided for @aiSettingsClearKey.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get aiSettingsClearKey;

  /// No description provided for @aiSettingsLinkEmail.
  ///
  /// In en, this message translates to:
  /// **'Link email'**
  String get aiSettingsLinkEmail;

  /// No description provided for @aiSettingsEnterEmail.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get aiSettingsEnterEmail;

  /// No description provided for @aiSettingsEnterOtp.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get aiSettingsEnterOtp;

  /// No description provided for @aiSettingsSendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get aiSettingsSendOtp;

  /// No description provided for @aiSettingsVerifyOtp.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get aiSettingsVerifyOtp;

  /// No description provided for @aiSettingsLinkedAs.
  ///
  /// In en, this message translates to:
  /// **'Linked as {email}'**
  String aiSettingsLinkedAs(String email);

  /// No description provided for @aiSettingsCreditsRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count} credits remaining'**
  String aiSettingsCreditsRemaining(int count);

  /// No description provided for @aiSettingsBuyCredits.
  ///
  /// In en, this message translates to:
  /// **'Buy credits'**
  String get aiSettingsBuyCredits;

  /// No description provided for @aiPurchasePayHint.
  ///
  /// In en, this message translates to:
  /// **'Pay with WeChat on the checkout page. Balance updates after payment.'**
  String get aiPurchasePayHint;

  /// No description provided for @aiPurchaseWaitingHint.
  ///
  /// In en, this message translates to:
  /// **'Payment may still be processing. Wait a moment, then refresh your credits in Settings.'**
  String get aiPurchaseWaitingHint;

  /// No description provided for @aiSettingsSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Login expired — please link your email again.'**
  String get aiSettingsSessionExpired;

  /// No description provided for @aiPrecheckCreditsCost.
  ///
  /// In en, this message translates to:
  /// **'Estimated cost: 1 credit (balance {balance})'**
  String aiPrecheckCreditsCost(int balance);

  /// No description provided for @aiInsufficientCredits.
  ///
  /// In en, this message translates to:
  /// **'No credits left — buy more in Settings.'**
  String get aiInsufficientCredits;

  /// No description provided for @aiAnalysisFab.
  ///
  /// In en, this message translates to:
  /// **'AI Analysis'**
  String get aiAnalysisFab;

  /// No description provided for @aiPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'AI analysis privacy'**
  String get aiPrivacyTitle;

  /// No description provided for @aiPrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'Only paths, sizes, and file counts are sent. File contents are never uploaded. BYOK sends data to DeepSeek; Platform mode sends data to Volward servers which forward to DeepSeek.'**
  String get aiPrivacyBody;

  /// No description provided for @aiPrivacyAccept.
  ///
  /// In en, this message translates to:
  /// **'I understand'**
  String get aiPrivacyAccept;

  /// No description provided for @aiOverwriteTitle.
  ///
  /// In en, this message translates to:
  /// **'Previous analysis available'**
  String get aiOverwriteTitle;

  /// No description provided for @aiOverwriteBody.
  ///
  /// In en, this message translates to:
  /// **'This scan already has an AI result. Load it, or re-analyze to overwrite.'**
  String get aiOverwriteBody;

  /// No description provided for @aiActionContinue.
  ///
  /// In en, this message translates to:
  /// **'Re-analyze'**
  String get aiActionContinue;

  /// No description provided for @aiActionLoadPrevious.
  ///
  /// In en, this message translates to:
  /// **'Load previous'**
  String get aiActionLoadPrevious;

  /// No description provided for @aiLoadPreviousFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the previous AI result.'**
  String get aiLoadPreviousFailed;

  /// No description provided for @aiAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing with AI…'**
  String get aiAnalyzing;

  /// No description provided for @aiActionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get aiActionRetry;

  /// No description provided for @aiErrorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get aiErrorUnknown;

  /// No description provided for @aiErrorNativeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Failed to load AI candidates (native API unavailable).'**
  String get aiErrorNativeUnavailable;

  /// No description provided for @aiErrorInvalidPayload.
  ///
  /// In en, this message translates to:
  /// **'Invalid candidates payload.'**
  String get aiErrorInvalidPayload;

  /// No description provided for @aiTruncatedNotice.
  ///
  /// In en, this message translates to:
  /// **'Showing the {shown} largest of {total} items — the rest were skipped to keep the request small.'**
  String aiTruncatedNotice(int shown, int total);

  /// No description provided for @aiCleanupSourceAiToolCache.
  ///
  /// In en, this message translates to:
  /// **'AI tool cache/temp'**
  String get aiCleanupSourceAiToolCache;

  /// No description provided for @aiCleanupSourceAiGeneratedOutput.
  ///
  /// In en, this message translates to:
  /// **'AI-generated output'**
  String get aiCleanupSourceAiGeneratedOutput;

  /// No description provided for @aiCleanupSourceSystemTemp.
  ///
  /// In en, this message translates to:
  /// **'Temporary file'**
  String get aiCleanupSourceSystemTemp;

  /// No description provided for @aiCleanupRetentionDays.
  ///
  /// In en, this message translates to:
  /// **'Review after {days} days'**
  String aiCleanupRetentionDays(int days);

  /// No description provided for @aiWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Cleanup Suggestions'**
  String get aiWorkspaceTitle;

  /// No description provided for @aiWorkspaceBack.
  ///
  /// In en, this message translates to:
  /// **'Back to Overview'**
  String get aiWorkspaceBack;

  /// No description provided for @aiWorkspacePhaseLoading.
  ///
  /// In en, this message translates to:
  /// **'Preparing candidates'**
  String get aiWorkspacePhaseLoading;

  /// No description provided for @aiWorkspacePhasePrecheck.
  ///
  /// In en, this message translates to:
  /// **'Pre-check'**
  String get aiWorkspacePhasePrecheck;

  /// No description provided for @aiWorkspacePhasePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get aiWorkspacePhasePrivacy;

  /// No description provided for @aiWorkspacePhaseAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing'**
  String get aiWorkspacePhaseAnalyzing;

  /// No description provided for @aiWorkspacePhaseReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get aiWorkspacePhaseReview;

  /// No description provided for @aiWorkspacePhaseDeleting.
  ///
  /// In en, this message translates to:
  /// **'Deleting'**
  String get aiWorkspacePhaseDeleting;

  /// No description provided for @aiWorkspacePhaseRecovery.
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get aiWorkspacePhaseRecovery;

  /// No description provided for @aiWorkspaceLoadPrevious.
  ///
  /// In en, this message translates to:
  /// **'Load Previous Result'**
  String get aiWorkspaceLoadPrevious;

  /// No description provided for @aiWorkspaceAnalyzeAgain.
  ///
  /// In en, this message translates to:
  /// **'Analyze Again'**
  String get aiWorkspaceAnalyzeAgain;

  /// No description provided for @aiWorkspaceSelectedSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} selected · {size}'**
  String aiWorkspaceSelectedSummary(int count, String size);

  /// No description provided for @aiWorkspacePartialDelete.
  ///
  /// In en, this message translates to:
  /// **'{count} items could not be removed · {size} freed'**
  String aiWorkspacePartialDelete(int count, String size);

  /// No description provided for @aiErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'The AI request timed out. Try again.'**
  String get aiErrorTimeout;

  /// No description provided for @aiErrorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'The AI service is busy. Try again shortly.'**
  String get aiErrorRateLimited;

  /// No description provided for @aiErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the AI service. Check your connection.'**
  String get aiErrorNetwork;

  /// No description provided for @aiWorkspaceReturn.
  ///
  /// In en, this message translates to:
  /// **'Return to Overview'**
  String get aiWorkspaceReturn;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @homeBrowseFiles.
  ///
  /// In en, this message translates to:
  /// **'Browse Files'**
  String get homeBrowseFiles;

  /// No description provided for @homeStartScan.
  ///
  /// In en, this message translates to:
  /// **'Start Scan'**
  String get homeStartScan;

  /// No description provided for @homeRescan.
  ///
  /// In en, this message translates to:
  /// **'Rescan'**
  String get homeRescan;

  /// No description provided for @homeCancelScan.
  ///
  /// In en, this message translates to:
  /// **'Cancel Scan'**
  String get homeCancelScan;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
