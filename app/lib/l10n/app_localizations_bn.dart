// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bengali Bangla (`bn`).
class LBn extends L {
  LBn([String locale = 'bn']) : super(locale);

  @override
  String get appTitle => 'বুলেটিন';

  @override
  String get tagline => 'আপনার প্রতিষ্ঠানের নোটিশ — প্রশ্ন করুন, প্রমাণসহ উত্তর পান।';

  @override
  String get signInAction => 'সাইন ইন';

  @override
  String get emailLabel => 'ইমেইল';

  @override
  String get passwordLabel => 'পাসওয়ার্ড';

  @override
  String get showPassword => 'দেখান';

  @override
  String get hidePassword => 'লুকান';

  @override
  String get joinCode => 'ইনভাইট কোড দিয়ে যোগ দিন';

  @override
  String get signUpAction => 'অ্যাকাউন্ট তৈরি করুন';

  @override
  String get signOutAction => 'সাইন আউট';

  @override
  String get joinTitle => 'আপনার প্রতিষ্ঠানে যোগ দিন';

  @override
  String get joinSubtitle => 'প্রতিষ্ঠান থেকে পাওয়া ইনভাইট কোডটি লিখুন।';

  @override
  String get inviteCodeLabel => 'ইনভাইট কোড';

  @override
  String get joinAction => 'যোগ দিন';

  @override
  String greetingMorning(String name) {
    return 'শুভ সকাল, $name';
  }

  @override
  String greetingAfternoon(String name) {
    return 'শুভ অপরাহ্ন, $name';
  }

  @override
  String greetingEvening(String name) {
    return 'শুভ সন্ধ্যা, $name';
  }

  @override
  String get greetingPlain => 'কী জানতে চান?';

