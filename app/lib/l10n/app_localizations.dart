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
  /// **'Enter the invite code from your department office.'**
  String get joinSubtitle;

  /// No description provided for @inviteCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get inviteCodeLabel;

  /// Placeholder showing the invite code's shape. Keep the Latin letters: codes are always Latin.
  ///
  /// In en, this message translates to:
  /// **'GUB-XXXX-00'**
  String get joinCodeHint;

  /// No description provided for @joinCodeHelper.
  ///
  /// In en, this message translates to:
  /// **'Letters and numbers only. The letter O and the number 0 are different.'**
  String get joinCodeHelper;

  /// No description provided for @joinCodeNotFound.
  ///
  /// In en, this message translates to:
  /// **'This code doesn\'t match any institution. Check it with your office.'**
  String get joinCodeNotFound;

  /// No description provided for @joinOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get joinOptional;

  /// No description provided for @joinDisplayNameHelper.
  ///
  /// In en, this message translates to:
  /// **'Used in greetings. Leave it empty to use your full name.'**
  String get joinDisplayNameHelper;

  /// No description provided for @joinAction.
  ///
  /// In en, this message translates to:
  /// **'Join institution'**
  String get joinAction;

  /// No description provided for @joinBusy.
  ///
  /// In en, this message translates to:
  /// **'Joining'**
  String get joinBusy;

  /// No description provided for @joinOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Connect to the internet to join.'**
  String get joinOffline;

  /// No description provided for @publishedDocuments.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 published document} other{{count} published documents}}'**
  String publishedDocuments(int count);

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
  /// **'Ask about exams, fees, rules…'**
  String get askHome;

  /// No description provided for @askAboutFile.
  ///
  /// In en, this message translates to:
  /// **'Ask about this file…'**
  String get askAboutFile;

  /// No description provided for @homeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hi {name}, what do you want to know today?'**
  String homeGreeting(String name);

  /// No description provided for @homeGreetingNoName.
  ///
  /// In en, this message translates to:
  /// **'What do you want to know today?'**
  String get homeGreetingNoName;

  /// No description provided for @homeInstitutionLine.
  ///
  /// In en, this message translates to:
  /// **'Answers come only from {institution} documents.'**
  String homeInstitutionLine(String institution);

  /// No description provided for @homeInstitutionLineGeneric.
  ///
  /// In en, this message translates to:
  /// **'Answers come only from your institution\'s documents.'**
  String get homeInstitutionLineGeneric;

  /// No description provided for @homeAttachRoutine.
  ///
  /// In en, this message translates to:
  /// **'Attach routine'**
  String get homeAttachRoutine;

  /// Screen-reader label for the round menu button on Home.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get homeMenuLabel;

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
  /// **'Add to your question'**
  String get attachTitle;

  /// No description provided for @attachCamera.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get attachCamera;

  /// No description provided for @attachGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get attachGallery;

  /// No description provided for @attachFiles.
  ///
  /// In en, this message translates to:
  /// **'Choose a file'**
  String get attachFiles;

  /// No description provided for @attachNote.
  ///
  /// In en, this message translates to:
  /// **'Your file is read to answer this question. It isn\'t added to your institution\'s documents.'**
  String get attachNote;

  /// No description provided for @attachAction.
  ///
  /// In en, this message translates to:
  /// **'Attach a file'**
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
  /// **'The app changes instantly. Answers follow the language you ask in.'**
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

  /// Under the wordmark on the splash screen. Verbatim from the handoff's bulletin-data.js.
  ///
  /// In en, this message translates to:
  /// **'Answers from your campus documents, with the page they came from.'**
  String get splashTagline;

  /// Screen-reader label for the waving panda on the splash and the Welcome screen.
  ///
  /// In en, this message translates to:
  /// **'Bulletin panda waving'**
  String get pandaWavingLabel;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Answers for every campus question.'**
  String get welcomeTitle;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Exams, fees and rules from your university\'s own documents, with the page they came from.'**
  String get welcomeSubtitle;

  /// The Welcome screen's one button; opens sign in.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get welcomeLogIn;

  /// Auth strings: verbatim from docs/design/handoff/bulletin-data.js unless noted in TASKS.md.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignInTitle;

  /// No description provided for @authSignInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use the email your institution gave you.'**
  String get authSignInSubtitle;

  /// No description provided for @authEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// No description provided for @authPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// No description provided for @authPasswordHelper.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters.'**
  String get authPasswordHelper;

  /// No description provided for @authEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'This email is incomplete. Add the domain, like name@green.edu.bd.'**
  String get authEmailInvalid;

  /// No description provided for @authWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'This password doesn\'t match the email. Check it, or reset your password.'**
  String get authWrongPassword;

  /// No description provided for @authResetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get authResetPassword;

  /// No description provided for @authSignInAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignInAction;

  /// No description provided for @authSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in'**
  String get authSigningIn;

  /// No description provided for @authOr.
  ///
  /// In en, this message translates to:
  /// **'Or'**
  String get authOr;

  /// No description provided for @authJoinWithInvite.
  ///
  /// In en, this message translates to:
  /// **'Join with invite code'**
  String get authJoinWithInvite;

  /// No description provided for @authNewHere.
  ///
  /// In en, this message translates to:
  /// **'New to Bulletin?'**
  String get authNewHere;

  /// No description provided for @authCreateAccountLink.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccountLink;

  /// No description provided for @authTermsPrefix.
  ///
  /// In en, this message translates to:
  /// **'By signing in, you agree to our '**
  String get authTermsPrefix;

  /// No description provided for @authTermsLink.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use'**
  String get authTermsLink;

  /// No description provided for @authTermsSuffix.
  ///
  /// In en, this message translates to:
  /// **'.'**
  String get authTermsSuffix;

  /// No description provided for @createTitle.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createTitle;

  /// No description provided for @createSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ll confirm your email before your first question.'**
  String get createSubtitle;

  /// No description provided for @createNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get createNameLabel;

  /// No description provided for @createAction.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAction;

  /// No description provided for @createHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get createHaveAccount;

  /// No description provided for @createSignInLink.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get createSignInLink;

  /// No description provided for @privacyPrefix.
  ///
  /// In en, this message translates to:
  /// **'For more information, see our '**
  String get privacyPrefix;

  /// No description provided for @privacyLink.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyLink;

  /// No description provided for @privacySuffix.
  ///
  /// In en, this message translates to:
  /// **'.'**
  String get privacySuffix;

  /// No description provided for @checkTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get checkTitle;

  /// No description provided for @checkHeading.
  ///
  /// In en, this message translates to:
  /// **'Your account is created'**
  String get checkHeading;

  /// No description provided for @checkResend.
  ///
  /// In en, this message translates to:
  /// **'Resend link'**
  String get checkResend;

  /// No description provided for @checkDifferentEmail.
  ///
  /// In en, this message translates to:
  /// **'Use a different email'**
  String get checkDifferentEmail;

  /// No description provided for @authEmailHint.
  ///
  /// In en, this message translates to:
  /// **'you@green.edu.bd'**
  String get authEmailHint;

  /// No description provided for @authResetSent.
  ///
  /// In en, this message translates to:
  /// **'If an account uses {email}, a reset link is on its way.'**
  String authResetSent(String email);

  /// No description provided for @authResetNeedsEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter your email above, then tap Reset password.'**
  String get authResetNeedsEmail;

  /// No description provided for @authErrorNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirm your email first. Open the link we sent you.'**
  String get authErrorNotConfirmed;

  /// No description provided for @authErrorAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'This email already has an account. Sign in instead.'**
  String get authErrorAlreadyRegistered;

  /// No description provided for @authErrorWeakPassword.
  ///
  /// In en, this message translates to:
  /// **'Choose a stronger password.'**
  String get authErrorWeakPassword;

  /// No description provided for @authErrorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many tries. Wait a minute, then try again.'**
  String get authErrorRateLimited;

  /// No description provided for @createPasswordShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 8 characters. This one has {count}.'**
  String createPasswordShort(int count);

  /// The email is shown in bold; it must appear exactly once.
  ///
  /// In en, this message translates to:
  /// **'We sent a confirmation link to {email}. Open it on this phone to continue.'**
  String checkBody(String email);

  /// No description provided for @checkResent.
  ///
  /// In en, this message translates to:
  /// **'A new link is on its way.'**
  String get checkResent;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChat;

  /// No description provided for @modelMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'AI model'**
  String get modelMenuTitle;

  /// No description provided for @modelPillLabel.
  ///
  /// In en, this message translates to:
  /// **'Model: {name}'**
  String modelPillLabel(String name);

  /// No description provided for @modelDefault.
  ///
  /// In en, this message translates to:
  /// **'{maker} · Default'**
  String modelDefault(String maker);

  /// No description provided for @modelLowCost.
  ///
  /// In en, this message translates to:
  /// **'{maker} · Fast, low cost'**
  String modelLowCost(String maker);

  /// No description provided for @modelHighCost.
  ///
  /// In en, this message translates to:
  /// **'{maker} · Stronger, costs more'**
  String modelHighCost(String maker);

  /// No description provided for @settingsProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get settingsProfile;

  /// No description provided for @settingsEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get settingsEmail;

  /// No description provided for @joinedWithCode.
  ///
  /// In en, this message translates to:
  /// **'Joined with code'**
  String get joinedWithCode;

  /// No description provided for @documentsRowSub.
  ///
  /// In en, this message translates to:
  /// **'Publish and review documents'**
  String get documentsRowSub;

  /// No description provided for @displayNameSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get displayNameSaved;

  /// No description provided for @attachCameraSub.
  ///
  /// In en, this message translates to:
  /// **'Routine, registration slip or notice'**
  String get attachCameraSub;

  /// No description provided for @attachGallerySub.
  ///
  /// In en, this message translates to:
  /// **'JPG or PNG'**
  String get attachGallerySub;

  /// No description provided for @attachFilesSub.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get attachFilesSub;

  /// No description provided for @attachLimitBefore.
  ///
  /// In en, this message translates to:
  /// **'Up to '**
  String get attachLimitBefore;

  /// No description provided for @attachLimitAfter.
  ///
  /// In en, this message translates to:
  /// **' per file.'**
  String get attachLimitAfter;

  /// No description provided for @sheetHandleLabel.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get sheetHandleLabel;

  /// No description provided for @sourcesHeader.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get sourcesHeader;

  /// No description provided for @stepSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching documents…'**
  String get stepSearching;

  /// No description provided for @stepReadCourses.
  ///
  /// In en, this message translates to:
  /// **'Read {count} courses from your routine'**
  String stepReadCourses(int count);

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Answers need a connection.'**
  String get offlineBanner;

  /// No description provided for @notSentOffline.
  ///
  /// In en, this message translates to:
  /// **'Not sent. You\'re offline.'**
  String get notSentOffline;

  /// No description provided for @retryMessage.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryMessage;

  /// No description provided for @sourceExpandLabel.
  ///
  /// In en, this message translates to:
  /// **'{title}, {page}'**
  String sourceExpandLabel(String title, String page);
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
