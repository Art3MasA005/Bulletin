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
  /// chat" appears.
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
        if (inThread && onNewChat != null) ...[
          _RoundButton(
            label: l.newChat,
            onTap: onNewChat!,
            child: LineIcon(LineIcons.pencil, color: BulletinColors.ink),
          ),
          const SizedBox(width: Space.sm),
        ],
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
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback onTap;
  final Widget child;

  static const _round = BorderRadius.all(Radius.circular(24));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
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
    );
  }
}
