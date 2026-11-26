/// The Home orb (prototype `home.orb`): 200 px of layered radial light,
/// breathing 1 ↔ 1.04 every 2.4 s (ease-in-out). Reduced motion: still.
///
/// Five layers, each a CSS `radial-gradient(circle, …)` inside a box with
/// `border-radius: 50%`: the gradient's 100 % stop sits at the box's
/// farthest corner and the box clips it to an ellipse. Three rings are
/// offset boxes that spill past the orb, which is what makes the edge look
/// soft and uneven rather than drawn with a compass.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/theme/tokens.dart';

class BreathingOrb extends StatefulWidget {
  const BreathingOrb({this.size = 200, super.key});

  final double size;

  @override
  State<BreathingOrb> createState() => _BreathingOrbState();
}

class _BreathingOrbState extends State<BreathingOrb> with SingleTickerProviderStateMixin {
  // Half the 2.4 s cycle; reversing gives the other half.
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 1,
    end: 1.04,
  ).animate(CurvedAnimation(parent: _breath, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _breath.stop();
      _breath.value = 0;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: ScaleTransition(
          scale: _scale,
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: const _OrbPainter(),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter();

  /// The prototype's layers, as boxes in its 200 px orb and gradient stops.
  static const _layers = <(Rect, List<double>, List<Color>)>[
    (
      Rect.fromLTRB(0, 0, 200, 200),
      [0, 0.40, 0.66, 1],
      [
        BulletinColors.orbWhite,
        BulletinColors.orbWhiteHalf,
        BulletinColors.orbPeach,
        BulletinColors.orbEdge,
      ],
    ),
    // inset: −8 12 16 −12
    (
      Rect.fromLTRB(-12, -8, 188, 184),
      [0, 0.56, 1],
      [_clearA, _clearA, BulletinColors.orbRingA],
    ),
    // inset: 14 −14 −8 10
    (
      Rect.fromLTRB(10, 14, 214, 208),
      [0, 0.56, 1],
      [_clearB, _clearB, BulletinColors.orbRingB],
    ),
    // inset: −14 −2 8 6
    (
      Rect.fromLTRB(6, -14, 202, 192),
      [0, 0.60, 1],
      [_clearC, _clearC, BulletinColors.orbRingC],
    ),
    // inset: 52 — the bright core.
    (
      Rect.fromLTRB(52, 52, 148, 148),
      [0, 0.5, 1],
      [BulletinColors.white, BulletinColors.orbWhiteCore, _clearWhite],
    ),
  ];

  // Each ring fades from its own colour at zero alpha, as CSS interpolates
  // in premultiplied space: no white haze on the way.
  static const _clearA = Color(0x00FF8C46);
  static const _clearB = Color(0x00FF8C46);
  static const _clearC = Color(0x00FFAA6E);
  static const _clearWhite = Color(0x00FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200);
    for (final (box, stops, colors) in _layers) {
      final farthestCorner =
          math.sqrt(box.width * box.width + box.height * box.height) / 2;
      canvas.save();
      canvas.clipPath(Path()..addOval(box));
      canvas.drawRect(
        box,
        Paint()..shader = ui.Gradient.radial(box.center, farthestCorner, colors, stops),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) => false;
}
