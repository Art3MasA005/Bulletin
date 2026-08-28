/// Frosted chrome: the pills and bars that sit above content. DESIGN §7.
///
/// Everything here uses a `BackdropFilter`, which is why it all lives in one
/// file: the budget is two per screen, and a reviewer counting them should
/// only have to look in one place. Nothing in this file may be used inside a
/// `ListView` item (CLAUDE.md #11).
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// A 44px-tall frosted pill with a 48px hit box.
class FrostedPill extends StatelessWidget {
  const FrostedPill({
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.padding = const EdgeInsets.symmetric(horizontal: Space.md),
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final pill = ClipRRect(
      borderRadius: Radii.pillAll,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: BlurBudget.sigma, sigmaY: BlurBudget.sigma),
        child: Container(
          height: Sizes.pillHeight,
          padding: padding,
          decoration: BoxDecoration(
            color: BulletinColors.frosted,
            borderRadius: Radii.pillAll,
            border: Border.all(color: BulletinColors.hairline),
          ),
          child: Center(child: child),
        ),
      ),
    );

    if (onTap == null) return pill;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.minTouchTarget),
        child: Material(
          color: Colors.transparent,
          child: InkWell(onTap: onTap, borderRadius: Radii.pillAll, child: pill),
        ),
      ),
    );
  }
}

/// A round frosted button — back chevron, pager arrows.
class FrostedCircle extends StatelessWidget {
  const FrostedCircle({
    required this.icon,
    required this.semanticLabel,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: Sizes.minTouchTarget,
        height: Sizes.minTouchTarget,
        child: Center(
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: BlurBudget.sigma,
                sigmaY: BlurBudget.sigma,
              ),
              child: Material(
                color: BulletinColors.frosted,
                shape: const CircleBorder(
                  side: BorderSide(color: BulletinColors.hairline),
                ),
                child: InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: Sizes.pillHeight,
                    height: Sizes.pillHeight,
                    child: Icon(icon, size: 20, color: BulletinColors.ink),
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

/// The language toggle. It shows the language you would switch TO, which is
/// the only way a one-tap toggle can be self-explanatory.
class LanguagePill extends StatelessWidget {
  const LanguagePill({required this.isBangla, required this.onToggle, super.key});

  final bool isBangla;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final label = isBangla ? 'English' : 'বাংলা';
    return FrostedPill(
      onTap: onToggle,
      semanticLabel: label,
      child: Text(
        label,
        style: BulletinText.resolve(
          BulletinText.sourceTitle.copyWith(fontSize: 14),
          label,
        ),
      ),
    );
  }
}

/// A small mono badge: `EN`, `BN`, `ADMIN`, `TEACHERS`.
class MonoBadge extends StatelessWidget {
  const MonoBadge({
    required this.text,
    required this.color,
    required this.tint,
    super.key,
  });

  final String text;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
      decoration: BoxDecoration(color: tint, borderRadius: Radii.badgeAll),
      child: Text(text.toUpperCase(), style: BulletinText.badge.copyWith(color: color)),
    );
  }
}
