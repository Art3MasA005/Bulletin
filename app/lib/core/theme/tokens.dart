/// Design tokens. DESIGN §3, and `docs/design/handoff/README.md` §1, which
/// holds the final values.
///
/// CLAUDE.md: "Colors and text styles from core/theme tokens only. No inline
/// Color(0xFF...)." Every hex in the app lives in this file, so a contrast
/// audit (DESIGN §8) has one place to look and one place to fix.
library;

import 'package:flutter/widgets.dart';

/// The palette.
///
/// Two groups. The **handoff palette** carries the names from the redesign
/// handoff (README §1) verbatim, so a value can be checked against the spec
/// by name. The **semantic aliases** below it are the names the screens built
/// before the redesign use; each now points into the handoff palette, so those
/// screens recolour coherently and are rebuilt one at a time rather than all
/// at once.
abstract final class BulletinColors {
  // --- Handoff palette -----------------------------------------------------

  /// Splash, welcome and sign-in header background; the logo tile.
  static const brand = Color(0xFFFF7A2E);

  /// Primary buttons, focus border, links, active icons.
  static const brandStrong = Color(0xFFF26314);

  /// Icons on peach.
  static const brandDeep = Color(0xFFE0570F);

  /// Text links on white ("Reset password", "Create account").
  static const brandText = Color(0xFFB84A0B);

  /// Decorative clouds on orange.
  static const cloud = Color(0xFFFFA566);

  /// The drifting clouds' vertical gradients, top → bottom (CHANGES.md,
  /// "drifting clouds"): lighter on top, `cloud`-family at the bottom.
  static const cloudFarTop = Color(0xFFFFD6B6);
  static const cloudFarBottom = Color(0xFFFFB585);
  static const cloudNearTop = Color(0xFFFFC9A3);
  static const cloudNearBottom = cloud;
  static const cloudMidTop = Color(0xFFFFC49C);
  static const cloudMidBottom = Color(0xFFFFA86C);
  static const cloudSmallBottom = Color(0xFFFFAB70);

  /// The Home orb's radial layers (prototype `home.orb`).
  static const orbWhite = Color(0xF2FFFFFF); // white .95
  static const orbWhiteHalf = Color(0x8CFFFFFF); // white .55
  static const orbWhiteCore = Color(0xD9FFFFFF); // white .85
  static const orbPeach = Color(0x52FFA566); // rgba(255,165,102,.32)
  static const orbEdge = Color(0x29FF7A2E); // rgba(255,122,46,.16)
  static const orbRingA = Color(0x38FF8C46); // rgba(255,140,70,.22)
  static const orbRingB = Color(0x2EFF8C46); // rgba(255,140,70,.18)
  static const orbRingC = Color(0x3DFFAA6E); // rgba(255,170,110,.24)

  /// The composer's attach button: radial white → peach → this.
  static const attachGlow = Color(0xFFFFD3B5);

  // Model picker (README §1 "Model tints"): icon tile background / ink, by
  // the model's maker. DeepSeek has no handoff tint; it takes Llama's, the
  // handoff's "other" model.
  static const modelAnthropicTint = Color(0xFFFFE9DB);
  static const modelAnthropicInk = Color(0xFFE0570F);
  static const modelOpenAiTint = Color(0xFFE3F2EC);
  static const modelOpenAiInk = Color(0xFF2F8F6E);
  static const modelGoogleTint = Color(0xFFE6ECFB);
  static const modelGoogleInk = Color(0xFF3A5BC7);
  static const modelOtherTint = Color(0xFFF1E9F7);
  static const modelOtherInk = Color(0xFF7A4AA0);

  /// The model menu's denser glass: white .94 → .84.
  static const menuFillTop = Color(0xF0FFFFFF);
  static const menuFillBottom = Color(0xD6FFFFFF);

  /// Behind the open model menu: rgba(60,25,5,.10).
  static const menuScrim = Color(0x1A3C1905);

  /// Over the screen a push slides away from: black at .08.
  static const pushScrim = Color(0x14000000);

  /// The picked row: peach at .75.
  static const menuRowPicked = Color(0xBFFFE9DB);

  /// The send button's icon while there is nothing to send.
  static const sendInert = Color(0xFFA39A93);

