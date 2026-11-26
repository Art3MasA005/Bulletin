/// The drifting clouds on Welcome, Sign in and Sign up (handoff CHANGES.md,
/// "Shared: drifting clouds").
///
/// Four gradient clouds, each crossing from fully off-screen left to fully
/// off-screen right and looping (linear), started part-way through their
/// cycle so they are spread out on the first frame. Each also bobs ±4 px on
/// its own phase. Optional sparkles twinkle. Reduced motion: everything
/// stays still at its base position.
///
/// One painter for the whole layer, repainting from one ticker: the clouds
/// never rebuild a widget, and the layer has its own repaint boundary so the
/// rest of the screen does not repaint with it. Positions are the
/// prototype's, in its 390-wide design frame, scaled to the width.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../motion/motion.dart';
import '../theme/tokens.dart';

/// The three cloud outlines in the prototype, each in its own SVG viewBox:
/// a start point, then cubic segments (control, control, end), closed.
enum CloudShape {
  /// viewBox 200 x 60.
  wide(Size(200, 60), [
    20, 56, //
    8, 56, 2, 46, 8, 38,
    12, 32, 22, 30, 28, 34,
    32, 22, 48, 18, 58, 24,
    66, 12, 86, 10, 96, 22,
    106, 14, 124, 16, 128, 28,
    140, 22, 158, 24, 162, 36,
    176, 34, 192, 40, 192, 48,
    192, 54, 186, 56, 180, 56,
  ]),

  /// viewBox 200 x 80.
  big(Size(200, 80), [
    28, 76, //
    10, 76, 2, 62, 8, 50,
    14, 38, 30, 36, 38, 42,
    40, 24, 58, 12, 78, 16,
    92, 4, 120, 4, 132, 20,
    146, 12, 168, 18, 172, 36,
    190, 36, 198, 52, 192, 64,
    188, 72, 180, 76, 170, 76,
  ]),

  /// viewBox 120 x 60.
  small(Size(120, 60), [
    18, 56, //
    6, 56, 0, 46, 6, 38,
    10, 30, 20, 30, 26, 34,
    28, 20, 42, 12, 56, 16,
    66, 6, 86, 8, 92, 22,
    104, 20, 116, 30, 114, 42,
    112, 52, 104, 56, 96, 56,
  ]);

  const CloudShape(this.viewBox, this._points);

  final Size viewBox;
  final List<double> _points;

  /// The outline stretched to [size] (`preserveAspectRatio="none"`).
  Path pathIn(Size size) {
    final sx = size.width / viewBox.width;
    final sy = size.height / viewBox.height;
    final p = _points;
    final path = Path()..moveTo(p[0] * sx, p[1] * sy);
    for (var i = 2; i < p.length; i += 6) {
      path.cubicTo(
        p[i] * sx,
        p[i + 1] * sy,
        p[i + 2] * sx,
        p[i + 3] * sy,
        p[i + 4] * sx,
        p[i + 5] * sy,
      );
    }
    return path..close();
  }
}

/// A cloud's timing. The prototype gives each depth its own pace: the near,
/// large cloud crosses fastest, the far one slowest. Durations and the
/// head-start into the cycle are in seconds.
@immutable
class CloudPace {
  const CloudPace({
    required this.drift,
    required this.driftHeadStart,
    required this.bob,
    required this.bobHeadStart,
  });

  final double drift;
  final double driftHeadStart;
  final double bob;
  final double bobHeadStart;

  // Prototype `si.cloudA..D` and `si.bobA..D`.
  static const near = CloudPace(drift: 44, driftHeadStart: 10, bob: 7, bobHeadStart: 0);
  static const mid = CloudPace(drift: 58, driftHeadStart: 30, bob: 9, bobHeadStart: 3);
  static const far = CloudPace(drift: 96, driftHeadStart: 50, bob: 11, bobHeadStart: 5);
  static const small = CloudPace(drift: 50, driftHeadStart: 20, bob: 8, bobHeadStart: 2);
}

@immutable
class DriftCloud {
  const DriftCloud({
    required this.shape,
    required this.rect,
    required this.opacity,
    required this.top,
    required this.bottom,
    required this.from,
    required this.to,
    required this.pace,
  });

  final CloudShape shape;

  /// Where it sits with no motion (left, top, width, height).
  final Rect rect;
  final double opacity;

  /// The vertical gradient's two stops.
  final Color top;
  final Color bottom;

  /// The horizontal travel relative to [rect] (`--a` → `--b`).
  final double from;
  final double to;
  final CloudPace pace;
}

