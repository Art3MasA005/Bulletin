/// What the vision model read from an attachment, before the user confirms it.
///
/// Every course here is a claim, not a fact. PRD §8.3: a misread course code
/// produces a confident wrong exam date, and no downstream stage can catch it
/// — so this type is deliberately awkward to use as an answer. It carries
/// `confirmed`, and the join query is only allowed the confirmed form.
library;

class ExtractedCourse {
  const ExtractedCourse({
    required this.code,
    required this.confidence,
    required this.needsReview,
    this.title,
    this.section,
  });

  factory ExtractedCourse.fromJson(Map<String, dynamic> json) => ExtractedCourse(
    code: json['code'] as String? ?? '',
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    needsReview: json['needs_review'] as bool? ?? false,
    title: json['title'] as String?,
    section: json['section'] as String?,
  );

  final String code;
  final double confidence;

  /// Below the confidence floor: renders with a warn dot and a "check this
  /// one" footnote (DESIGN §5).
  final bool needsReview;

  final String? title;
  final String? section;

  /// "0.62" — shown beside the warning, because a number the user can see is
  /// more honest than a coloured dot alone.
  String get confidenceLabel => confidence.toStringAsFixed(2);

  ExtractedCourse withCode(String value) => ExtractedCourse(
    code: value,
    // A code a human typed is certain by definition; that is what the
    // confirmation step is for.
    confidence: 1,
    needsReview: false,
    title: title,
    section: section,
  );
}

class RoutineExtraction {
  const RoutineExtraction({
    required this.attachmentId,
    required this.courses,
    required this.ok,
    this.semester,
    this.reason = '',
    this.confirmed = false,
  });

  factory RoutineExtraction.fromJson(Map<String, dynamic> json) => RoutineExtraction(
    attachmentId: json['attachment_id'] as String? ?? '',
    semester: json['semester'] as String?,
    ok: json['ok'] as bool? ?? false,
    reason: json['reason'] as String? ?? '',
    confirmed: json['confirmed'] as bool? ?? false,
    courses: [
      for (final raw in (json['courses'] as List? ?? const []))
        if (raw is Map<String, dynamic>) ExtractedCourse.fromJson(raw),
    ],
  );

  final String attachmentId;
  final String? semester;
  final List<ExtractedCourse> courses;
  final bool ok;
  final String reason;

  /// True only after `PATCH /attachments/{id}/confirm` succeeded.
  final bool confirmed;

  List<ExtractedCourse> get flagged =>
      courses.where((course) => course.needsReview).toList(growable: false);

  /// The extraction as it stands after the user pressed confirm.
  RoutineExtraction withConfirmed(List<String> codes) => RoutineExtraction(
    attachmentId: attachmentId,
    semester: semester,
    ok: ok,
    reason: reason,
    confirmed: true,
    courses: [
      for (final code in codes)
        ExtractedCourse(code: code, confidence: 1, needsReview: false),
    ],
  );
}
