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
  String get showPassword => 'দেখান';

  @override
  String get hidePassword => 'লুকান';

  @override
  String get signOutAction => 'সাইন আউট';

  @override
  String get joinTitle => 'প্রতিষ্ঠানে যোগ দিন';

  @override
  String get joinSubtitle => 'বিভাগীয় অফিস থেকে পাওয়া আমন্ত্রণ কোডটি লিখুন।';

  @override
  String get inviteCodeLabel => 'আমন্ত্রণ কোড';

  @override
  String get joinCodeHint => 'GUB-XXXX-00';

  @override
  String get joinCodeHelper => 'শুধু অক্ষর ও সংখ্যা। ইংরেজি O অক্ষর আর 0 সংখ্যা আলাদা।';

  @override
  String get joinCodeNotFound =>
      'এই কোড কোনো প্রতিষ্ঠানের সাথে মেলে না। অফিস থেকে কোডটি মিলিয়ে নিন।';

  @override
  String get joinOptional => 'ঐচ্ছিক';

  @override
  String get joinDisplayNameHelper =>
      'শুভেচ্ছাবার্তায় দেখানো হবে। খালি রাখলে পুরো নাম দেখাবে।';

  @override
  String get joinAction => 'প্রতিষ্ঠানে যোগ দিন';

  @override
  String get joinBusy => 'যোগ দেওয়া হচ্ছে';

  @override
  String get joinOffline => 'আপনি অফলাইনে আছেন। যোগ দিতে ইন্টারনেটে সংযুক্ত হোন।';

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
  String get askHome => 'পরীক্ষা, ফি বা নিয়ম নিয়ে জিজ্ঞেস করুন…';

  @override
  String get askAboutFile => 'এই ফাইল নিয়ে জিজ্ঞেস করুন…';

  @override
  String homeGreeting(String name) {
    return 'হাই $name, আজ কী জানতে চান?';
  }

  @override
  String get homeGreetingNoName => 'আজ কী জানতে চান?';

  @override
  String homeInstitutionLine(String institution) {
    return 'উত্তর আসে শুধু $institution-এর ডকুমেন্ট থেকে।';
  }

  @override
  String get homeInstitutionLineGeneric =>
      'উত্তর আসে শুধু আপনার প্রতিষ্ঠানের ডকুমেন্ট থেকে।';

  @override
  String get homeAttachRoutine => 'রুটিন যুক্ত করুন';

  @override
  String get homeMenuLabel => 'সেটিংস';

  @override
  String get askFollowUp => 'আরেকটি প্রশ্ন করুন';

  @override
  String get sendAction => 'পাঠান';

  @override
  String get attachTitle => 'প্রশ্নের সঙ্গে যুক্ত করুন';

  @override
  String get attachCamera => 'ছবি তুলুন';

  @override
  String get attachGallery => 'গ্যালারি থেকে বেছে নিন';

  @override
  String get attachFiles => 'ফাইল বেছে নিন';

  @override
  String get attachNote =>
      'ফাইলটি শুধু এই প্রশ্নের উত্তর দিতে পড়া হয়। প্রতিষ্ঠানের নথিতে এটি যোগ করা হয় না।';

  @override
  String get attachAction => 'ফাইল যুক্ত করুন';

  @override
  String get removeAttachment => 'সরান';

  @override
  String get uploading => 'আপলোড হচ্ছে…';

  @override
  String openPage(int page) {
    return 'পৃষ্ঠা $page খুলুন';
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
      other: 'আরও $countটি উৎস',
      one: 'আরও ১টি উৎস',
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
      'অ্যাপের ভাষা সঙ্গে সঙ্গে বদলে যায়। যে ভাষায় প্রশ্ন করবেন, উত্তর সেই ভাষায় আসবে।';

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
  String get splashTagline => 'ক্যাম্পাসের ডকুমেন্ট থেকে উত্তর, সঙ্গে উৎসের পাতা।';

  @override
  String get pandaWavingLabel => 'বুলেটিনের পান্ডা হাত নাড়ছে';

  @override
  String get welcomeTitle => 'ক্যাম্পাসের প্রতিটি প্রশ্নের উত্তর।';

  @override
  String get welcomeSubtitle =>
      'পরীক্ষা, ফি আর নিয়মকানুন — আপনার বিশ্ববিদ্যালয়ের নিজস্ব ডকুমেন্ট থেকে, সঙ্গে উৎসের পাতা।';

  @override
  String get welcomeLogIn => 'লগ ইন করুন';

  @override
  String get authSignInTitle => 'সাইন ইন করুন';

  @override
  String get authSignInSubtitle => 'প্রতিষ্ঠানের দেওয়া ইমেইল দিয়ে সাইন ইন করুন।';

  @override
  String get authEmailLabel => 'ইমেইল';

  @override
  String get authPasswordLabel => 'পাসওয়ার্ড';

  @override
  String get authPasswordHelper => 'কমপক্ষে ৮টি অক্ষর।';

  @override
  String get authEmailInvalid =>
      'ইমেইলটি অসম্পূর্ণ। ডোমেইনসহ লিখুন, যেমন name@green.edu.bd';

  @override
  String get authWrongPassword =>
      'পাসওয়ার্ডটি এই ইমেইলের সাথে মিলছে না। আবার দেখে নিন, অথবা পাসওয়ার্ড রিসেট করুন।';

  @override
  String get authResetPassword => 'পাসওয়ার্ড রিসেট করুন';

  @override
  String get authSignInAction => 'সাইন ইন করুন';

  @override
  String get authSigningIn => 'সাইন ইন হচ্ছে';

  @override
  String get authOr => 'অথবা';

  @override
  String get authJoinWithInvite => 'আমন্ত্রণ কোড দিয়ে যোগ দিন';

  @override
  String get authNewHere => 'বুলেটিনে নতুন?';

  @override
  String get authCreateAccountLink => 'অ্যাকাউন্ট খুলুন';

  @override
  String get authTermsPrefix => 'সাইন ইন করলে আপনি আমাদের ';

  @override
  String get authTermsLink => 'ব্যবহারের শর্তাবলিতে';

  @override
  String get authTermsSuffix => ' সম্মত হচ্ছেন।';

  @override
  String get createTitle => 'অ্যাকাউন্ট খুলুন';

  @override
  String get createSubtitle => 'প্রথম প্রশ্ন করার আগে ইমেইল নিশ্চিত করতে হবে।';

  @override
  String get createNameLabel => 'পুরো নাম';

  @override
  String get createAction => 'অ্যাকাউন্ট খুলুন';

  @override
  String get createHaveAccount => 'আগেই অ্যাকাউন্ট আছে?';

  @override
  String get createSignInLink => 'সাইন ইন করুন';

  @override
  String get privacyPrefix => 'আরও জানতে আমাদের ';

  @override
  String get privacyLink => 'গোপনীয়তা নীতি';

  @override
  String get privacySuffix => ' দেখুন।';

  @override
  String get checkTitle => 'ইমেইল দেখুন';

  @override
  String get checkHeading => 'আপনার অ্যাকাউন্ট তৈরি হয়েছে';

  @override
  String get checkResend => 'লিংক আবার পাঠান';

  @override
  String get checkDifferentEmail => 'অন্য ইমেইল ব্যবহার করুন';

  @override
  String get authEmailHint => 'you@green.edu.bd';

  @override
  String authResetSent(String email) {
    return '$email দিয়ে অ্যাকাউন্ট থাকলে রিসেট লিংক পাঠানো হয়েছে।';
  }

  @override
  String get authResetNeedsEmail => 'ওপরে ইমেইল লিখে তারপর পাসওয়ার্ড রিসেট চাপুন।';

  @override
  String get authErrorNotConfirmed =>
      'আগে ইমেইল নিশ্চিত করুন। আমাদের পাঠানো লিংকটি খুলুন।';

  @override
  String get authErrorAlreadyRegistered => 'এই ইমেইলে আগেই অ্যাকাউন্ট আছে। সাইন ইন করুন।';

  @override
  String get authErrorWeakPassword => 'আরও শক্ত পাসওয়ার্ড দিন।';

  @override
  String get authErrorRateLimited =>
      'অনেকবার চেষ্টা হয়েছে। এক মিনিট অপেক্ষা করে আবার চেষ্টা করুন।';

  @override
  String createPasswordShort(int count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String countString = countNumberFormat.format(count);

    return 'কমপক্ষে ৮টি অক্ষর দিন। এখানে আছে $countStringটি।';
  }

  @override
  String checkBody(String email) {
    return '$email ঠিকানায় একটি নিশ্চিতকরণ লিংক পাঠানো হয়েছে। চালিয়ে যেতে এই ফোনেই লিংকটি খুলুন।';
  }

  @override
  String get checkResent => 'নতুন লিংক পাঠানো হয়েছে।';

  @override
  String get newChat => 'নতুন চ্যাট';

  @override
  String get modelMenuTitle => 'এআই মডেল';

  @override
  String modelPillLabel(String name) {
    return 'মডেল: $name';
  }

  @override
  String modelDefault(String maker) {
    return '$maker · ডিফল্ট';
  }

  @override
  String modelLowCost(String maker) {
    return '$maker · দ্রুত, কম খরচ';
  }

  @override
  String modelHighCost(String maker) {
    return '$maker · বেশি দক্ষ, খরচ বেশি';
  }

  @override
  String get settingsProfile => 'প্রোফাইল';

  @override
  String get settingsEmail => 'ইমেইল';

  @override
  String get joinedWithCode => 'যে কোডে যোগ দিয়েছেন';

  @override
  String get documentsRowSub => 'ডকুমেন্ট প্রকাশ ও পর্যালোচনা';

  @override
  String get displayNameSaved => 'সংরক্ষিত';

  @override
  String get attachCameraSub => 'রুটিন, রেজিস্ট্রেশন স্লিপ বা নোটিশ';

  @override
  String get attachGallerySub => 'JPG বা PNG';

  @override
  String get attachFilesSub => 'PDF';

  @override
  String get attachLimitBefore => 'প্রতিটি ফাইল সর্বোচ্চ ';

  @override
  String get attachLimitAfter => '।';

  @override
  String get sheetHandleLabel => 'বন্ধ করুন';

  @override
  String get sourcesHeader => 'উৎস';

  @override
  String get stepSearching => 'ডকুমেন্ট খোঁজা হচ্ছে…';

  @override
  String stepReadCourses(int count) {
    return 'রুটিন থেকে $countটি কোর্স পড়া হয়েছে';
  }

  @override
  String get offlineBanner => 'আপনি অফলাইনে আছেন। উত্তর পেতে ইন্টারনেট সংযোগ লাগবে।';

  @override
  String get notSentOffline => 'পাঠানো যায়নি। আপনি অফলাইনে আছেন।';

  @override
  String get retryMessage => 'আবার পাঠান';

  @override
  String sourceExpandLabel(String title, String page) {
    return '$title, $page';
  }
}