/// A twinkling sparkle: top-left corner, side, period and head-start (s).
typedef Twinkle = ({Offset origin, double side, double period, double headStart});

@immutable
class CloudScene {
  const CloudScene({required this.clouds, this.twinkles = const []});

  final List<DriftCloud> clouds;
  final List<Twinkle> twinkles;
}

/// Where a looping animation is in its cycle, 0..1, [t] seconds in.
double loopPhase(double t, double period, double headStart) =>
    ((t + headStart) % period) / period;

/// CSS ease-in-out over keyframes 0% → 50% → 100% of 0 → 1 → 0.
double pingPong(double phase) =>
    Curves.easeInOut.transform(phase < 0.5 ? phase * 2 : (1 - phase) * 2);

/// How far [cloud] has moved from its base position [t] seconds in: the
/// drift across, and the bob (up is negative).
Offset cloudOffset(DriftCloud cloud, double t) {
  const bobHeight = 4.0;
  final pace = cloud.pace;
  return Offset(
    cloud.from + (cloud.to - cloud.from) * loopPhase(t, pace.drift, pace.driftHeadStart),
    -bobHeight * pingPong(loopPhase(t, pace.bob, pace.bobHeadStart)),
  );
}

class DriftingClouds extends StatefulWidget {
  const DriftingClouds(this.scene, {super.key});

  final CloudScene scene;

  @override
  State<DriftingClouds> createState() => _DriftingCloudsState();
}

class _DriftingCloudsState extends State<DriftingClouds>
    with SingleTickerProviderStateMixin {
  /// Seconds since mount; null while still (reduced motion).
  final _clock = ValueNotifier<double?>(null);
  Ticker? _ticker;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = reduceMotionOf(context);
    if (still) {
      _ticker?.dispose();
      _ticker = null;
      _clock.value = null;
    } else if (_ticker == null) {
      _clock.value = 0;
      _ticker = createTicker((elapsed) {
        _clock.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
      })..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _CloudPainter(widget.scene, _clock),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _CloudPainter extends CustomPainter {
  _CloudPainter(this.scene, this.clock) : super(repaint: clock);

  final CloudScene scene;
  final ValueListenable<double?> clock;

  static const _designWidth = 390.0;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    canvas.save();
    canvas.scale(size.width / _designWidth);

    for (final c in scene.clouds) {
      final moved = t == null ? Offset.zero : cloudOffset(c, t);
      final box = c.rect.size;
      canvas.save();
      canvas.translate(c.rect.left + moved.dx, c.rect.top + moved.dy);
      canvas.drawPath(
        c.shape.pathIn(box),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // Opacity baked into the stops, as the element's opacity is.
            colors: [
              c.top.withValues(alpha: c.opacity),
              c.bottom.withValues(alpha: c.opacity),
            ],
          ).createShader(Offset.zero & box),
      );
      canvas.restore();
    }

    final sparkle = Paint();
    for (final s in scene.twinkles) {
      // opacity .35 ↔ 1, scale .7 ↔ 1, rotate 0 ↔ 18°, about the centre.
      final v = t == null ? 1.0 : pingPong(loopPhase(t, s.period, s.headStart));
      final centre = s.origin + Offset(s.side / 2, s.side / 2);
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(18 * v * math.pi / 180);
      final scale = 0.7 + 0.3 * v;
      canvas.scale(scale);
      sparkle.color = BulletinColors.white.withValues(alpha: 0.35 + 0.65 * v);
      canvas.drawPath(_sparkle(s.side), sparkle);
      canvas.restore();
    }

    canvas.restore();
  }

  /// The prototype's 24x24 star, centred on the origin.
  static Path _sparkle(double side) {
    final k = side / 24;
    Offset p(double x, double y) => Offset((x - 12) * k, (y - 12) * k);
    final path = Path();
    final top = p(12, 0);
    path.moveTo(top.dx, top.dy);
    void cubic(Offset a, Offset b, Offset c) =>
        path.cubicTo(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy);
    cubic(p(12.9, 7.6), p(16.4, 11.1), p(24, 12));
    cubic(p(16.4, 12.9), p(12.9, 16.4), p(12, 24));
    cubic(p(11.1, 16.4), p(7.6, 12.9), p(0, 12));
    cubic(p(7.6, 11.1), p(11.1, 7.6), top);
    return path..close();
  }

  @override
  bool shouldRepaint(_CloudPainter old) => old.scene != scene || old.clock != clock;
}
