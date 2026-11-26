/// The handoff's stroke icons: 24-unit grid, round caps and joins (README §7).
///
/// Each glyph is the prototype's SVG path transcribed into a [Path] builder.
/// Material's icons are filled and sit on a different optical grid, so mixing
/// them in would visibly change the weight of every form.
library;

import 'package:flutter/widgets.dart';

typedef _Glyph = void Function(Path path);

/// A glyph on the 24 x 24 grid.
@immutable
class LineGlyph {
  const LineGlyph._(this._build);

  final _Glyph _build;

  Path path() => Path().._applyGlyph(_build);
}

extension on Path {
  void _applyGlyph(_Glyph glyph) => glyph(this);
}

abstract final class LineIcons {
  /// M15 5l-7 7 7 7
  static final back = LineGlyph._(
    (p) => p
      ..moveTo(15, 5)
      ..lineTo(8, 12)
      ..lineTo(15, 19),
  );

  /// M5 12h14M13 6l6 6-6 6
  static final arrowRight = LineGlyph._(
    (p) => p
      ..moveTo(5, 12)
      ..lineTo(19, 12)
      ..moveTo(13, 6)
      ..lineTo(19, 12)
      ..lineTo(13, 18),
  );

  /// rect 3,5 18x14 rx3 + M4 7l8 6 8-6
  static final mail = LineGlyph._(
    (p) => p
      ..addRRect(RRect.fromLTRBR(3, 5, 21, 19, const Radius.circular(3)))
      ..moveTo(4, 7)
      ..lineTo(12, 13)
      ..lineTo(20, 7),
  );

  /// rect 4.5,10.5 15x10 rx2.5 + M8 10.5V7.5a4 4 0 018 0v3
  static final lock = LineGlyph._(
    (p) => p
      ..addRRect(RRect.fromLTRBR(4.5, 10.5, 19.5, 20.5, const Radius.circular(2.5)))
      ..moveTo(8, 10.5)
      ..lineTo(8, 7.5)
      ..arcToPoint(const Offset(16, 7.5), radius: const Radius.circular(4))
      ..lineTo(16, 10.5),
  );

