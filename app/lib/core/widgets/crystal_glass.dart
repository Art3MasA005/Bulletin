/// Crystal glass (handoff README §1): the sign-in back button now, the Home
/// chrome later.
///
/// fill:   LinearGradient(160°) white .62 → .22 (55%) → .40
/// border: 1px white .95
/// inner:  top highlight 1.5px white; bottom inner glow 0 −10 18 −8
///         rgba(255,150,90,.16); hairline 0.5px rgba(180,90,40,.10)
/// outer:  0 10 26 −6 rgba(170,80,25,.18), 0 2 4 rgba(170,80,25,.06)
/// blur:   sigma 20, saturation 180% — a BackdropFilter, so at most two
///         per screen and never in a list item (CLAUDE.md §11).
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

class CrystalGlass extends StatelessWidget {
  const CrystalGlass({
    required this.child,
    this.borderRadius = BrandRadii.square,
    this.blur = true,
    super.key,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// False draws the same glass without its BackdropFilter, for a screen
  /// that has already spent its two.
  final bool blur;

  /// CSS 160°: from the top, a little left, to the bottom, a little right.
  static const _begin = Alignment(-0.34, -0.94);
  static const _end = Alignment(0.34, 0.94);

  /// Saturation 180%, as a colour matrix on the blurred backdrop.
  static final ui.ImageFilter _backdrop = ui.ImageFilter.compose(
    outer: const ui.ColorFilter.matrix(_saturate180),
    inner: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
  );

  /// CSS `saturate(1.8)`, from the filter spec's matrix:
  /// [.213+.787s  .715−.715s  .072−.072s] and so on.
  static const _saturate180 = <double>[
    1.6296, -0.5720, -0.0576, 0, 0, //
    -0.1704, 1.2280, -0.0576, 0, 0,
    -0.1704, -0.5720, 1.7424, 0, 0,
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          begin: _begin,
          end: _end,
          stops: [0, 0.55, 1],
          colors: [
            BulletinColors.glassFillTop,
            BulletinColors.glassFillMid,
            BulletinColors.glassFillEnd,
          ],
        ),
        border: Border.all(color: BulletinColors.glassBorder),
      ),
      position: DecorationPosition.background,
      child: CustomPaint(foregroundPainter: _InnerLight(borderRadius), child: child),
    );

    return CustomPaint(
      painter: _OuterShadow(borderRadius),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: blur ? BackdropFilter(filter: _backdrop, child: surface) : surface,
      ),
    );
  }
}

/// The outer shadow, drawn only OUTSIDE the shape, as CSS does. A Flutter
/// BoxShadow also paints under the box, which shows through a glass fill as
/// a dark patch.
class _OuterShadow extends CustomPainter {
  const _OuterShadow(this.radius);

  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = radius.toRRect(Offset.zero & size);
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect((Offset.zero & size).inflate(60)),
      Path()..addRRect(shape),
    );
    canvas.save();
    canvas.clipPath(outside);
    for (final s in BrandLifts.glass) {
      canvas.drawRRect(
        shape.shift(s.offset).inflate(s.spreadRadius),
        Paint()
          ..color = s.color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.blurSigma),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadow old) => old.radius != radius;
}

/// The three inset effects, clipped to the shape: a 1.5 px white highlight
/// along the top edge, a warm glow rising from the bottom edge, and a 0.5 px
/// warm hairline.
class _InnerLight extends CustomPainter {
  const _InnerLight(this.radius);

  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = radius.toRRect(Offset.zero & size);
    canvas.save();
    canvas.clipRRect(shape);

    // inset 0 1.5px 0 white: the band the shape uncovers when shifted down.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRRect(shape),
        Path()..addRRect(shape.shift(const Offset(0, 1.5))),
      ),
      Paint()..color = BulletinColors.white,
    );

    // inset 0 −10px 18px −8px: everything outside the shape moved up 10 and
    // shrunk 8, blurred, so only a glow along the bottom edge remains.
    final hole = shape.shift(const Offset(0, -10)).deflate(8);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect((Offset.zero & size).inflate(40)),
        Path()..addRRect(hole),
      ),
      Paint()
        ..color = BulletinColors.glassInnerGlow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );

    canvas.drawRRect(
      shape.deflate(0.25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = BulletinColors.glassHairline,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InnerLight old) => old.radius != radius;
}
