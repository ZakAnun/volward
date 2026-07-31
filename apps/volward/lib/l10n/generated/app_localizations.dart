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
  /// **'Rebuild Rust (apps/volward/macos/build_rust.sh) and fully restart (R).'**
  String get permissionNativeOutdatedDescription;

  /// No description provided for @permissionDeepScanReady.
  ///
  /// In en, this message translates to:
  /// **'Full Disk Access enabled — deep scan on.'**
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
