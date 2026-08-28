import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L
/// returned by `L.of(context)`.
///
/// Applications need to include `L.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L.localizationsDelegates,
///   supportedLocales: L.supportedLocales,
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
/// be consistent with the languages listed in the L.supportedLocales
/// property.
abstract class L {
  L(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L of(BuildContext context) {
    return Localizations.of<L>(context, L)!;
  }

  static const LocalizationsDelegate<L> delegate = _LDelegate();

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
  static const List<Locale> supportedLocales = <Locale>[Locale('bn'), Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Bulletin'**
  String get appTitle;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Your institution\'s bulletin, made askable — with the page to prove every answer.'**
  String get tagline;

  /// No description provided for @signInAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInAction;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hidePassword;

  /// No description provided for @joinCode.
  ///
  /// In en, this message translates to:
  /// **'Join with invite code'**
  String get joinCode;

  /// No description provided for @signUpAction.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get signUpAction;

  /// No description provided for @signOutAction.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOutAction;

  /// No description provided for @joinTitle.
  ///
  /// In en, this message translates to:
  /// **'Join your institution'**
  String get joinTitle;

  /// No description provided for @joinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the invite code your institution gave you.'**
  String get joinSubtitle;

  /// No description provided for @inviteCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get inviteCodeLabel;

  /// No description provided for @joinAction.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get joinAction;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning, {name}'**
  String greetingMorning(String name);

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon, {name}'**
  String greetingAfternoon(String name);

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening, {name}'**
  String greetingEvening(String name);

  /// No description provided for @greetingPlain.
  ///
  /// In en, this message translates to:
  /// **'What would you like to know?'**
  String get greetingPlain;

  /// No description provided for @publishedDocuments.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 published document} other{{count} published documents}}'**
  String publishedDocuments(int count);

  /// No description provided for @tryAsking.
  ///
  /// In en, this message translates to:
  /// **'Try asking'**
  String get tryAsking;

  /// No description provided for @suggestExamStart.
  ///
  /// In en, this message translates to:
  /// **'When do the final examinations start?'**
  String get suggestExamStart;

  /// No description provided for @suggestMakeupFee.
  ///
  /// In en, this message translates to:
  /// **'How much does a makeup examination cost?'**
  String get suggestMakeupFee;

  /// No description provided for @suggestHoliday.
  ///
  /// In en, this message translates to:
  /// **'Is the university closed this week?'**
  String get suggestHoliday;

  /// No description provided for @suggestEvaluation.
  ///
  /// In en, this message translates to:
  /// **'When is the teachers\' evaluation open?'**
  String get suggestEvaluation;

  /// No description provided for @suggestHostelBn.
  ///
  /// In en, this message translates to:
  /// **'ছাত্রাবাসের নিয়ম কী?'**
  String get suggestHostelBn;

  /// No description provided for @suggestExamBn.
  ///
  /// In en, this message translates to:
  /// **'পরীক্ষা কবে শুরু হবে?'**
  String get suggestExamBn;

  /// No description provided for @askHome.
  ///
  /// In en, this message translates to:
  /// **'Ask about your campus documents'**
  String get askHome;

  /// No description provided for @askFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Ask a follow-up'**
  String get askFollowUp;

  /// No description provided for @sendAction.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get sendAction;

  /// No description provided for @attachTitle.
  ///
  /// In en, this message translates to:
  /// **'Attach a file'**
  String get attachTitle;

  /// No description provided for @attachCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get attachCamera;

  /// No description provided for @attachGallery.
  ///
  /// In en, this message translates to:
  /// **'Photo library'**
  String get attachGallery;

  /// No description provided for @attachFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get attachFiles;

  /// No description provided for @attachNote.
  ///
  /// In en, this message translates to:
  /// **'Your file is read to answer this question. It isn\'t added to your institution\'s documents.'**
  String get attachNote;

  /// No description provided for @attachAction.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get attachAction;

  /// No description provided for @removeAttachment.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeAttachment;

  /// No description provided for @uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get uploading;

  /// No description provided for @openPage.
  ///
  /// In en, this message translates to:
  /// **'Open page {page}'**
  String openPage(int page);

  /// No description provided for @pageLabel.
  ///
  /// In en, this message translates to:
  /// **'Page {page}'**
  String pageLabel(int page);

  /// No description provided for @pageOfPages.
  ///
  /// In en, this message translates to:
  /// **'Page {page} of {total}'**
  String pageOfPages(int page, int total);

  /// No description provided for @visionRead.
  ///
  /// In en, this message translates to:
  /// **'vision read'**
  String get visionRead;

  /// No description provided for @moreSources.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 more source} other{{count} more sources}}'**
  String moreSources(int count);

  /// No description provided for @notFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'No source found'**
  String get notFoundTitle;

  /// No description provided for @notFoundBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the published documents covers this. Try rephrasing, or ask the office.'**
  String get notFoundBody;

  /// No description provided for @rephrase.
  ///
  /// In en, this message translates to:
  /// **'Rephrase'**
  String get rephrase;

  /// No description provided for @askInBangla.
  ///
  /// In en, this message translates to:
  /// **'Ask in বাংলা'**
  String get askInBangla;

  /// No description provided for @askInEnglish.
  ///
  /// In en, this message translates to:
  /// **'Ask in English'**
  String get askInEnglish;

  /// No description provided for @scopeNoteStudent.
  ///
  /// In en, this message translates to:
  /// **'Answered from student-scoped documents only.'**
  String get scopeNoteStudent;

  /// No description provided for @scopeNoteTeacher.
  ///
  /// In en, this message translates to:
  /// **'Answered from teacher-scoped documents only.'**
  String get scopeNoteTeacher;

  /// No description provided for @scopeNoteAdmin.
  ///
  /// In en, this message translates to:
  /// **'Answered from all published documents.'**
  String get scopeNoteAdmin;

  /// No description provided for @readingRoutine.
  ///
  /// In en, this message translates to:
  /// **'Reading your routine…'**
  String get readingRoutine;

  /// No description provided for @foundCourses.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Found 1 course in your routine. Correct it if needed.} other{Found {count} courses in your routine. Correct these if needed.}}'**
  String foundCourses(int count);

  /// No description provided for @checkThisOne.
  ///
  /// In en, this message translates to:
  /// **'Check this one — low confidence · {score}'**
  String checkThisOne(String score);

  /// No description provided for @addCourse.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addCourse;

  /// No description provided for @confirmCta.
  ///
  /// In en, this message translates to:
  /// **'Looks right — find my exams'**
  String get confirmCta;

  /// No description provided for @extractionFailed.
  ///
  /// In en, this message translates to:
  /// **'The courses could not be read from this file. Add them by hand.'**
  String get extractionFailed;

  /// No description provided for @documentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documentsTitle;

  /// No description provided for @documentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing published yet.'**
  String get documentsEmpty;

  /// No description provided for @publishDocument.
  ///
  /// In en, this message translates to:
  /// **'Publish document'**
  String get publishDocument;

  /// No description provided for @publishShort.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get publishShort;

  /// No description provided for @publishTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get publishTitleLabel;

  /// No description provided for @whoCanAsk.
  ///
  /// In en, this message translates to:
  /// **'Who can ask about this'**
  String get whoCanAsk;

  /// No description provided for @requiredLabel.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredLabel;

  /// No description provided for @audienceEveryone.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get audienceEveryone;

  /// No description provided for @audienceStudents.
  ///
  /// In en, this message translates to:
  /// **'Students only'**
  String get audienceStudents;

  /// No description provided for @audienceTeachers.
  ///
  /// In en, this message translates to:
  /// **'Teachers only'**
  String get audienceTeachers;

  /// No description provided for @audienceAdmins.
  ///
  /// In en, this message translates to:
  /// **'Admins only'**
  String get audienceAdmins;

  /// No description provided for @audienceNote.
  ///
  /// In en, this message translates to:
  /// **'This controls who can ever see this content in an answer. It cannot be inherited from a default.'**
  String get audienceNote;

  /// No description provided for @statusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get statusReady;

  /// No description provided for @statusExtracting.
  ///
  /// In en, this message translates to:
  /// **'Extracting'**
  String get statusExtracting;

  /// No description provided for @statusEmbedding.
  ///
  /// In en, this message translates to:
  /// **'Embedding'**
  String get statusEmbedding;

  /// No description provided for @statusQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get statusQueued;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusFailed;

  /// No description provided for @statusLowConfidence.
  ///
  /// In en, this message translates to:
  /// **'Ready · text quality uncertain'**
  String get statusLowConfidence;

  /// No description provided for @reviewPages.
  ///
  /// In en, this message translates to:
  /// **'Review pages'**
  String get reviewPages;

  /// No description provided for @visionReread.
  ///
  /// In en, this message translates to:
  /// **'Re-read with vision'**
  String get visionReread;

  /// No description provided for @retryAction.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryAction;

  /// No description provided for @deleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAction;

  /// No description provided for @pagesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 page} other{{count} pages}}'**
  String pagesCount(int count);

  /// No description provided for @docsCountShort.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 doc} other{{count} docs}}'**
  String docsCountShort(int count);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @interfaceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Interface language'**
  String get interfaceLanguage;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageBangla.
  ///
  /// In en, this message translates to:
  /// **'বাংলা'**
  String get languageBangla;

  /// No description provided for @answerLangNote.
  ///
  /// In en, this message translates to:
  /// **'Answers always come back in the language you asked in, whichever you pick here.'**
  String get answerLangNote;

  /// No description provided for @displayNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayNameLabel;

  /// No description provided for @institutionLabel.
  ///
  /// In en, this message translates to:
  /// **'Institution'**
  String get institutionLabel;

  /// No description provided for @questionsToday.
  ///
  /// In en, this message translates to:
  /// **'Questions today'**
  String get questionsToday;

  /// No description provided for @chatHistory.
  ///
  /// In en, this message translates to:
  /// **'Chat history'**
  String get chatHistory;

  /// No description provided for @historyNote.
  ///
  /// In en, this message translates to:
  /// **'Kept on this device and in your institution account. Clearing removes it from both.'**
  String get historyNote;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get clearHistory;

  /// No description provided for @newQuestion.
  ///
  /// In en, this message translates to:
  /// **'New question'**
  String get newQuestion;

  /// No description provided for @roleStudent.
  ///
  /// In en, this message translates to:
  /// **'Student'**
  String get roleStudent;

  /// No description provided for @roleTeacher.
  ///
  /// In en, this message translates to:
  /// **'Teacher'**
  String get roleTeacher;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @scopeLine.
  ///
  /// In en, this message translates to:
  /// **'{role} scope · {count} docs'**
  String scopeLine(String role, int count);

  /// No description provided for @errorOffline.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Reconnect and try again.'**
  String get errorOffline;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get errorGeneric;

  /// No description provided for @errorSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Sign in again.'**
  String get errorSessionExpired;

  /// No description provided for @errorQuotaQuestions.
  ///
  /// In en, this message translates to:
  /// **'You have reached today\'s question limit. It resets in 24 hours.'**
  String get errorQuotaQuestions;

  /// No description provided for @errorQuotaAttachments.
  ///
  /// In en, this message translates to:
  /// **'You have reached today\'s attachment limit.'**
  String get errorQuotaAttachments;

  /// No description provided for @errorFileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That file is too large. The limit is {limit} MB.'**
  String errorFileTooLarge(int limit);

  /// No description provided for @errorNotAdmin.
  ///
  /// In en, this message translates to:
  /// **'Only an administrator can publish documents.'**
  String get errorNotAdmin;

  /// No description provided for @cancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelAction;

  /// No description provided for @closeAction.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeAction;

  /// No description provided for @retryLabel.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retryLabel;

  /// No description provided for @backLabel.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backLabel;

  /// No description provided for @checkYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Almost there — check {email} for a confirmation link, then sign in.'**
  String checkYourEmail(String email);

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your email address.'**
  String get emailRequired;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Your password needs at least 6 characters.'**
  String get passwordTooShort;
}

class _LDelegate extends LocalizationsDelegate<L> {
  const _LDelegate();

  @override
  Future<L> load(Locale locale) {
    return SynchronousFuture<L>(lookupL(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['bn', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_LDelegate old) => false;
}

L lookupL(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return LBn();
    case 'en':
      return LEn();
  }

  throw FlutterError(
    'L.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
