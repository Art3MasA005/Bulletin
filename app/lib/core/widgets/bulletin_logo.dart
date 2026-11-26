/// The Bulletin logo, "2a Peeking Panda, refined" (handoff README §7).
///
/// Drawn in code from `docs/design/handoff/assets/bulletin-logo.svg` rather
/// than shipped as an SVG: the mark is twenty primitives, a painter keeps it
/// sharp at every size from a 36px tile to a 1024px icon, and it costs no
/// SVG dependency. Coordinates are the SVG's own 120-unit viewBox, verbatim,
/// so the two can be diffed by eye.
///
/// The launcher icons are rendered from the same SVG
/// (`assets/logo/README.md`), so the app icon and the in-app mark cannot
/// drift apart.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// The colours a mark is drawn in. [standard] is the orange app icon;
/// [inverse] the dark-background variant (`bulletin-logo-dark.svg`).
@immutable
class BulletinMarkColors {
  const BulletinMarkColors({required this.ink, required this.face, required this.toes});

  /// Ears, eye patches, nose, mouth, ledge and paws.
  final Color ink;

  /// The face and the eye highlights.
  final Color face;

  /// The toe lines on the paws, cut out in the background colour.
  final Color toes;

  static const standard = BulletinMarkColors(
    ink: BulletinColors.ink,
    face: BulletinColors.white,
    toes: BulletinColors.brand,
  );

  static const inverse = BulletinMarkColors(
    ink: BulletinColors.brand,
    face: BulletinColors.white,
    toes: BulletinColors.ink,
  );
}

/// The panda mark alone, on a transparent background.
class BulletinMark extends StatelessWidget {
  const BulletinMark({
    this.size = 36,
    this.colors = BulletinMarkColors.standard,
    super.key,
  });

  final double size;
  final BulletinMarkColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MarkPainter(colors)),
    );
  }
}

/// The full app icon: the mark on a rounded brand tile (corner 27/120).
class BulletinAppIcon extends StatelessWidget {
  const BulletinAppIcon({this.size = 44, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: BulletinColors.brand,
          borderRadius: BorderRadius.circular(size * 27 / 120),
        ),
        child: const CustomPaint(painter: _MarkPainter(BulletinMarkColors.standard)),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.colors);

  final BulletinMarkColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 120, size.height / 120);
    // <g transform="translate(60 61) scale(1.08) translate(-60 -66)">
    canvas.translate(60, 61);
    canvas.scale(1.08);
    canvas.translate(-60, -66);

    final ink = Paint()..color = colors.ink;
    final face = Paint()..color = colors.face;

    // Ears.
    canvas.drawCircle(const Offset(33, 47), 14, ink);
    canvas.drawCircle(const Offset(87, 47), 14, ink);

    // Face: the top half of an ellipse sitting on the ledge.
    canvas.drawPath(
      Path()
        ..moveTo(20, 89)
        ..arcToPoint(const Offset(100, 89), radius: const Radius.elliptical(40, 37))
        ..close(),
      face,
    );

    // Eye patches, tilted, with highlights.
    _tiltedEllipse(canvas, const Offset(45, 72), 7.5, 10, 35, ink);
    _tiltedEllipse(canvas, const Offset(75, 72), 7.5, 10, -35, ink);
    canvas.drawCircle(const Offset(46.5, 70.5), 2.8, face);
    canvas.drawCircle(const Offset(73.5, 70.5), 2.8, face);

    // Nose and mouth.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(60, 80), width: 8.8, height: 6.2),
      ink,
    );
    canvas.drawPath(
      Path()
        ..moveTo(56.4, 84.2)
        ..quadraticBezierTo(58.2, 86, 60, 84.2)
        ..quadraticBezierTo(61.8, 86, 63.6, 84.2),
      _stroke(colors.ink),
    );

    // The ledge, and two paws gripping it.
    canvas.drawRRect(RRect.fromLTRBR(12, 88, 108, 98, const Radius.circular(5)), ink);
    for (final left in const [28.0, 73.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(left, 90)
          ..arcToPoint(Offset(left + 19, 90), radius: const Radius.elliptical(9.5, 8.5))
          ..close(),
        ink,
      );
      final toes = _stroke(colors.toes);
      for (final x in [left + 6.5, left + 12.5]) {
        canvas.drawLine(Offset(x, 84), Offset(x, 87), toes);
      }
    }

    canvas.restore();
  }

  static Paint _stroke(Color color) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round;

  static void _tiltedEllipse(
    Canvas canvas,
    Offset centre,
    double rx,
    double ry,
    double degrees,
    Paint paint,
  ) {
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(degrees * math.pi / 180);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => oldDelegate.colors != colors;
}