  /// Crystal glass (README §1): the fill's three stops, its border, and the
  /// warm inner glow and hairline.
  static const glassFillTop = Color(0x9EFFFFFF); // white .62
  static const glassFillMid = Color(0x38FFFFFF); // white .22
  static const glassFillEnd = Color(0x66FFFFFF); // white .40
  static const glassBorder = Color(0xF2FFFFFF); // white .95
  static const glassInnerGlow = Color(0x29FF965A); // rgba(255,150,90,.16)
  static const glassHairline = Color(0x1AB45A28); // rgba(180,90,40,.10)

  /// Icon circles, the 4px focus ring, selected rows.
  static const peach = Color(0xFFFFE9DB);

  /// Secondary button background.
  static const peachSoft = Color(0xFFFFF1E8);

  /// Attach-button gradient end.
  static const peachLine = Color(0xFFFFD3B5);

  /// Primary text.
  static const ink = Color(0xFF161412);

  /// Body text on cards.
  static const inkSoft = Color(0xFF3B342F);

  /// Secondary text and placeholders.
  static const muted = Color(0xFF6B625C);

  /// Input leading icons.
  static const mutedIcon = Color(0xFF8A7F78);

  /// The app background, a warm beige.
  static const canvas = Color(0xFFF7F1EC);

  /// Input fill while unfocused.
  static const field = Color(0xFFF7F4F1);

  /// "Or" divider lines.
  static const divider = Color(0xFFEEE8E3);

  /// The rule inside a white card (Join): a shade warmer than [divider].
  static const dividerCard = Color(0xFFF0EAE5);

  /// Cards and sheets.
  static const white = Color(0xFFFFFFFF);

  /// Ready and uploaded check badges, confirmed extraction.
  static const success = Color(0xFF2F8F6E);

  /// Field errors and failed ingestion.
  static const error = Color(0xFFC0392B);

  /// The error box behind a form-level error.
  static const errorSurface = Color(0xFFFDF0EE);

  /// Low confidence, needs review. The chip fill is [warnTint].
  static const warn = Color(0xFFB8701E);

  /// English-sourced content: the source-language tag and the source card's
  /// left rule when the SOURCE is English (DESIGN §4).
  static const srcEn = Color(0xFF2F6FB5);

  /// Bangla-sourced content.
  static const srcBn = Color(0xFFC4456B);

  /// Supporting text on brand orange (the sign-in subtitle).
  static const brandInk = Color(0xFF3B1E0C);

  /// A border that marks something present but inert (rgba(22,20,18,.12)).
  static const inertBorder = Color(0x1F161412);

  /// The panda's line work drawn in code (the ledge, the blink lids). Pure
  /// black, because it has to match the black already in the panda PNGs.
  static const pandaLine = Color(0xFF000000);

  /// The thin arc across the splash sky (white .55).
  static const skyLine = Color(0x8CFFFFFF);

  /// The warm glows painted over [canvas] behind Home and Documents. Glass
  /// needs colour behind it; these are static and never animated.
  static const glowPeach = Color(0x73FFA86E); // rgba(255,168,110,.45)
  static const glowApricot = Color(0x8CFFC896); // rgba(255,200,150,.55)
  static const glowEmber = Color(0x52FF965A); // rgba(255,150,90,.32)

  // --- Semantic aliases (pre-redesign names) --------------------------------

  static const inkMuted = muted;
  static const inkFaint = mutedIcon;
  static const paper = white;
  static const accent = brandStrong;
  static const accentSoft = peach;
  static const accentHover = brandDeep;
  static const bnMarker = srcBn;
  static const enMarker = srcEn;
  static const danger = error;

  /// Hairlines, all derived from [ink] so they sit in the same family. The
  /// not-found border is heavier on purpose, so the card does not read as an
  /// answer.
  static const hairline = Color(0x0F161412); // 0.06 — on paper
  static const hairlineInput = Color(0x17161412); // 0.09 — inputs
  static const hairlineStrong = Color(0x29161412); // 0.16 — not-found card

  /// Frosted chrome. The ONLY surfaces allowed a BackdropFilter (DESIGN §7):
  /// fixed chrome, never a list item.
  static const frosted = Color(0xB8FFFFFF); // white 0.72 — top bars, pills
  static const frostedComposer = Color(0xD1FFFFFF); // white 0.82
  static const frostedSoft = Color(0x9EFFFFFF); // white 0.62 — quiet chips