  /// M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z + circle 12,12 r3.
  /// The smooth `s`/`S` segments are expanded to explicit cubics.
  static final eye = LineGlyph._(
    (p) => p
      ..moveTo(2, 12)
      ..cubicTo(2, 12, 5.5, 5, 12, 5)
      ..cubicTo(18.5, 5, 22, 12, 22, 12)
      ..cubicTo(22, 12, 18.5, 19, 12, 19)
      ..cubicTo(5.5, 19, 2, 12, 2, 12)
      ..close()
      ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 3)),
  );

  /// The eye with a slash through it, for "hide password".
  static final eyeOff = LineGlyph._(
    (p) => p
      .._applyGlyph(eye._build)
      ..moveTo(4, 4)
      ..lineTo(20, 20),
  );

  /// circle 12,12 r9 + M12 7.5v5.5M12 16.5v.3
  static final alert = LineGlyph._(
    (p) => p
      ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 9))
      ..moveTo(12, 7.5)
      ..lineTo(12, 13)
      ..moveTo(12, 16.5)
      ..lineTo(12, 16.8),
  );

  /// M3 20h18M5 20V9.5L12 5l7 4.5V20M9.5 20v-5h5v5 — the institution.
  static final building = LineGlyph._(
    (p) => p
      ..moveTo(3, 20)
      ..lineTo(21, 20)
      ..moveTo(5, 20)
      ..lineTo(5, 9.5)
      ..lineTo(12, 5)
      ..lineTo(19, 9.5)
      ..lineTo(19, 20)
      ..moveTo(9.5, 20)
      ..lineTo(9.5, 15)
      ..lineTo(14.5, 15)
      ..lineTo(14.5, 20),
  );

  /// M20 11.5l-8.1 8.1a5 5 0 01-7.1-7.1l8.5-8.5a3.3 3.3 0 014.7 4.7
  /// l-8.5 8.5a1.7 1.7 0 01-2.4-2.4l7.8-7.8 — attach.
  static final paperclip = LineGlyph._(
    (p) => p
      ..moveTo(20, 11.5)
      ..lineTo(11.9, 19.6)
      ..arcToPoint(const Offset(4.8, 12.5), radius: const Radius.circular(5))
      ..lineTo(13.3, 4)
      ..arcToPoint(const Offset(18, 8.7), radius: const Radius.circular(3.3))
      ..lineTo(9.5, 17.2)
      ..arcToPoint(const Offset(7.1, 14.8), radius: const Radius.circular(1.7))
      ..lineTo(14.9, 7),
  );

  /// M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z — a
  /// suggested question.
  static final sparkle = LineGlyph._(
    (p) => p
      ..moveTo(12, 3)
      ..lineTo(13.8, 8.2)
      ..lineTo(19, 10)
      ..lineTo(13.8, 11.8)
      ..lineTo(12, 17)
      ..lineTo(10.2, 11.8)
      ..lineTo(5, 10)
      ..lineTo(10.2, 8.2)
      ..close(),
  );

  /// M6 9l6 6 6-6 — the model pill's chevron.
  static final chevronDown = LineGlyph._(
    (p) => p
      ..moveTo(6, 9)
      ..lineTo(12, 15)
      ..lineTo(18, 9),
  );

  /// M12 20h8M16.5 3.5a2.1 2.1 0 013 3L7 19l-4 1 1-4z — new chat.
  static final pencil = LineGlyph._(
    (p) => p
      ..moveTo(12, 20)
      ..lineTo(20, 20)
      ..moveTo(16.5, 3.5)
      ..arcToPoint(const Offset(19.5, 6.5), radius: const Radius.circular(2.1))
      ..lineTo(7, 19)
      ..lineTo(3, 20)
      ..lineTo(4, 16)
      ..close(),
  );

  /// M4 8h3l2-3h6l2 3h3v11H4z + circle (12, 13) r 3.5 — camera.
  static final camera = LineGlyph._(
    (p) => p
      ..moveTo(4, 8)
      ..lineTo(7, 8)
      ..lineTo(9, 5)
      ..lineTo(15, 5)
      ..lineTo(17, 8)
      ..lineTo(20, 8)
      ..lineTo(20, 19)
      ..lineTo(4, 19)
      ..close()
      ..addOval(Rect.fromCircle(center: const Offset(12, 13), radius: 3.5)),
  );

  /// rect 4,4 16x16 r3 + circle (9, 9.5) r 1.5 + M20 15l-4.5-4.5L6 20 — gallery.
  static final image = LineGlyph._(
    (p) => p
      ..addRRect(RRect.fromLTRBR(4, 4, 20, 20, const Radius.circular(3)))
      ..addOval(Rect.fromCircle(center: const Offset(9, 9.5), radius: 1.5))
      ..moveTo(20, 15)
      ..lineTo(15.5, 10.5)
      ..lineTo(6, 20),
  );

  /// The document outline with its folded corner only — a file to pick.
  static final file = LineGlyph._(
    (p) => p
      ..moveTo(14, 3)
      ..lineTo(7, 3)
      ..arcToPoint(const Offset(5, 5), radius: const Radius.circular(2), clockwise: false)
      ..lineTo(5, 19)
      ..arcToPoint(
        const Offset(7, 21),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(17, 21)
      ..arcToPoint(
        const Offset(19, 19),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(19, 8)
      ..close()
      ..moveTo(14, 3)
      ..lineTo(14, 8)
      ..lineTo(19, 8),
  );

  /// M9 5l7 7-7 7 — a row that opens a screen.
  static final chevronRight = LineGlyph._(
    (p) => p
      ..moveTo(9, 5)
      ..lineTo(16, 12)
      ..lineTo(9, 19),
  );

  /// M14 3H7a2 2 0 00-2 2v14a2 2 0 002 2h10a2 2 0 002-2V8z M14 3v5h5M9 13h6M9 17h4
  /// — a document.
  static final document = LineGlyph._(
    (p) => p
      ..moveTo(14, 3)
      ..lineTo(7, 3)
      ..arcToPoint(const Offset(5, 5), radius: const Radius.circular(2), clockwise: false)
      ..lineTo(5, 19)
      ..arcToPoint(
        const Offset(7, 21),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(17, 21)
      ..arcToPoint(
        const Offset(19, 19),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(19, 8)
      ..close()
      ..moveTo(14, 3)
      ..lineTo(14, 8)
      ..lineTo(19, 8)
      ..moveTo(9, 13)
      ..lineTo(15, 13)
      ..moveTo(9, 17)
      ..lineTo(13, 17),
  );

  /// M12 19V5M6 11l6-6 6 6 — send.
  static final arrowUp = LineGlyph._(
    (p) => p
      ..moveTo(12, 19)
      ..lineTo(12, 5)
      ..moveTo(6, 11)
      ..lineTo(12, 5)
      ..lineTo(18, 11),
  );

  /// Three dots at y 5, 12, 19, r 1.8 — the menu. Drawn as zero-length
  /// strokes: with round caps and a 3.6 stroke each is a dot of r 1.8.
  static final dotsVertical = LineGlyph._(
    (p) => p
      ..moveTo(12, 5)
      ..lineTo(12, 5.01)
      ..moveTo(12, 12)
      ..lineTo(12, 12.01)
      ..moveTo(12, 19)
      ..lineTo(12, 19.01),
  );

  /// circle 12,12 r9 + M12 11v5M12 8v.3 — information.
  static final info = LineGlyph._(
    (p) => p
      ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 9))
      ..moveTo(12, 11)
      ..lineTo(12, 16)
      ..moveTo(12, 8)
      ..lineTo(12, 8.3),
  );

  /// circle 12,8 r4 + M4.5 20c1.4-3.7 4.3-5.6 7.5-5.6s6.1 1.9 7.5 5.6
  /// (the smooth `s` expanded to an explicit cubic) — a person.
  static final person = LineGlyph._(
    (p) => p
      ..addOval(Rect.fromCircle(center: const Offset(12, 8), radius: 4))
      ..moveTo(4.5, 20)
      ..cubicTo(5.9, 16.3, 8.8, 14.4, 12, 14.4)
      ..cubicTo(15.2, 14.4, 18.1, 16.3, 19.5, 20),
  );

  /// M3 3l18 18M8.5 16.5a5 5 0 017 0M5 12.6a10 10 0 015.2-2.8
  /// M19 12.6a10 10 0 00-2.7-1.9M2 8.6A15 15 0 018.4 5.4
  /// M22 8.6a15 15 0 00-9-3.6 + circle 12,20 r.8 — offline.
  static final wifiOff = LineGlyph._(
    (p) => p
      ..moveTo(3, 3)
      ..lineTo(21, 21)
      ..moveTo(8.5, 16.5)
      ..arcToPoint(const Offset(15.5, 16.5), radius: const Radius.circular(5))
      ..moveTo(5, 12.6)
      ..arcToPoint(const Offset(10.2, 9.8), radius: const Radius.circular(10))
      ..moveTo(19, 12.6)
      ..arcToPoint(
        const Offset(16.3, 10.7),
        radius: const Radius.circular(10),
        clockwise: false,
      )
      ..moveTo(2, 8.6)
      ..arcToPoint(const Offset(8.4, 5.4), radius: const Radius.circular(15))
      ..moveTo(22, 8.6)
      ..arcToPoint(
        const Offset(13, 5),
        radius: const Radius.circular(15),
        clockwise: false,
      )
      ..addOval(Rect.fromCircle(center: const Offset(12, 20), radius: 0.8)),
  );

  /// A check mark, for the account-created badge.
  static final check = LineGlyph._(
    (p) => p
      ..moveTo(5, 12.5)
      ..lineTo(10, 17.5)
      ..lineTo(19, 7.5),
  );

  /// circle 11,11 r6.5 + M20 20l-4.3-4.3M8.5 11h5 — a search that found nothing.
  static final searchMinus = LineGlyph._(
    (p) => p
      ..addOval(Rect.fromCircle(center: const Offset(11, 11), radius: 6.5))
      ..moveTo(20, 20)
      ..lineTo(15.7, 15.7)
      ..moveTo(8.5, 11)
      ..lineTo(13.5, 11),
  );

  /// M7 17L17 7M9 7h8v8 — open the page.
  static final arrowUpRight = LineGlyph._(
    (p) => p
      ..moveTo(7, 17)
      ..lineTo(17, 7)
      ..moveTo(9, 7)
      ..lineTo(17, 7)
      ..lineTo(17, 15),
  );

  /// M12 5v14M5 12h14 — reveal more.
  static final plus = LineGlyph._(
    (p) => p
      ..moveTo(12, 5)
      ..lineTo(12, 19)
      ..moveTo(5, 12)
      ..lineTo(19, 12),
  );

  /// M20 12a8 8 0 11-2.3-5.6M20 4v5h-5 — send again.
  static final retry = LineGlyph._(
    (p) => p
      ..moveTo(20, 12)
      ..arcToPoint(
        const Offset(17.7, 6.4),
        radius: const Radius.circular(8),
        largeArc: true,
      )
      ..moveTo(20, 4)
      ..lineTo(20, 9)
      ..lineTo(15, 9),
  );
}

class LineIcon extends StatelessWidget {
  const LineIcon(
    this.glyph, {
    required this.color,
    this.size = 20,
    this.strokeWidth = 1.75,
    this.filled = false,
    super.key,
  });

  final LineGlyph glyph;
  final Color color;
  final double size;

  /// In grid units, as the SVGs specify it (1.75 for UI icons, 2 for alerts).
  final double strokeWidth;

  /// Fills the shape instead of stroking it, for the glyphs the prototype
  /// draws with `fill="currentColor"` (the model sparkle).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _LinePainter(glyph, color, strokeWidth, filled)),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.glyph, this.color, this.strokeWidth, this.filled);

  final LineGlyph glyph;
  final Color color;
  final double strokeWidth;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      glyph.path(),
      Paint()
        ..color = color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.glyph != glyph ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.filled != filled;
}
