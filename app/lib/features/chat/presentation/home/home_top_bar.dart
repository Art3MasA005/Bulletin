/// The floating top bar (prototype `L.main`, y = 56): the model picker pill
/// on the left; on the right, "New chat" once there is a thread, and the
/// round menu button.
///
/// The pill is one of the screen's two BackdropFilters (the composer is the
/// other); the two round buttons are glass without a blur.
library;

import 'package:flutter/material.dart';

import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/crystal_glass.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../../../l10n/app_localizations.dart';
import 'model_picker.dart';

class HomeTopBar extends StatelessWidget {
  const HomeTopBar({
    required this.onMenu,
    this.inThread = false,
    this.onNewChat,
    super.key,
  });

  final VoidCallback onMenu;

  /// True once the first question is asked: the pill changes, and "New
  /// chat" appears (inert while an answer is being written).
  final bool inThread;
  final VoidCallback? onNewChat;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: ModelPicker(inThread: inThread)),
        const SizedBox(width: Space.sm),
        // Both round buttons sit together at the right edge: "New chat" first,
        // then the menu. As separate children of the spaceBetween row, "New
        // chat" would drift to the middle.
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.sm,
          children: [
            // Kept in place while an answer is being written, only inert, so
            // the bar does not jump when the first question is sent.
            if (inThread)
              _RoundButton(
                label: l.newChat,
                onTap: onNewChat,
                child: LineIcon(LineIcons.pencil, color: BulletinColors.ink),
              ),
            _RoundButton(
              label: l.homeMenuLabel,
              onTap: onMenu,
              child: LineIcon(
                LineIcons.dotsVertical,
                color: BulletinColors.ink,
                strokeWidth: 3.6,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.label, required this.child, this.onTap});

  final String label;

  /// Null makes the button inert: dimmed, and it takes no taps.
  final VoidCallback? onTap;
  final Widget child;

  static const _round = BorderRadius.all(Radius.circular(24));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: PressScale.icon(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: SizedBox.square(
              dimension: Sizes.minTouchTarget,
              child: CrystalGlass(
                borderRadius: _round,
                blur: false,
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
