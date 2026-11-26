/// The small panda peeking over the white sheet on Sign in and Sign up
/// (handoff README §4, "Sign-in panda"; CHANGES.md for Sign up): 144 x 91,
/// gripping the sheet's top edge, waving once.
///
/// Same rig as the splash, different choreography: the head rises 700 ms
/// after 320, the grip lands 420 ms after 620, and the paw waves once,
/// 0 → −11° → 0 → +7° → 0 over 1300 ms after 900. No ledge (the card's edge
/// is the ledge), no blink, and the paw rises with the head.
library;

import 'package:flutter/widgets.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/widgets/panda_rig.dart';

class SheetPanda extends StatefulWidget {
  const SheetPanda({super.key});

  static const size = Size(144, 91);

  @override
  State<SheetPanda> createState() => _SheetPandaState();
}

class _SheetPandaState extends State<SheetPanda> with SingleTickerProviderStateMixin {
  static const _total = 900 + 1300;

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _total),
  );

  late Animation<double> _rise;
  late Animation<double> _grip;
  late Animation<double> _wave;
  bool _wired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;

    if (reduceMotionOf(context)) {
      // Static: the panda is simply there (README §5, Reduced motion).
      _rise = kAlwaysCompleteAnimation;
      _grip = kAlwaysCompleteAnimation;
      _wave = const AlwaysStoppedAnimation(0);
      return;
    }

    Animation<double> beat(int delay, int duration) => CurvedAnimation(
      parent: _clock,
      curve: msInterval(
        delay: delay,
        duration: duration,
        total: _total,
        curve: MotionCurves.splash,
      ),
    );
    _rise = beat(320, 700);
    _grip = beat(620, 420);

    // One wave, each quarter eased on its own, as CSS applies the timing
    // function per keyframe segment.
    const ease = Cubic(0.45, 0, 0.55, 1);
    TweenSequenceItem<double> swing(double from, double to) => TweenSequenceItem(
      tween: Tween(begin: from, end: to).chain(CurveTween(curve: ease)),
      weight: 1,
    );
    _wave =
        TweenSequence<double>([
          swing(0, -11),
          swing(-11, 0),
          swing(0, 7),
          swing(7, 0),
        ]).animate(
          CurvedAnimation(
            parent: _clock,
            curve: msInterval(delay: 900, duration: 1300, total: _total),
          ),
        );

    // Decoded already if the splash ran; on a later sign-out it may not be.
    PandaAssets.precache(context).whenComplete(() {
      if (mounted) _clock.forward();
    });
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.fromSize(
        size: SheetPanda.size,
        child: PandaRig(rise: _rise, grip: _grip, waveDegrees: _wave),
      ),
    );
  }
}
