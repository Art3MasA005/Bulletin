/// The Welcome hero's panda (prototype `sp.peek`, `sp.sway`): the whole
/// panda, 300 wide, peeking up into place and then swaying gently.
///
/// Peek: opacity 0 → 1, 40 px up, scale .92 → 1, 650 ms soft-pop after 150.
/// Sway: −2.5° ↔ +2.5° about the bottom centre, lifting 3 px at the far end,
/// 2.4 s ease-in-out, looping from 800 ms (when the peek lands). Reduced
/// motion: the panda is simply there, still.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/widgets/panda_rig.dart';

class WelcomePanda extends StatefulWidget {
  const WelcomePanda({required this.semanticLabel, super.key});

  final String semanticLabel;

  /// The prototype's 300 px width at the image's own 786 x 498 aspect.
  static const size = Size(300, 300 * 498 / 786);

  @override
  State<WelcomePanda> createState() => _WelcomePandaState();
}

class _WelcomePandaState extends State<WelcomePanda> with TickerProviderStateMixin {
  static const _peekDelay = 150;
  static const _peekDuration = 650;
  static const _swayHalf = Duration(milliseconds: 1200);
  static const _swayDegrees = 2.5;
  static const _swayLift = 3.0;

  late final AnimationController _peek = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _peekDelay + _peekDuration),
  );

  // One half of the CSS cycle; reversing gives the other half. Each half is
  // eased on its own, as CSS applies ease-in-out per keyframe segment. It
  // rests mid-swing, where the angle is 0, so the loop picks up from the pose
  // the peek landed in instead of snapping to −2.5°.
  late final AnimationController _sway = AnimationController(
    vsync: this,
    duration: _swayHalf,
    value: 0.5,
  );

  late final Animation<double> _peekIn = CurvedAnimation(
    parent: _peek,
    curve: msInterval(
      delay: _peekDelay,
      duration: _peekDuration,
      total: _peekDelay + _peekDuration,
      curve: MotionCurves.softPop,
    ),
  );
  late final Animation<double> _swing = CurvedAnimation(
    parent: _sway,
    curve: Curves.easeInOut,
  );

  bool _wired = false;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;

    if (reduceMotionOf(context)) {
      _still = true;
      return;
    }

    _peek.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      _sway.repeat(reverse: true);
    });

    // Nothing to see until the image is decoded; the peek starts at opacity
    // 0, so waiting costs no pop.
    precacheImage(const AssetImage(PandaAssets.whole), context).whenComplete(() {
      if (mounted) _peek.forward();
    });
  }

  @override
  void dispose() {
    _peek.dispose();
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      PandaAssets.whole,
      width: WelcomePanda.size.width,
      height: WelcomePanda.size.height,
      semanticLabel: widget.semanticLabel,
    );
    if (_still) return image;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_peekIn, _swing]),
        child: image,
        builder: (context, child) {
          final p = _peekIn.value;
          // Swing runs 0 → 1 → 0: −2.5° → +2.5°, lifting at the + end.
          final s = _swing.value;
          final degrees = -_swayDegrees + 2 * _swayDegrees * s;
          return Opacity(
            // soft-pop overshoots; opacity cannot.
            opacity: p.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 40 * (1 - p) - _swayLift * s),
              child: Transform.scale(
                scale: 0.92 + 0.08 * p,
                child: Transform.rotate(
                  angle: degrees * math.pi / 180,
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
