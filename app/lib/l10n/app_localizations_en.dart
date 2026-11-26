// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class LEn extends L {
  LEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Bulletin';

  @override
  String get showPassword => 'Show';

  @override
  String get hidePassword => 'Hide';

  @override
  String get signOutAction => 'Sign out';

  @override
  String get joinTitle => 'Join your institution';

  @override
  String get joinSubtitle => 'Enter the invite code from your department office.';

  @override
  String get inviteCodeLabel => 'Invite code';

  @override
  String get joinCodeHint => 'GUB-XXXX-00';

  @override
  String get joinCodeHelper =>
      'Letters and numbers only. The letter O and the number 0 are different.';

  @override
  String get joinCodeNotFound =>
      'This code doesn\'t match any institution. Check it with your office.';

  @override
  String get joinOptional => 'Optional';

  @override
  String get joinDisplayNameHelper =>
      'Used in greetings. Leave it empty to use your full name.';

  @override
  String get joinAction => 'Join institution';

  @override
  String get joinBusy => 'Joining';

  @override
  String get joinOffline => 'You\'re offline. Connect to the internet to join.';

  @override
  String publishedDocuments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count published documents',
      one: '1 published document',
    );
    return '$_temp0';
  }

  @override
  String get suggestExamStart => 'When do the final examinations start?';

  @override
  String get suggestMakeupFee => 'How much does a makeup examination cost?';

  @override
  String get suggestHoliday => 'Is the university closed this week?';

  @override
  String get suggestEvaluation => 'When is the teachers\' evaluation open?';

  @override
  String get suggestHostelBn => 'ছাত্রাবাসের নিয়ম কী?';

  @override
  String get suggestExamBn => 'পরীক্ষা কবে শুরু হবে?';

  @override
  String get askHome => 'Ask about exams, fees, rules…';

  @override
  String get askAboutFile => 'Ask about this file…';

  @override
  String homeGreeting(String name) {
    return 'Hi $name, what do you want to know today?';
  }

  @override
  String get homeGreetingNoName => 'What do you want to know today?';

  @override
  String homeInstitutionLine(String institution) {
    return 'Answers come only from $institution documents.';
  }

  @override
  String get homeInstitutionLineGeneric =>
      'Answers come only from your institution\'s documents.';

  @override
  String get homeAttachRoutine => 'Attach routine';

  @override
  String get homeMenuLabel => 'Settings';

  @override
  String get askFollowUp => 'Ask a follow-up';

  @override
  String get sendAction => 'Send';

  @override
  String get attachTitle => 'Add to your question';

  @override
  String get attachCamera => 'Take a photo';

  @override
  String get attachGallery => 'Choose from gallery';

  @override
  String get attachFiles => 'Choose a file';

  @override
  String get attachNote =>
      'Your file is read to answer this question. It isn\'t added to your institution\'s documents.';

  @override
  String get attachAction => 'Attach a file';

  @override
  String get removeAttachment => 'Remove';

  @override
  String get uploading => 'Uploading…';

  @override
  String openPage(int page) {
    return 'Open page $page';
  }

  @override
  String pageLabel(int page) {
    return 'Page $page';
  }

  @override
  String pageOfPages(int page, int total) {
    return 'Page $page of $total';
  }

  @override
  String get visionRead => 'vision read';

  @override
  String moreSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more sources',
      one: '1 more source',
    );
    return '$_temp0';
  }

  @override
  String get notFoundTitle => 'No source found';

  @override
  String get notFoundBody =>
      'Nothing in the published documents covers this. Try rephrasing, or ask the office.';

  @override
  String get rephrase => 'Rephrase';

  @override
  String get askInBangla => 'Ask in বাংলা';

  @override
  String get askInEnglish => 'Ask in English';

  @override
  String get scopeNoteStudent => 'Answered from student-scoped documents only.';

  @override
  String get scopeNoteTeacher => 'Answered from teacher-scoped documents only.';

  @override
  String get scopeNoteAdmin => 'Answered from all published documents.';

  @override
  String get readingRoutine => 'Reading your routine…';

  @override
  String foundCourses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Found $count courses in your routine. Correct these if needed.',
      one: 'Found 1 course in your routine. Correct it if needed.',
    );
    return '$_temp0';
  }

  @override
  String checkThisOne(String score) {
    return 'Check this one — low confidence · $score';
  }

  @override
  String get addCourse => 'Add';

  @override
  String get confirmCta => 'Looks right — find my exams';

  @override
  String get extractionFailed =>
      'The courses could not be read from this file. Add them by hand.';

  @override
  String get documentsTitle => 'Documents';

  @override
  String get documentsEmpty => 'Nothing published yet.';

  @override
  String get publishDocument => 'Publish document';

  @override
  String get publishShort => 'Publish';

  @override
  String get publishTitleLabel => 'Title';

  @override
  String get whoCanAsk => 'Who can ask about this';

  @override
  String get requiredLabel => 'Required';

  @override
  String get audienceEveryone => 'Everyone';

  @override
  String get audienceStudents => 'Students only';

  @override
  String get audienceTeachers => 'Teachers only';

  @override
  String get audienceAdmins => 'Admins only';

  @override
  String get audienceNote =>
      'This controls who can ever see this content in an answer. It cannot be inherited from a default.';

  @override
  String get statusReady => 'Ready';

  @override
  String get statusExtracting => 'Extracting';

  @override
  String get statusEmbedding => 'Embedding';

  @override
  String get statusQueued => 'Queued';

  @override
  String get statusFailed => 'Failed';

  @override
  String get statusLowConfidence => 'Ready · text quality uncertain';

  @override
  String get reviewPages => 'Review pages';

  @override
  String get visionReread => 'Re-read with vision';

  @override
  String get retryAction => 'Retry';

  @override
  String get deleteAction => 'Delete';

  @override
  String pagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String docsCountShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count docs',
      one: '1 doc',
    );
    return '$_temp0';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get interfaceLanguage => 'Interface language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageBangla => 'বাংলা';

  @override
  String get answerLangNote =>
      'The app changes instantly. Answers follow the language you ask in.';

  @override
  String get displayNameLabel => 'Display name';

  @override
  String get institutionLabel => 'Institution';

  @override
  String get questionsToday => 'Questions today';

  @override
  String get chatHistory => 'Chat history';

  @override
  String get historyNote =>
      'Kept on this device and in your institution account. Clearing removes it from both.';

  @override
  String get clearHistory => 'Clear history';

  @override
  String get newQuestion => 'New question';

  @override
  String get roleStudent => 'Student';

  @override
  String get roleTeacher => 'Teacher';

  @override
  String get roleAdmin => 'Admin';

  @override
  String scopeLine(String role, int count) {
    return '$role scope · $count docs';
  }

  @override
  String get errorOffline => 'You are offline. Reconnect and try again.';

  @override
  String get errorGeneric => 'Something went wrong. Try again.';

  @override
  String get errorSessionExpired => 'Your session expired. Sign in again.';

  @override
  String get errorQuotaQuestions =>
      'You have reached today\'s question limit. It resets in 24 hours.';

  @override
  String get errorQuotaAttachments => 'You have reached today\'s attachment limit.';

  @override
  String errorFileTooLarge(int limit) {
    return 'That file is too large. The limit is $limit MB.';
  }

  @override
  String get errorNotAdmin => 'Only an administrator can publish documents.';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get closeAction => 'Close';

  @override
  String get retryLabel => 'Try again';

  @override
  String get backLabel => 'Back';

  @override
  String get splashTagline =>
      'Answers from your campus documents, with the page they came from.';

  @override
  String get pandaWavingLabel => 'Bulletin panda waving';

  @override
  String get welcomeTitle => 'Answers for every campus question.';

  @override
  String get welcomeSubtitle =>
      'Exams, fees and rules from your university\'s own documents, with the page they came from.';

  @override
  String get welcomeLogIn => 'Log in';

  @override
  String get authSignInTitle => 'Sign in';

  @override
  String get authSignInSubtitle => 'Use the email your institution gave you.';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authPasswordHelper => 'At least 8 characters.';

  @override
  String get authEmailInvalid =>
      'This email is incomplete. Add the domain, like name@green.edu.bd.';

  @override
  String get authWrongPassword =>
      'This password doesn\'t match the email. Check it, or reset your password.';

  @override
  String get authResetPassword => 'Reset password';

  @override
  String get authSignInAction => 'Sign in';

  @override
  String get authSigningIn => 'Signing in';

  @override
  String get authOr => 'Or';

  @override
  String get authJoinWithInvite => 'Join with invite code';

  @override
  String get authNewHere => 'New to Bulletin?';

  @override
  String get authCreateAccountLink => 'Create account';

  @override
  String get authTermsPrefix => 'By signing in, you agree to our ';

  @override
  String get authTermsLink => 'Terms of Use';

  @override
  String get authTermsSuffix => '.';

  @override
  String get createTitle => 'Create account';

  @override
  String get createSubtitle => 'You\'ll confirm your email before your first question.';

  @override
  String get createNameLabel => 'Full name';

  @override
  String get createAction => 'Create account';

  @override
  String get createHaveAccount => 'Already have an account?';

  @override
  String get createSignInLink => 'Sign in';

  @override
  String get privacyPrefix => 'For more information, see our ';

  @override
  String get privacyLink => 'Privacy policy';

  @override
  String get privacySuffix => '.';

  @override
  String get checkTitle => 'Check your email';

  @override
  String get checkHeading => 'Your account is created';

  @override
  String get checkResend => 'Resend link';

  @override
  String get checkDifferentEmail => 'Use a different email';

  @override
  String get authEmailHint => 'you@green.edu.bd';

  @override
  String authResetSent(String email) {
    return 'If an account uses $email, a reset link is on its way.';
  }

  @override
  String get authResetNeedsEmail => 'Enter your email above, then tap Reset password.';

  @override
  String get authErrorNotConfirmed =>
      'Confirm your email first. Open the link we sent you.';

  @override
  String get authErrorAlreadyRegistered =>
      'This email already has an account. Sign in instead.';

  @override
  String get authErrorWeakPassword => 'Choose a stronger password.';

  @override
  String get authErrorRateLimited => 'Too many tries. Wait a minute, then try again.';

  @override
  String createPasswordShort(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String countString = countNumberFormat.format(count);

    return 'Use at least 8 characters. This one has $countString.';
  }

  @override
  String checkBody(String email) {
    return 'We sent a confirmation link to $email. Open it on this phone to continue.';
  }

  @override
  String get checkResent => 'A new link is on its way.';

  @override
  String get newChat => 'New chat';

  @override
  String get modelMenuTitle => 'AI model';

  @override
  String modelPillLabel(String name) {
    return 'Model: $name';
  }

  @override
  String modelDefault(String maker) {
    return '$maker · Default';
  }

  @override
  String modelLowCost(String maker) {
    return '$maker · Fast, low cost';
  }

  @override
  String modelHighCost(String maker) {
    return '$maker · Stronger, costs more';
  }

  @override
  String get settingsProfile => 'Profile';

  @override
  String get settingsEmail => 'Email';

  @override
  String get joinedWithCode => 'Joined with code';

  @override
  String get documentsRowSub => 'Publish and review documents';

  @override
  String get displayNameSaved => 'Saved';

  @override
  String get attachCameraSub => 'Routine, registration slip or notice';

  @override
  String get attachGallerySub => 'JPG or PNG';

  @override
  String get attachFilesSub => 'PDF';

  @override
  String get attachLimitBefore => 'Up to ';

  @override
  String get attachLimitAfter => ' per file.';

  @override
  String get sheetHandleLabel => 'Close';

  @override
  String get sourcesHeader => 'Sources';

  @override
  String get stepSearching => 'Searching documents…';

  @override
  String stepReadCourses(int count) {
    return 'Read $count courses from your routine';
  }

  @override
  String get offlineBanner => 'You\'re offline. Answers need a connection.';

  @override
  String get notSentOffline => 'Not sent. You\'re offline.';

  @override
  String get retryMessage => 'Retry';

  @override
  String sourceExpandLabel(String title, String page) {
    return '$title, $page';
  }
}
