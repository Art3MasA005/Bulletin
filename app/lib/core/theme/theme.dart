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

/// The fixed ambient gradient (DESIGN §3).
///
/// It sits behind the whole app and never scrolls, which is why it lives above
/// the Navigator rather than inside a screen: a gradient rebuilt per route
/// would flicker at every push.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Four radial pools over a warm base, each fading out by ~60% of its
    // radius -- the handoff spec's mesh gradient. One painted layer, never
    // animated: it is atmosphere, and an animated background would both fight
    // the source card and cost frames on a mid-range phone (DESIGN §7).
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFFCFAFB)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final pool in _pools)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: pool.$1,
                  radius: 0.95,
                  colors: [pool.$2, pool.$2.withValues(alpha: 0)],
                  stops: const [0, 0.6],
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }

  static const _pools = <(Alignment, Color)>[
    (Alignment.topLeft, Color(0xFFEFE9F7)), // lavender
    (Alignment.topRight, Color(0xFFFDEEF1)), // blush
    (Alignment.bottomLeft, Color(0xFFE8F3EE)), // mint
    (Alignment.bottomRight, Color(0xFFFDF7EC)), // cream
  ];
}
