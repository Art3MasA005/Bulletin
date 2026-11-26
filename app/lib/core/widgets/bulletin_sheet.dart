/// The handoff's bottom sheet (README §2.8–2.9, §5 "Bottom sheet").
///
/// White, 28 px top corners, `0 -8 32` shadow, a 36 x 5 handle in a 28 px
/// strip, content padded 4 / 24 / 40. Rises 100% → 0 over 450 ms `sheet`
/// (a little overshoot), leaves to 105% over 280 ms `exit`; the scrim is
/// ink at .36. Dragged 1:1 by its handle or body; let go and it settles or
/// closes. Reduced motion: 150 ms, linear.
library;

import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/theme.dart';

Future<T?> showBulletinSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  final reduce = reduceMotionOf(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: BulletinColors.white.withValues(alpha: 0),
    barrierColor: BulletinColors.scrim,
    elevation: 0,
    sheetAnimationStyle: reduce
        ? const AnimationStyle(
            duration: MotionDurations.reduced,
            reverseDuration: MotionDurations.reduced,
            curve: Curves.linear,
          )
        : const AnimationStyle(
            duration: MotionDurations.sheetIn,
            reverseDuration: MotionDurations.sheetOut,
            curve: MotionCurves.sheet,
            reverseCurve: MotionCurves.exit,
          ),
    builder: (context) => BulletinSheet(showHandle: dismissible, child: builder(context)),
  );
}

class BulletinSheet extends StatelessWidget {
  const BulletinSheet({required this.child, this.showHandle = true, super.key});

  final Widget child;

  /// Hidden while the sheet cannot be dismissed (the prototype fades it out
  /// while a routine is being read).
  final bool showHandle;

  static const _radius = BorderRadius.vertical(top: Radius.circular(28));

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: BulletinColors.white,
          borderRadius: _radius,
          boxShadow: BrandLifts.sheet,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 28,
              child: Center(
                child: AnimatedOpacity(
                  opacity: showHandle ? 1 : 0,
                  duration: MotionDurations.micro,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: BulletinColors.inert,
                      borderRadius: BorderRadius.all(Radius.circular(3)),
                    ),
                    child: SizedBox(width: 36, height: 5),
                  ),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 4, 24, 40 + (keyboard > 0 ? 0 : bottom)),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
