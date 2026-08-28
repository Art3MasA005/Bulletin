/// Design tokens. DESIGN §3.
///
/// CLAUDE.md: "Colors and text styles from core/theme tokens only. No inline
/// Color(0xFF...)." Every hex in the app lives in this file, so a contrast
/// audit (DESIGN §8) has one place to look and one place to fix.
library;

import 'package:flutter/widgets.dart';

/// The palette. Names match DESIGN §3 exactly so the doc and the code cannot
/// drift apart in conversation.
abstract final class BulletinColors {
  /// Body text and headings. Near-ink, not gray: the reference sets pale gray
  /// on a pale gradient, and Bangla conjuncts need more contrast than Latin at
  /// the same size (DESIGN §2).
  static const ink = Color(0xFF1C1B2E);

  /// Secondary text, labels, timestamps.
  static const inkMuted = Color(0xFF5A5870);

  /// Placeholders and disabled text. Never used for anything a user must read.
  static const inkFaint = Color(0xFF8C8AA0);

  /// Card and sheet surfaces.
  static const paper = Color(0xFFFDFCFA);

  /// Primary actions, links, focus rings.
  static const accent = Color(0xFF6A5AE0);

  /// Selected states and the user's own message bubble.
  static const accentSoft = Color(0xFFEDE9FD);

  /// Marks Bangla-sourced content. The source card's left rule uses this when
  /// the SOURCE is Bangla, whatever language the answer is in (DESIGN §4).
  static const bnMarker = Color(0xFFC4456B);

  /// Marks English-sourced content.
  static const enMarker = Color(0xFF2F6FB5);

  /// Ready state, confirmed extraction.
  static const success = Color(0xFF2F8F6E);

  /// Low confidence, needs review.
  static const warn = Color(0xFFB8701E);

  /// Failed ingestion, destructive actions.
  static const danger = Color(0xFFC0392B);

  /// The ambient four-stop mesh gradient. Fixed, never scrolling: it is
  /// atmosphere, and it must never compete with a source card.
  static const ambient = <Color>[
    Color(0xFFEFE9F7),
    Color(0xFFFDEEF1),
    Color(0xFFE8F3EE),
    Color(0xFFFDF7EC),
  ];

  /// Pressed / hover state on accent.
  static const accentHover = Color(0xFF5646C9);

  /// Hairlines, all derived from ink so they sit in the same family. The
  /// handoff spec gives three weights and uses them deliberately: the
  /// not-found border is heavier precisely so the card does not read as an
  /// answer.
  static const hairline = Color(0x0F1C1B2E); // 0.06 — on paper
  static const hairlineInput = Color(0x171C1B2E); // 0.09 — inputs
  static const hairlineStrong = Color(0x291C1B2E); // 0.16 — not-found card

  /// Frosted chrome. The ONLY surfaces allowed a BackdropFilter (DESIGN §7):
  /// fixed chrome, never a list item.
  static const frosted = Color(0xB8FFFFFF); // white 0.72 — top bars, pills
  static const frostedComposer = Color(0xD1FFFFFF); // white 0.82
  static const frostedSoft = Color(0x9EFFFFFF); // white 0.62 — quiet chips

  /// Neutral chip fill on paper.
  static const chipFill = Color(0x081C1B2E); // 0.03
  static const chipFillStrong = Color(0x0D1C1B2E); // 0.05

  /// Scrim behind a bottom sheet.
  static const scrim = Color(0x4D1C1B2E); // 0.30

  /// 12–14% tints, for badges and status circles.
  static const bnTint = Color(0x1FC4456B);
  static const enTint = Color(0x1F2F6FB5);
  static const successTint = Color(0x242F8F6E);
  static const warnTint = Color(0x24B8701E);
  static const dangerTint = Color(0x1FC0392B);
  static const accentTint = Color(0x1F6A5AE0);

  /// A chip or button that is present but inert (nothing to send yet).
  static const inert = Color(0x381C1B2E); // 0.22
}

