/// The app's ThemeData, assembled from tokens. DESIGN §2, §3.
///
/// Everything here reads from `tokens.dart` and `typography.dart`. If a colour
/// or a text style is needed and is not in those files, it belongs in those
/// files first (CLAUDE.md).
///
/// Light only. Dark mode is deferred (TASKS.md), and a half-done dark palette
/// would fail the contrast audit in DESIGN §8 rather than pass it early.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

export 'chrome.dart';
export 'tokens.dart';
export 'typography.dart';

ThemeData buildBulletinTheme() {
  const scheme = ColorScheme.light(
    primary: BulletinColors.accent,
    onPrimary: BulletinColors.paper,
    primaryContainer: BulletinColors.accentSoft,
    onPrimaryContainer: BulletinColors.ink,
    secondary: BulletinColors.accent,
    onSecondary: BulletinColors.paper,
    surface: BulletinColors.paper,
    onSurface: BulletinColors.ink,
    onSurfaceVariant: BulletinColors.inkMuted,
    error: BulletinColors.danger,
    onError: BulletinColors.paper,
    outline: BulletinColors.inkFaint,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // The ambient gradient is painted by AmbientBackground behind everything,
    // so scaffolds are transparent rather than white.
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: Fonts.latin,
    textTheme: const TextTheme(
      titleLarge: BulletinText.screenTitle,
      titleMedium: BulletinText.sourceTitle,
      bodyLarge: BulletinText.messageBody,
      bodyMedium: BulletinText.sourceSnippet,
      labelLarge: BulletinText.sectionLabel,
      labelSmall: BulletinText.meta,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: BulletinText.screenTitle,
      iconTheme: IconThemeData(color: BulletinColors.ink),
    ),
    cardTheme: const CardThemeData(
      color: BulletinColors.paper,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: Radii.cardAll),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BulletinColors.accent,
        foregroundColor: BulletinColors.paper,
        // 48 minimum, no exceptions (DESIGN §3).
        minimumSize: const Size(Sizes.minTouchTarget, Sizes.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        shape: const RoundedRectangleBorder(borderRadius: Radii.chipAll),
        textStyle: BulletinText.sourceTitle,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: BulletinColors.accent,
        minimumSize: const Size(Sizes.minTouchTarget, Sizes.minTouchTarget),
        textStyle: BulletinText.sourceTitle,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BulletinColors.paper,
      hintStyle: BulletinText.messageBody.copyWith(color: BulletinColors.inkFaint),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      border: const OutlineInputBorder(
        borderRadius: Radii.chipAll,
        borderSide: BorderSide(color: BulletinColors.hairline),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: Radii.chipAll,
        borderSide: BorderSide(color: BulletinColors.hairline),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: Radii.chipAll,
        borderSide: BorderSide(color: BulletinColors.accent, width: 2),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: BulletinColors.hairline,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: BulletinColors.ink,
      contentTextStyle: TextStyle(
        fontFamily: Fonts.latin,
        fontSize: 14,
        height: 1.6,
        color: BulletinColors.paper,
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// The fixed app background: warm [BulletinColors.canvas] with three static
/// glows (handoff README §1, "Crystal glass": glass needs colour behind it).
///
/// It sits behind the whole app and never scrolls, which is why it lives above
/// the Navigator rather than inside a screen: a background rebuilt per route
/// would flicker at every push. Never animated, for the same reason and for
/// frame budget on a mid-range phone (DESIGN §7).
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: BulletinColors.canvas),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [for (final glow in _glows) _Glow(glow)],
            ),
          ),
          child,
        ],
      ),
    );
  }

  /// The prototype's Home background: centre (as a fraction of the screen),
  /// radii (as fractions of width and height) and colour.
  static const _glows = <({Offset at, Size radius, Color color})>[
    (at: Offset(0.18, 0.04), radius: Size(0.60, 0.22), color: BulletinColors.glowPeach),
    (at: Offset(0.92, 0.06), radius: Size(0.45, 0.18), color: BulletinColors.glowApricot),
    (at: Offset(0.50, 1.00), radius: Size(0.80, 0.26), color: BulletinColors.glowEmber),
  ];
}

/// One elliptical radial glow. CSS `radial-gradient(60% 22% at 18% 4%, ...)`
/// is an ellipse; Flutter's [RadialGradient] is a circle, so the circle is
/// drawn in a box with the ellipse's proportions and positioned to match.
class _Glow extends StatelessWidget {
  const _Glow(this.glow);

  final ({Offset at, Size radius, Color color}) glow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final rx = glow.radius.width * box.maxWidth;
        final ry = glow.radius.height * box.maxHeight;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: glow.at.dx * box.maxWidth - rx,
              top: glow.at.dy * box.maxHeight - ry,
              width: rx * 2,
              height: ry * 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [glow.color, glow.color.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