  @override
  String publishedDocuments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countটি প্রকাশিত নথি',
      one: '১টি প্রকাশিত নথি',
    );
    return '$_temp0';
  }

  @override
  String get tryAsking => 'জিজ্ঞাসা করে দেখুন';

  @override
  String get suggestExamStart => 'চূড়ান্ত পরীক্ষা কবে শুরু হবে?';

  @override
  String get suggestMakeupFee => 'মেকআপ পরীক্ষার ফি কত?';

  @override
  String get suggestHoliday => 'এই সপ্তাহে কি বিশ্ববিদ্যালয় বন্ধ?';

  @override
  String get suggestEvaluation => 'শিক্ষক মূল্যায়ন কবে খোলা থাকবে?';

  @override
  String get suggestHostelBn => 'ছাত্রাবাসের নিয়ম কী?';

  @override
  String get suggestExamBn => 'When do the final examinations start?';

  @override
  String get askHome => 'আপনার ক্যাম্পাসের নথি নিয়ে প্রশ্ন করুন';

  @override
  String get askFollowUp => 'আরেকটি প্রশ্ন করুন';

  @override
  String get sendAction => 'পাঠান';

  @override
  String get attachTitle => 'ফাইল যুক্ত করুন';

  @override
  String get attachCamera => 'ক্যামেরা';

  @override
  String get attachGallery => 'ছবির গ্যালারি';

  @override
  String get attachFiles => 'ফাইল';

  @override
  String get attachNote =>
      'ফাইলটি শুধু এই প্রশ্নের উত্তর দিতে পড়া হয়। প্রতিষ্ঠানের নথিতে এটি যোগ করা হয় না।';

  @override
  String get attachAction => 'যুক্ত করুন';

  @override
  String get removeAttachment => 'সরান';

  @override
  String get uploading => 'আপলোড হচ্ছে…';

  @override
  String openPage(int page) {
    return 'পৃষ্ঠা দেখুন $page';
  }

  @override
  String pageLabel(int page) {
    return 'পৃষ্ঠা $page';
  }

  @override
  String pageOfPages(int page, int total) {
    return 'পৃষ্ঠা $page / $total';
  }

  @override
  String get visionRead => 'ভিশন রিড';

  @override
  String moreSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'আরও $countটি সূত্র',
      one: 'আরও ১টি সূত্র',
    );
    return '$_temp0';
  }

  @override
  String get notFoundTitle => 'কোনো সূত্র পাওয়া যায়নি';

  @override
  String get notFoundBody =>
      'প্রকাশিত নথিতে এ বিষয়ে কিছু পাওয়া যায়নি। প্রশ্নটি অন্যভাবে লিখুন, বা অফিসে জিজ্ঞাসা করুন।';

  @override
  String get rephrase => 'অন্যভাবে লিখুন';

  @override
  String get askInBangla => 'বাংলায় জিজ্ঞাসা করুন';

  @override
  String get askInEnglish => 'ইংরেজিতে জিজ্ঞাসা করুন';

  @override
  String get scopeNoteStudent =>
      'শুধু ছাত্রছাত্রীদের জন্য প্রকাশিত নথি থেকে উত্তর দেওয়া হয়েছে।';

  @override
  String get scopeNoteTeacher =>
      'শুধু শিক্ষকদের জন্য প্রকাশিত নথি থেকে উত্তর দেওয়া হয়েছে।';

  @override
  String get scopeNoteAdmin => 'সব প্রকাশিত নথি থেকে উত্তর দেওয়া হয়েছে।';

  @override
  String get readingRoutine => 'আপনার রুটিন পড়া হচ্ছে…';

  @override
  String foundCourses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'আপনার রুটিনে $countটি কোর্স পাওয়া গেছে। প্রয়োজনে ঠিক করে নিন।',
      one: 'আপনার রুটিনে ১টি কোর্স পাওয়া গেছে। প্রয়োজনে ঠিক করে নিন।',
    );
    return '$_temp0';
  }

  @override
  String checkThisOne(String score) {
    return 'এটি যাচাই করুন — আত্মবিশ্বাস কম · $score';
  }

  @override
  String get addCourse => 'যোগ করুন';

  @override
  String get confirmCta => 'ঠিক আছে — আমার পরীক্ষা খুঁজুন';

  @override
  String get extractionFailed =>
      'এই ফাইল থেকে কোর্সগুলো পড়া যায়নি। হাতে লিখে যোগ করুন।';

  @override
  String get documentsTitle => 'নথি';

  @override
  String get documentsEmpty => 'এখনো কিছু প্রকাশ করা হয়নি।';

  @override
  String get publishDocument => 'নথি প্রকাশ করুন';

  @override
  String get publishShort => 'প্রকাশ';

  @override
  String get publishTitleLabel => 'শিরোনাম';

  @override
  String get whoCanAsk => 'কারা এ বিষয়ে জিজ্ঞাসা করতে পারবে';

  @override
  String get requiredLabel => 'আবশ্যক';

  @override
  String get audienceEveryone => 'সবাই';

  @override
  String get audienceStudents => 'শুধু ছাত্রছাত্রী';

  @override
  String get audienceTeachers => 'শুধু শিক্ষক';

  @override
  String get audienceAdmins => 'শুধু অ্যাডমিন';

  @override
  String get audienceNote =>
      'কে কখনো এই তথ্য উত্তরে দেখতে পাবে, তা এটিই নির্ধারণ করে। ডিফল্ট থেকে এটি ধরে নেওয়া হয় না।';

  @override
  String get statusReady => 'প্রস্তুত';

  @override
  String get statusExtracting => 'টেক্সট নেওয়া হচ্ছে';

  @override
  String get statusEmbedding => 'এমবেডিং';

  @override
  String get statusQueued => 'অপেক্ষমাণ';

  @override
  String get statusFailed => 'ব্যর্থ';

  @override
  String get statusLowConfidence => 'প্রস্তুত · লেখার গুণমান অনিশ্চিত';

  @override
  String get reviewPages => 'পৃষ্ঠা যাচাই করুন';

  @override
  String get visionReread => 'ভিশন দিয়ে আবার পড়ান';

  @override
  String get retryAction => 'আবার চেষ্টা';

  @override
  String get deleteAction => 'মুছে ফেলুন';

  @override
  String pagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count পৃষ্ঠা',
      one: '১ পৃষ্ঠা',
    );
    return '$_temp0';
  }

  @override
  String docsCountShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count নথি',
      one: '১ নথি',
    );
    return '$_temp0';
  }

  @override
  String get settingsTitle => 'সেটিংস';

  @override
  String get interfaceLanguage => 'ইন্টারফেসের ভাষা';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageBangla => 'বাংলা';

  @override
  String get answerLangNote =>
      'এখানে যা-ই নির্বাচন করুন, আপনি যে ভাষায় প্রশ্ন করবেন উত্তর সেই ভাষাতেই আসবে।';

  @override
  String get displayNameLabel => 'প্রদর্শিত নাম';

  @override
  String get institutionLabel => 'প্রতিষ্ঠান';

  @override
  String get questionsToday => 'আজকের প্রশ্ন';

  @override
  String get chatHistory => 'চ্যাট ইতিহাস';

  @override
  String get historyNote =>
      'এই ডিভাইসে ও আপনার প্রাতিষ্ঠানিক অ্যাকাউন্টে রাখা হয়। মুছে ফেললে দুই জায়গা থেকেই মুছে যায়।';

  @override
  String get clearHistory => 'ইতিহাস মুছুন';

  @override
  String get newQuestion => 'নতুন প্রশ্ন';

  @override
  String get roleStudent => 'ছাত্রছাত্রী';

  @override
  String get roleTeacher => 'শিক্ষক';

  @override
  String get roleAdmin => 'অ্যাডমিন';

  @override
  String scopeLine(String role, int count) {
    return '$role স্কোপ · $count নথি';
  }

  @override
  String get errorOffline => 'আপনি অফলাইনে আছেন। সংযোগ ফিরলে আবার চেষ্টা করুন।';

  @override
  String get errorGeneric => 'কিছু একটা সমস্যা হয়েছে। আবার চেষ্টা করুন।';

  @override
  String get errorSessionExpired => 'আপনার সেশনের মেয়াদ শেষ। আবার সাইন ইন করুন।';

  @override
  String get errorQuotaQuestions =>
      'আজকের প্রশ্নের সীমা শেষ। ২৪ ঘণ্টা পরে আবার শুরু হবে।';

  @override
  String get errorQuotaAttachments => 'আজকের সংযুক্তির সীমা শেষ।';

  @override
  String errorFileTooLarge(int limit) {
    return 'ফাইলটি অনেক বড়। সীমা $limit MB।';
  }

  @override
  String get errorNotAdmin => 'শুধু প্রশাসকই নথি প্রকাশ করতে পারেন।';

  @override
  String get cancelAction => 'বাতিল';

  @override
  String get closeAction => 'বন্ধ করুন';

  @override
  String get retryLabel => 'আবার চেষ্টা করুন';

  @override
  String get backLabel => 'ফিরে যান';

  @override
  String checkYourEmail(String email) {
    return 'প্রায় হয়ে গেছে — $email ঠিকানায় পাঠানো লিঙ্কে ক্লিক করে সাইন ইন করুন।';
  }

  @override
  String get emailRequired => 'আপনার ইমেইল ঠিকানা লিখুন।';

  @override
  String get passwordTooShort => 'পাসওয়ার্ড অন্তত ৬ অক্ষরের হতে হবে।';
}