  /// Neutral chip fill on paper.
  static const chipFill = Color(0x08161412); // 0.03
  static const chipFillStrong = Color(0x0D161412); // 0.05

  /// Scrim behind a bottom sheet: rgba(22,20,18,.36), from the prototype.
  static const scrim = Color(0x5C161412);

  /// 12–14% tints, for badges and status circles.
  static const bnTint = Color(0x1FC4456B);
  static const enTint = Color(0x1F2F6FB5);
  static const successTint = Color(0x242F8F6E);
  static const warnTint = Color(0x1FB8701E); // rgba(184,112,30,.12)
  static const dangerTint = Color(0x1FC0392B);
  static const accentTint = Color(0x1FF26314);

  /// A chip or button that is present but inert (nothing to send yet).
  static const inert = Color(0x38161412); // 0.22
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

  /// The primary action, tinted with the brand rather than black:
  /// `0 10 24 rgba(242,99,20,.28)` (handoff README §1).
  static const accentButton = <BoxShadow>[
    BoxShadow(color: Color(0x47F26314), blurRadius: 24, offset: Offset(0, 10)),
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

/// Shadows from the redesign handoff (README §1, "Shadows").
abstract final class BrandLifts {
  /// Crystal glass's outer shadow: `0 10 26 -6 rgba(170,80,25,.18)`,
  /// `0 2 4 rgba(170,80,25,.06)`.
  static const glass = <BoxShadow>[
    BoxShadow(
      color: Color(0x2EAA5019),
      blurRadius: 26,
      spreadRadius: -6,
      offset: Offset(0, 10),
    ),
    BoxShadow(color: Color(0x0FAA5019), blurRadius: 4, offset: Offset(0, 2)),
  ];

  /// A bottom sheet: `0 -8 32 rgba(22,20,18,.14)`.
  static const sheet = <BoxShadow>[
    BoxShadow(color: Color(0x24161412), blurRadius: 32, offset: Offset(0, -8)),
  ];

  /// The model menu: `0 24 48 -12 rgba(120,50,10,.28)`.
  static const menu = <BoxShadow>[
    BoxShadow(
      color: Color(0x47783210),
      blurRadius: 48,
      spreadRadius: -12,
      offset: Offset(0, 24),
    ),
  ];

  /// The smaller primary button: `0 8 20 rgba(242,99,20,.25)`.
  static const accentButtonSoft = <BoxShadow>[
    BoxShadow(color: Color(0x40F26314), blurRadius: 20, offset: Offset(0, 8)),
  ];

  /// The sign-in card rising over the orange header: `0 -6 24 rgba(120,40,0,.12)`.
  static const authCard = <BoxShadow>[
    BoxShadow(color: Color(0x1F782800), blurRadius: 24, offset: Offset(0, -6)),
  ];

  /// A white card on canvas (Join): `0 1 2 rgba(22,20,18,.05)`,
  /// `0 12 32 -16 rgba(22,20,18,.12)`.
  static const canvasCard = <BoxShadow>[
    BoxShadow(color: Color(0x0D161412), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(
      color: Color(0x1F161412),
      blurRadius: 32,
      spreadRadius: -16,
      offset: Offset(0, 12),
    ),
  ];

  /// A white surface on canvas: `0 1 2 rgba(22,20,18,.06)`.
  static const hairline = <BoxShadow>[
    BoxShadow(color: Color(0x0F161412), blurRadius: 2, offset: Offset(0, 1)),
  ];
}

/// Radii from the redesign handoff (README §1, "Radii").
abstract final class BrandRadii {
  static const field = BorderRadius.all(Radius.circular(16));
  static const fieldCompact = BorderRadius.all(Radius.circular(14));
  static const button = BorderRadius.all(Radius.circular(18));
  static const buttonCompact = BorderRadius.all(Radius.circular(16));
  static const square = BorderRadius.all(Radius.circular(14));
  static const notice = BorderRadius.all(Radius.circular(14));
  static const card = BorderRadius.all(Radius.circular(20));
  static const cardLarge = BorderRadius.all(Radius.circular(24));
  static const authCard = BorderRadius.vertical(top: Radius.circular(32));
  static const welcomeHero = BorderRadius.vertical(bottom: Radius.circular(40));
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
