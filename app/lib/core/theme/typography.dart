/// Type scale. DESIGN §3.
///
/// Two rules carry most of the weight here:
///
/// 1. **Line height 1.6–1.7 on anything that may render Bangla.** Latin
///    defaults clip descenders and stacked matras. `ক্ষ`, `জ্ঞ`, `ঞ্চ`, `র্ধ্ব`
///    are the four that fail first, and they are in the widget tests.
///
/// 2. **Script-aware family selection.** Anek Latin and Anek Bangla are one
///    superfamily but two files, so a string containing Bangla has to ask for
///    the Bengali face. `BulletinText.of` does that per string rather than per
///    screen, because a single sentence can hold both scripts.
///
/// The fonts are variable, so weight is applied with [FontVariation] rather
/// than by shipping six static cuts.
library;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Bengali block, plus the Bengali digits and signs that sit beside it.
final _bengali = RegExp(r'[ঀ-৿]');

/// Whether this string needs the Bengali face.
///
/// One Bangla character is enough: mixed strings ("CSE 4101 পরীক্ষা") are the
/// normal case in this product, and Anek Bangla covers Latin acceptably while
/// Anek Latin cannot render Bengali at all.
bool hasBangla(String text) => _bengali.hasMatch(text);

abstract final class Fonts {
  static const latin = 'AnekLatin';
  static const bangla = 'AnekBangla';

  /// Data only: page numbers, course codes, file sizes, confidence scores.
  static const mono = 'PlexMono';

  /// The family for a string, chosen by what is actually in it.
  static String forText(String text) => hasBangla(text) ? bangla : latin;
}

/// Weights as variable-font axis values.
abstract final class Weights {
  static const regular = <FontVariation>[FontVariation('wght', 400)];
  static const medium = <FontVariation>[FontVariation('wght', 500)];
  static const semiBold = <FontVariation>[FontVariation('wght', 600)];
}

/// The type scale from DESIGN §3, one getter per row of the table.
abstract final class BulletinText {
  /// 24 / 600 / 1.25
  static const screenTitle = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 24,
    height: 1.25,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.ink,
  );

  /// 18–24 / 600 / 1.3 — a bottom sheet's title.
  static const sheetTitle = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.ink,
  );

  /// 38 / 600 / -0.02em — the wordmark on the sign-in screen.
  static const wordmark = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 38,
    height: 1.1,
    letterSpacing: -0.76,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.ink,
  );

  /// 15 / 400 / 1.6 — the sign-in tagline and other quiet supporting lines.
  static const supporting = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 15,
    height: 1.6,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.inkMuted,
  );

  /// 10 / 500 / +0.06em, mono — the EN/BN and audience badges.
  static const badge = TextStyle(
    fontFamily: Fonts.mono,
    fontSize: 10,
    height: 1.2,
    letterSpacing: 0.6,
    fontWeight: FontWeight.w500,
  );

  /// 12 / 600 / 1.2, uppercase, +0.06em
  static const sectionLabel = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 12,
    height: 1.2,
    letterSpacing: 0.72, // 0.06em at 12px
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.inkMuted,
  );

  /// 16 / 400 / 1.6 — the height is for Bangla matras, not for taste.
  static const messageBody = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 16,
    height: 1.6,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.ink,
  );

  /// 14 / 600 / 1.35
  static const sourceTitle = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.ink,
  );

  /// 14 / 400 / 1.7 — snippets render in the source's own language, so this
  /// one is the most likely of all to hold Bangla.
  static const sourceSnippet = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.7,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.inkMuted,
  );

  /// 14 / 500 / 1.3, mono. Course codes are data.
  static const courseCode = TextStyle(
    fontFamily: Fonts.mono,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: BulletinColors.ink,
  );

  /// 12 / 400 / 1.4
  static const meta = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.inkMuted,
  );

  /// The same style, resolved for the script the text actually uses.
  ///
  /// Call this anywhere the text is user or document content. Static UI labels
  /// come from l10n and can use the styles directly, because the locale
  /// already decided the script.
  static TextStyle resolve(TextStyle style, String text) =>
      hasBangla(text) ? style.copyWith(fontFamily: Fonts.bangla) : style;
}