/// The three shadows in the system. Soft and low-contrast: the ambient
/// gradient is the light source, and a hard shadow would fight it.
abstract final class Lifts {
  /// Cards and message bubbles.
  static const card = <BoxShadow>[
    BoxShadow(
      color: Color(0x4D423460),
      blurRadius: 20,
      offset: Offset(0, 8),
      spreadRadius: -16,
    ),
  ];

  /// The composer, which floats above the list.
  static const composer = <BoxShadow>[
    BoxShadow(
      color: Color(0x4D423460),
      blurRadius: 34,
      offset: Offset(0, 14),
      spreadRadius: -22,
    ),
  ];

  /// The primary action. Tinted with the accent, not black.
  static const accentButton = <BoxShadow>[
    BoxShadow(
      color: Color(0xB36A5AE0),
      blurRadius: 24,
      offset: Offset(0, 12),
      spreadRadius: -12,
    ),
  ];

  /// A document page in the source viewer.
  static const page = <BoxShadow>[
    BoxShadow(
      color: Color(0x8C423460),
      blurRadius: 28,
      offset: Offset(0, 10),
      spreadRadius: -18,
    ),
  ];
}

/// The 4px spacing scale (DESIGN §3). Nothing between these values.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
}

/// Corner radii (DESIGN §3).
abstract final class Radii {
  /// Chips and inputs.
  static const chip = Radius.circular(12);

  /// Cards and message bubbles.
  static const card = Radius.circular(20);

  /// Bottom sheets, top corners only.
  static const sheet = Radius.circular(28);

  /// The composer.
  static const composer = Radius.circular(24);

  /// 44px-tall pill chrome.
  static const pill = Radius.circular(22);

  /// Mono badges.
  static const badge = Radius.circular(6);

  /// A rendered document page.
  static const page = Radius.circular(8);

  static const chipAll = BorderRadius.all(chip);
  static const cardAll = BorderRadius.all(card);
  static const composerAll = BorderRadius.all(composer);
  static const pillAll = BorderRadius.all(pill);
  static const badgeAll = BorderRadius.all(badge);
  static const pageAll = BorderRadius.all(page);
  static const sheetTop = BorderRadius.vertical(top: sheet);
}

/// Sizes that are decisions rather than measurements.
abstract final class Sizes {
  /// 48x48 minimum, no exceptions (DESIGN §3). Anything tappable asserts this.
  static const minTouchTarget = 48.0;

  /// The source card's left rule (DESIGN §4).
  static const sourceRule = 3.0;

  /// Two source cards, then "N more sources" (DESIGN §4).
  static const visibleSourceCards = 2;

  /// Assistant messages stretch to the width minus this; user bubbles cap out.
  static const assistantRightInset = 48.0;
  static const userBubbleMaxWidth = 288.0;

  /// Chrome pills are 44px tall by design; the hit box is still 48.
  static const pillHeight = 44.0;

  /// Screen horizontal padding.
  static const screenPadding = 18.0;
  static const sheetPadding = 20.0;
}

/// Motion. Every duration in the app is one of these.
abstract final class Motion {
  /// A message entering the list: rise 14px, fade in.
  static const messageEnter = Duration(milliseconds: 220);

  /// A sheet rising from the bottom.
  static const sheet = Duration(milliseconds: 200);

  /// The streaming caret pulse. Disabled under reduced motion (DESIGN §8).
  static const caretPulse = Duration(milliseconds: 1300);

  /// Spinners.
  static const spinner = Duration(seconds: 1);
}

/// The blur budget, and why it exists. DESIGN §7, CLAUDE.md #11.
///
/// A `BackdropFilter` inside a `ListView` item rebuilds the blur every frame
/// the list scrolls, which drops frames on the mid-range Android this product
/// targets. The rule is enforced by convention and by
/// `test/blur_budget_test.dart`, which fails if a frosted surface appears in a
/// scrollable item.
abstract final class BlurBudget {
  /// Frosted surfaces allowed on one screen.
  static const maxPerScreen = 2;

  /// Sigma for the two that are allowed (the app bar and a bottom sheet).
  static const sigma = 18.0;
}
