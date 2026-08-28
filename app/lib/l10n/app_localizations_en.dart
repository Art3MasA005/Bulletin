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
  String get tagline =>
      'Your institution\'s bulletin, made askable — with the page to prove every answer.';

  @override
  String get signInAction => 'Sign in';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get showPassword => 'Show';

  @override
  String get hidePassword => 'Hide';

  @override
  String get joinCode => 'Join with invite code';

  @override
  String get signUpAction => 'Create an account';

  @override
  String get signOutAction => 'Sign out';

  @override
  String get joinTitle => 'Join your institution';

  @override
  String get joinSubtitle => 'Enter the invite code your institution gave you.';

  @override
  String get inviteCodeLabel => 'Invite code';

  @override
  String get joinAction => 'Join';

  @override
  String greetingMorning(String name) {
    return 'Good morning, $name';
  }

  @override
  String greetingAfternoon(String name) {
    return 'Good afternoon, $name';
  }

  @override
  String greetingEvening(String name) {
    return 'Good evening, $name';
  }

  @override
  String get greetingPlain => 'What would you like to know?';

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
  String get tryAsking => 'Try asking';

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
  String get askHome => 'Ask about your campus documents';

  @override
  String get askFollowUp => 'Ask a follow-up';

  @override
  String get sendAction => 'Send';

  @override
  String get attachTitle => 'Attach a file';

  @override
  String get attachCamera => 'Camera';

  @override
  String get attachGallery => 'Photo library';

  @override
  String get attachFiles => 'Files';

  @override
  String get attachNote =>
      'Your file is read to answer this question. It isn\'t added to your institution\'s documents.';

  @override
  String get attachAction => 'Attach';

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
      'Answers always come back in the language you asked in, whichever you pick here.';

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
  String checkYourEmail(String email) {
    return 'Almost there — check $email for a confirmation link, then sign in.';
  }

  @override
  String get emailRequired => 'Enter your email address.';

  @override
  String get passwordTooShort => 'Your password needs at least 6 characters.';
}
