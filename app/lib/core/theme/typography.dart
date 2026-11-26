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
  static const bold = <FontVariation>[FontVariation('wght', 700)];
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

  /// 28 / 600 / 1.1, white — the splash wordmark, animated letter by letter.
  static const splashWordmark = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 28,
    height: 1.1,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.white,
  );

  /// 14 / 400 / 1.6, white — the splash tagline. Resolve it per string: the
  /// Bangla tagline needs the Bengali face.
  static const splashTagline = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.6,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.white,
  );

  // --- Auth (handoff README §1, "Typography"; prototype `ab.*`) ---------

  /// 32 / 700 / 1.15, −0.015em — "Sign in" on the orange header.
  /// A canvas page's title (Join): 30 / 1.15 / 700, −0.015em, and its
  /// 15 / 1.55 subtitle (CHANGES.md).
  static const canvasTitle = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 30,
    height: 1.15,
    letterSpacing: -0.45,
    fontWeight: FontWeight.w700,
    fontVariations: Weights.bold,
    color: BulletinColors.ink,
  );
  static const canvasSubtitle = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 15,
    height: 1.55,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.muted,
  );

  /// Home: the greeting 28 / 1.3 / 600, −0.01em, centred; the institution
  /// line 14 / 1.6 muted; a chip's label 14 / 1.6 / 500.
  static const homeGreeting = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 28,
    height: 1.3,
    letterSpacing: -0.28,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.ink,
  );
  static const homeNote = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.6,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.muted,
  );
  static const chipLabel = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.6,
    fontWeight: FontWeight.w500,
    fontVariations: Weights.medium,
    color: BulletinColors.ink,
  );
  static const pillLabel = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.ink,
  );

  /// Welcome: 30 / 1.25 / 700, −0.01em (README §3).
  /// The chat pill's "Bulletin" line: 16/600.
  static const pillTitle = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.ink,
  );

  /// The chat pill's model line, and a model row's description: 12/1.4 muted.
  static const pillCaption = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 12,
    height: 1.4,
    fontVariations: Weights.regular,
    color: BulletinColors.muted,
  );

  /// The model menu's "AI MODEL" overline: 12/600, +.04em, upper case.
  static const menuOverline = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 12,
    height: 1.3,
    letterSpacing: 0.48,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.muted,
  );

  /// A model row's name: 15/600.
  static const menuRowTitle = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.ink,
  );

  /// An attach-sheet source's name: 16/500/1.45.
  static const sourceRowTitle = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 16,
    height: 1.45,
    fontWeight: FontWeight.w500,
    fontVariations: Weights.medium,
    color: BulletinColors.ink,
  );

  /// Settings' language switch: 16/600; ink when on, muted when off.
  static const segmentLabel = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.ink,
  );

  /// Settings' small field label ("Display name"): 12/500 muted.
  static const settingsLabel = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w500,
    fontVariations: Weights.medium,
    color: BulletinColors.muted,
  );

  /// A Settings row's text (email, role): 14/1.5.
  static const settingsRow = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.5,
    fontVariations: Weights.regular,
    color: BulletinColors.ink,
  );

  /// A Settings card's title (institution, Documents): 16/600/1.45.
  static const settingsCardTitle = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 16,
    height: 1.45,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.ink,
  );

  /// The invite code in Settings: mono 12, +1 px.
  static const settingsCode = TextStyle(
    fontFamily: Fonts.mono,
    fontSize: 12,
    height: 1.4,
    letterSpacing: 1,
    color: BulletinColors.ink,
  );

  static const welcomeTitle = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 30,
    height: 1.25,
    letterSpacing: -0.3,
    fontWeight: FontWeight.w700,
    fontVariations: Weights.bold,
    color: BulletinColors.ink,
  );
  static const welcomeSubtitle = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 15,
    height: 1.6,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.muted,
  );
  static const authTitle = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 32,
    height: 1.15,
    letterSpacing: -0.48,
    fontWeight: FontWeight.w700,
    fontVariations: Weights.bold,
    color: BulletinColors.ink,
  );

  /// 14 / 400 / 1.5 on orange.
  static const authSubtitle = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.brandInk,
  );

  /// 26 / 700 / 1.25 — create account, check email.
  static const stepTitle = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 26,
    height: 1.25,
    fontWeight: FontWeight.w700,
    fontVariations: Weights.bold,
    color: BulletinColors.ink,
  );

  /// 13 / 400 / 1.6, muted.
  static const stepSubtitle = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 13,
    height: 1.6,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.muted,
  );

  /// 13 / 600 / 1.4 — a field's label.
  static const fieldLabel = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.ink,
  );

  /// 13 / 500 / 1.4 — a field's label on the create step.
  static const fieldLabelQuiet = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w500,
    fontVariations: Weights.medium,
    color: BulletinColors.ink,
  );

  /// 16 / 400 — what the user types. 16 keeps iOS from zooming.
  static const fieldInput = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.ink,
  );

  /// 12 / 400 / 1.5, muted — helper under a field.
  static const fieldHelper = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 12,
    height: 1.5,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.muted,
  );

  /// 14 / 400 / 1.5, error red.
  static const fieldError = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.error,
  );

  /// 14 / 400 / 1.55 — the text inside an error or status box.
  static const noticeBody = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.55,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.ink,
  );

  /// 16 / 600 — primary and secondary buttons.
  static const buttonLabel = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.white,
  );

  /// 13 / 600 / 1.4 — "Reset password".
  static const inlineLink = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.brandText,
  );

  /// 14 / 400 / 1.5, muted — "New to Bulletin?".
  static const footer = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.muted,
  );

  /// 12 / 400 / 1.6, muted — the terms line.
  static const legal = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 12,
    height: 1.6,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.muted,
  );

  /// 17 / 600 / 1.4 — the heading inside a status card.
  static const cardHeading = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 17,
    height: 1.4,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.ink,
  );

  /// 14 / 400 / 1.65 — body inside a status card.
  static const cardBody = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.65,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.ink,
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
  /// The invite code as typed: mono so O and 0 differ, 20 / 500, tracked
  /// 3 px (CHANGES.md, Join).
  static const inviteCode = TextStyle(
    fontFamily: Fonts.mono,
    fontSize: 20,
    height: 1.3,
    letterSpacing: 3,
    fontWeight: FontWeight.w500,
    color: BulletinColors.ink,
  );
  static const courseCode = TextStyle(
    fontFamily: Fonts.mono,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: BulletinColors.ink,
  );

  /// The user's bubble: 15 / 400 / 1.55.
  static const userBubbleText = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 15,
    height: 1.55,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.ink,
  );

  /// An answer: 16 / 400 / 1.65, no bubble (CHANGES.md).
  static const answerBody = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 16,
    height: 1.65,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.ink,
  );

  /// "Bulletin" over an answer: 13 / 600 / 1.
  static const assistantName = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 13,
    height: 1,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.ink,
  );

  /// A working step, and the not-found text and a snippet: 14 / 400 / 1.45.
  static const stepLabel = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.inkBody,
  );

  /// "SOURCES": 12 / 600 / 1, +.04em, uppercase.
  static const sourcesHeader = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 12,
    height: 1,
    letterSpacing: 0.48,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.muted,
  );

  /// A source's number, page and language pills: 12 / 500, mono.
  static const sourceMono = TextStyle(
    fontFamily: Fonts.mono,
    fontSize: 12,
    height: 1,
    fontWeight: FontWeight.w500,
    color: BulletinColors.inkBody,
  );

  /// An opened source's snippet: 14 / 400 / 1.65.
  static const snippet = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.65,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.inkBody,
  );

  /// "Open page 3" on its orange pill, "N more sources": 14 / 600 and 13 / 600.
  static const pillAction = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.white,
  );
  static const moreSources = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
    fontVariations: Weights.semiBold,
    color: BulletinColors.brandText,
  );

  /// The not-found text: 15 / 400 / 1.6.
  static const notFoundText = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 15,
    height: 1.6,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
    color: BulletinColors.inkBody,
  );

  /// The offline banner: 14 / 400 / 1.5.
  static const bannerText = TextStyle(
    fontFamily: Fonts.latin,
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
    fontVariations: Weights.regular,
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
