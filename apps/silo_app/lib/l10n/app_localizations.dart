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
/// import 'l10n/app_localizations.dart';
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
  /// **'Silo'**
  String get appTitle;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Download once, link everywhere.'**
  String get tagline;

  /// No description provided for @searchLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get searchLabel;

  /// No description provided for @searchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'a keyword, author/repo, or a hub URL'**
  String get searchPlaceholder;

  /// No description provided for @searchAction.
  ///
  /// In en, this message translates to:
  /// **'Look up'**
  String get searchAction;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Looking up sources…'**
  String get searching;

  /// No description provided for @availableFrom.
  ///
  /// In en, this message translates to:
  /// **'Available from {sources}'**
  String availableFrom(String sources);

  /// No description provided for @variantsTitle.
  ///
  /// In en, this message translates to:
  /// **'Variants'**
  String get variantsTitle;

  /// No description provided for @variantShards.
  ///
  /// In en, this message translates to:
  /// **'{count} shards'**
  String variantShards(int count);

  /// No description provided for @variantProjector.
  ///
  /// In en, this message translates to:
  /// **'+{count} mmproj'**
  String variantProjector(int count);

  /// No description provided for @variantSupportFiles.
  ///
  /// In en, this message translates to:
  /// **'+{count} support files'**
  String variantSupportFiles(int count);

  /// No description provided for @pauseAction.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pauseAction;

  /// No description provided for @resumeAction.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeAction;

  /// No description provided for @cancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelAction;

  /// No description provided for @linkAction.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get linkAction;

  /// No description provided for @removeAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeAction;

  /// No description provided for @reclaimAction.
  ///
  /// In en, this message translates to:
  /// **'Reclaim space'**
  String get reclaimAction;

  /// No description provided for @refreshAction.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshAction;

  /// No description provided for @revealAction.
  ///
  /// In en, this message translates to:
  /// **'Show in Finder'**
  String get revealAction;

  /// No description provided for @downloadFile.
  ///
  /// In en, this message translates to:
  /// **'{name} ({index} of {count})'**
  String downloadFile(String name, int index, int count);

  /// No description provided for @downloadStats.
  ///
  /// In en, this message translates to:
  /// **'{received} of {total} · {rate} · {eta} left'**
  String downloadStats(String received, String total, String rate, String eta);

  /// No description provided for @downloadConnections.
  ///
  /// In en, this message translates to:
  /// **'{active} connections · {done}/{total} chunks'**
  String downloadConnections(int active, int done, int total);

  /// No description provided for @statusResolving.
  ///
  /// In en, this message translates to:
  /// **'Resolving sources…'**
  String get statusResolving;

  /// No description provided for @statusVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying checksum…'**
  String get statusVerifying;

  /// No description provided for @statusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused — resume to continue where it stopped'**
  String get statusPaused;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @statusDone.
  ///
  /// In en, this message translates to:
  /// **'Added {name}'**
  String statusDone(String name);

  /// No description provided for @unknownValue.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get unknownValue;

  /// No description provided for @libraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryTitle;

  /// No description provided for @libraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing stored yet. Look up a model to get started.'**
  String get libraryEmpty;

  /// No description provided for @librarySummary.
  ///
  /// In en, this message translates to:
  /// **'{models} models · {size} on disk'**
  String librarySummary(int models, String size);

  /// No description provided for @librarySaved.
  ///
  /// In en, this message translates to:
  /// **'Deduplication saved {size}'**
  String librarySaved(String size);

  /// No description provided for @entryLinkedTo.
  ///
  /// In en, this message translates to:
  /// **'Linked into {targets}'**
  String entryLinkedTo(String targets);

  /// No description provided for @entryNotLinked.
  ///
  /// In en, this message translates to:
  /// **'Not linked yet'**
  String get entryNotLinked;

  /// No description provided for @entrySource.
  ///
  /// In en, this message translates to:
  /// **'{source} · {revision}'**
  String entrySource(String source, String revision);

  /// No description provided for @targetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Link into'**
  String get targetsTitle;

  /// No description provided for @targetNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'not installed'**
  String get targetNotInstalled;

  /// No description provided for @linkedResult.
  ///
  /// In en, this message translates to:
  /// **'{visible} visible, {cost} extra on disk'**
  String linkedResult(String visible, String cost);

  /// No description provided for @reclaimedSpace.
  ///
  /// In en, this message translates to:
  /// **'Freed {size} across {count} blobs'**
  String reclaimedSpace(String size, int count);

  /// No description provided for @reclaimNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to reclaim'**
  String get reclaimNothing;

  /// No description provided for @sourceSpeed.
  ///
  /// In en, this message translates to:
  /// **'{source}: {rate}'**
  String sourceSpeed(String source, String rate);

  /// No description provided for @sourceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'{source}: unavailable'**
  String sourceUnavailable(String source);

  /// No description provided for @queueTitle.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queueTitle;

  /// No description provided for @queueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing queued.'**
  String get queueEmpty;

  /// No description provided for @queueAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get queueAddAction;

  /// No description provided for @queueSummary.
  ///
  /// In en, this message translates to:
  /// **'{pending} waiting'**
  String queueSummary(int pending);

  /// No description provided for @queuePauseAllAction.
  ///
  /// In en, this message translates to:
  /// **'Hold queue'**
  String get queuePauseAllAction;

  /// No description provided for @queueResumeAllAction.
  ///
  /// In en, this message translates to:
  /// **'Start queue'**
  String get queueResumeAllAction;

  /// No description provided for @queueClearAction.
  ///
  /// In en, this message translates to:
  /// **'Clear finished'**
  String get queueClearAction;

  /// No description provided for @queueHeldNotice.
  ///
  /// In en, this message translates to:
  /// **'Queue is held — nothing will start until you resume it.'**
  String get queueHeldNotice;

  /// No description provided for @queueRestoredNotice.
  ///
  /// In en, this message translates to:
  /// **'{count} jobs restored from the last session, paused.'**
  String queueRestoredNotice(int count);

  /// No description provided for @jobStatusQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get jobStatusQueued;

  /// No description provided for @jobStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get jobStatusRunning;

  /// No description provided for @jobStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get jobStatusPaused;

  /// No description provided for @jobStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get jobStatusCompleted;

  /// No description provided for @jobStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get jobStatusCancelled;

  /// No description provided for @jobStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get jobStatusFailed;

  /// No description provided for @moveUpAction.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get moveUpAction;

  /// No description provided for @moveDownAction.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get moveDownAction;

  /// No description provided for @removeFromQueueAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeFromQueueAction;

  /// No description provided for @libraryReclaimable.
  ///
  /// In en, this message translates to:
  /// **'{size} unreferenced — reclaim to free it'**
  String libraryReclaimable(String size);

  /// No description provided for @unlinkAction.
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get unlinkAction;

  /// No description provided for @gcResult.
  ///
  /// In en, this message translates to:
  /// **'Freed {freed} across {count} blobs'**
  String gcResult(String freed, int count);

  /// No description provided for @gcRetained.
  ///
  /// In en, this message translates to:
  /// **'{size} not reclaimed — still installed in a tool'**
  String gcRetained(String size);

  /// No description provided for @unlinkSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count} file(s) left alone — not what Silo put there'**
  String unlinkSkipped(int count);

  /// No description provided for @searchResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Search results'**
  String get searchResultsTitle;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'Nothing matched. Try a different keyword.'**
  String get searchNoResults;

  /// No description provided for @searchShowAll.
  ///
  /// In en, this message translates to:
  /// **'Include transformers-only repositories'**
  String get searchShowAll;

  /// No description provided for @resultDownloads.
  ///
  /// In en, this message translates to:
  /// **'{count} downloads'**
  String resultDownloads(String count);

  /// No description provided for @resultOnSources.
  ///
  /// In en, this message translates to:
  /// **'on {sources}'**
  String resultOnSources(String sources);
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
