/// The brand sky: clouds, four-point sparkles and thin arcs on orange.
///
/// One painter, many scenes. The splash and the sign-in header place the same
/// shapes differently; each screen owns its [SkyScene] (pure data, in the
/// prototype's 390-wide design frame) and this paints it, scaled uniformly to
/// the width so the composition keeps its shape on a wider phone.
///
/// Static by rule: painted once, never animated (README §4, Performance).
library;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// A pill with circles sitting on it. All values in design pixels.
@immutable
class SkyCloud {
  const SkyCloud({required this.base, required this.puffs});

  /// The pill. Its radius is half its height.
  final Rect base;

  /// Each puff's centre and radius.
  final List<(Offset, double)> puffs;
}

/// A four-point sparkle: top-left corner and side length.
typedef SkySparkle = (Offset, double);

/// A quadratic arc: start, control, end.
typedef SkyArc = (Offset, Offset, Offset);

@immutable
class SkyScene {
  const SkyScene({
    this.clouds = const [],
    this.sparkles = const [],
    this.arcs = const [],
  });

  final List<SkyCloud> clouds;
  final List<SkySparkle> sparkles;
  final List<SkyArc> arcs;
}

class BrandSky extends StatelessWidget {
  const BrandSky(this.scene, {super.key});

  final SkyScene scene;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: _SkyPainter(scene), size: Size.infinite),
    );
  }
}

class _SkyPainter extends CustomPainter {
  const _SkyPainter(this.scene);

  final SkyScene scene;

  static const _designWidth = 390.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _designWidth);

    final cloud = Paint()..color = BulletinColors.cloud;
    for (final c in scene.clouds) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(c.base, Radius.circular(c.base.height / 2)),
        cloud,
      );
      for (final (centre, r) in c.puffs) {
        canvas.drawCircle(centre, r, cloud);
      }
    }

    final line = Paint()
      ..color = BulletinColors.skyLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final (start, control, end) in scene.arcs) {
      canvas.drawPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy),
        line,
      );
    }

    final sparkle = Paint()..color = BulletinColors.white;
    for (final (origin, side) in scene.sparkles) {
      canvas.drawPath(_sparkle(origin, side), sparkle);
    }

    canvas.restore();
  }

  /// The prototype's 24x24 star: M12 0C12.9 7.6 16.4 11.1 24 12 … Z.
  static Path _sparkle(Offset origin, double side) {
    final s = side / 24;
    Offset p(double x, double y) => origin + Offset(x * s, y * s);
    void cubic(Path path, Offset a, Offset b, Offset c) =>
        path.cubicTo(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy);

    final top = p(12, 0);
    final path = Path()..moveTo(top.dx, top.dy);
    cubic(path, p(12.9, 7.6), p(16.4, 11.1), p(24, 12));
    cubic(path, p(16.4, 12.9), p(12.9, 16.4), p(12, 24));
    cubic(path, p(11.1, 16.4), p(7.6, 12.9), p(0, 12));
    cubic(path, p(7.6, 11.1), p(11.1, 7.6), top);
    return path..close();
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) => oldDelegate.scene != scene;
}
