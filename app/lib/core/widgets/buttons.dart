/// Buttons from the redesign handoff (README §2.3, §5).
///
/// Built on [InkWell] for focus, keyboard activation and semantics, with the
/// ripple switched off: the handoff's feedback is the press scale
/// (MOTION.md §4.1), not a splash.
library;

import 'package:flutter/material.dart';

import '../motion/motion_widgets.dart';
import '../theme/theme.dart';
import 'crystal_glass.dart';
import 'line_icons.dart';

/// Two sizes appear in the handoff: 56/18 on the sign-in card, 54/16 on the
/// create and check steps.
enum ButtonSize { large, regular }

extension on ButtonSize {
  double get height => this == ButtonSize.large ? 56 : 54;
  BorderRadius get radius =>
      this == ButtonSize.large ? BrandRadii.button : BrandRadii.buttonCompact;
}

/// The orange primary action.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.busyLabel,
    this.trailing,
    this.leading,
    this.size = ButtonSize.large,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Shows a spinner and ignores taps. [busyLabel] replaces [label] if given.
  final bool busy;
  final String? busyLabel;
  final LineGlyph? trailing;
  final LineGlyph? leading;
  final ButtonSize size;

  @override
  Widget build(BuildContext context) {
    final text = busy ? (busyLabel ?? label) : label;
    final enabled = onPressed != null && !busy;

    return _ButtonShell(
      size: size,
      color: BulletinColors.brandStrong,
      shadow: size == ButtonSize.large ? Lifts.accentButton : BrandLifts.accentButtonSoft,
      onPressed: enabled ? onPressed : null,
      label: text,
      busy: busy,
      children: [
        if (busy)
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: BulletinColors.white),
          )
        else if (leading case final glyph?)
          LineIcon(glyph, color: BulletinColors.white, strokeWidth: 2),
        Flexible(child: _Label(text, color: BulletinColors.white)),
        if (!busy && trailing != null)
          LineIcon(trailing!, color: BulletinColors.white, size: 18, strokeWidth: 2),
      ],
    );
  }
}

/// The peach secondary action, with a leading icon.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    required this.label,
    required this.onPressed,
    this.leading,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final LineGlyph? leading;

  @override
  Widget build(BuildContext context) {
    return _ButtonShell(
      size: ButtonSize.large,
      color: BulletinColors.peachSoft,
      onPressed: onPressed,
      label: label,
      children: [
        if (leading case final glyph?) LineIcon(glyph, color: BulletinColors.brandDeep),
        Flexible(child: _Label(label, color: BulletinColors.ink)),
      ],
    );
  }
}

/// The square back button. On orange it is white .9 at 44px; on canvas it is
/// white at 48px with a hairline shadow.
class BackSquareButton extends StatelessWidget {
  const BackSquareButton({
    required this.onPressed,
    required this.semanticLabel,
    this.onBrand = false,
    this.size = 48,
    super.key,
  });

  final VoidCallback onPressed;
  final String semanticLabel;

  /// The white square's side: 48 on the old canvas steps, 44 on Join
  /// (CHANGES.md). The tap target stays 48 either way.
  final double size;

  /// On the orange header: 44 px crystal glass (CHANGES.md, Sign in).
  /// Otherwise 48 px white with a hairline shadow.
  final bool onBrand;

  @override
  Widget build(BuildContext context) {
    final icon = LineIcon(LineIcons.back, color: BulletinColors.ink, strokeWidth: 2);
    final square = onBrand
        ? SizedBox.square(
            dimension: 44,
            child: CrystalGlass(child: Center(child: icon)),
          )
        : Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              color: BulletinColors.white,
              borderRadius: BrandRadii.square,
              boxShadow: BrandLifts.hairline,
            ),
            alignment: Alignment.center,
            child: icon,
          );

    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: PressScale.icon(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BrandRadii.square,
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            // The visible square may be 44; the hit box is never under 48.
            child: SizedBox.square(
              dimension: Sizes.minTouchTarget,
              child: Center(child: square),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bare text action: "Reset password", "Create account".
class TextLink extends StatelessWidget {
  const TextLink({required this.label, required this.onPressed, this.style, super.key});

  final String label;
  final VoidCallback? onPressed;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final resolved = BulletinText.resolve(style ?? BulletinText.inlineLink, label);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onPressed,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        borderRadius: Radii.badgeAll,
        // Text links sit inline, so their hit box is padded out to the 48
        // minimum vertically without moving the text.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.minTouchTarget),
          child: Center(
            widthFactor: 1,
            child: Text(label, style: resolved, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

class _ButtonShell extends StatelessWidget {
  const _ButtonShell({
    required this.size,
    required this.color,
    required this.onPressed,
    required this.label,
    required this.children,
    this.shadow,
    this.busy = false,
  });

  final ButtonSize size;
  final Color color;
  final VoidCallback? onPressed;
  final String label;
  final List<Widget> children;
  final List<BoxShadow>? shadow;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      liveRegion: busy,
      excludeSemantics: true,
      child: PressScale.button(
        enabled: onPressed != null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: size.radius,
            boxShadow: shadow,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onPressed,
              borderRadius: size.radius,
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: size.height),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.lg,
                    vertical: Space.sm,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 10,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: BulletinText.resolve(BulletinText.buttonLabel.copyWith(color: color), text),
    );
  }
}
