/// A citation, as the terminal SSE event delivers it.
///
/// The backend assembles these from the retrieved chunks rather than parsing
/// them out of the model's prose (app/generate/answer.py), so a `[4]` the model
/// invented has no citation behind it and simply does not render.
library;

class Citation {
  const Citation({
    required this.n,
    required this.chunkId,
    required this.documentId,
    required this.pageNo,
    required this.lang,
    required this.snippet,
    this.section,
    this.title,
  });

  factory Citation.fromJson(Map<String, dynamic> json) => Citation(
    n: (json['n'] as num?)?.toInt() ?? 0,
    chunkId: (json['chunk_id'] as num?)?.toInt() ?? 0,
    documentId: json['doc_id'] as String? ?? '',
    pageNo: (json['page_no'] as num?)?.toInt() ?? 1,
    // The language of the SOURCE, which may differ from the answer's.
    // That difference is the point (DESIGN §4).
    lang: json['lang'] as String? ?? 'en',
    snippet: json['snippet'] as String? ?? '',
    section: json['section'] as String?,
    title: json['title'] as String?,
  );

  /// The number the answer text refers to: `[1]`, `[2]`.
  final int n;
  final int chunkId;
  final String documentId;
  final int pageNo;

  /// "en" or "bn" — the source's own language.
  final String lang;

  /// Shown verbatim, never translated: translating it away removes the ability
  /// to verify the claim against the page (DESIGN §4).
  final String snippet;

  final String? section;

  /// The document title, when the client has it. Citations arrive with the
  /// document id; the title comes from the documents list or the source
  /// endpoint, so it may be null on first render.
  final String? title;

  bool get isBangla => lang == 'bn';

  Citation withTitle(String? value) => Citation(
    n: n,
    chunkId: chunkId,
    documentId: documentId,
    pageNo: pageNo,
    lang: lang,
    snippet: snippet,
    section: section,
    title: value ?? title,
  );

  static List<Citation> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Citation.fromJson)
        .toList(growable: false);
  }
}
