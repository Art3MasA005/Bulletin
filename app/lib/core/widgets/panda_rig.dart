/// The peeking panda, as a rig of layers. Handoff README §4.
///
/// The rig only RENDERS a pose. It owns no controllers and no timeline: the
/// splash and the sign-in card drive the same layers with different
/// choreography, so the choreography belongs to each screen and the geometry
/// belongs here, once.
///
/// The three PNGs share one 786x498 canvas, so they stack 1:1 at any size.
/// Every offset below is a fraction of the rig's box, taken from the
/// prototype, which keeps the rig correct at 300x190 (splash) and 144x91
/// (sign-in) alike.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

abstract final class PandaAssets {
  static const body = 'assets/panda/panda-body.png';
  static const paw = 'assets/panda/panda-paw.png';
  static const grip = 'assets/panda/panda-grip.png';

  /// The full panda, for the Welcome hero.
  static const whole = 'assets/panda/panda.png';

  static const layers = <String>[body, paw, grip];

  /// Decodes the three layers ahead of the first frame.
  ///
  /// The splash must hold at frame 0 until this completes: a layer that
  /// decodes late pops in mid-animation, which is exactly the stutter the
  /// handoff calls out.
  static Future<void> precache(BuildContext context) =>
      Future.wait([for (final path in layers) precacheImage(AssetImage(path), context)]);
}

/// The rig's design aspect ratio (300 x 190 on the splash).
const pandaAspectRatio = 300 / 190;

/// Draws the panda from five animated inputs, each 0 → 1 unless noted.
class PandaRig extends StatelessWidget {
  const PandaRig({
    required this.rise,
    required this.grip,
    required this.waveDegrees,
    this.pawUp = kAlwaysCompleteAnimation,
    this.ledge,
    this.blink,
    super.key,
  });

  /// The ledge bar growing out from its centre. Null draws no ledge: the
  /// sign-in panda grips the card's edge instead.
  final Animation<double>? ledge;

  /// The head rising from behind the ledge.
  final Animation<double> rise;

  /// The gripping paw dropping onto the ledge and fading in.
  final Animation<double> grip;

  /// The waving paw rising into place. Complete by default: on sign-in the
  /// paw rises with the head rather than after it.
  final Animation<double> pawUp;

  /// The wave's rotation, in DEGREES (the spec is written in degrees).
  final Animation<double> waveDegrees;

  /// The blink lids' vertical scale: 0 is open eyes, 1 is closed. Null
  /// draws no lids.
  final Animation<double>? blink;

  // Geometry, as fractions of the rig box (handoff README §4).
  static const _ledgeLine = 166 / 190; // the clip and the ledge's top edge
  static const _ledgeHeight = 0.029;
  static const _ledgeInset = 0.008;
  static const _riseFrom = 0.72;
  static const _pawFrom = 0.85;
  static const _pawTiltDegrees = 8.0;
  static const _gripFrom = -0.12;

  /// The wave pivots BELOW the ledge, at (21.6%, 112.4%) of the image box,
  /// so the arm swings from the shoulder and the cut never shows. As an
  /// [Alignment] that is (2x − 1, 2y − 1).
  static const _wavePivot = Alignment(2 * 0.216 - 1, 2 * 1.124 - 1);

  /// Only the bottom is clipped, at the ledge line; the top and sides are
  /// left open so the ears are never cut off. The prototype's clip box is
  /// (-60, -120, 360, 166) on a 300x190 rig.
  static Rect _clipFor(Size size) => Rect.fromLTRB(
    -0.2 * size.width,
    -(120 / 190) * size.height,
    1.2 * size.width,
    _ledgeLine * size.height,
  );

  static double _radians(double degrees) => degrees * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: pandaAspectRatio,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          return Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              ClipRect(
                clipper: _BottomClipper(_clipFor(size)),
                child: Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [_layer(_head(size)), _layer(_wavingPaw(size))],
                ),
              ),
              if (ledge case final ledge?) _ledgeBar(size, ledge),
              _layer(_grippingPaw(size)),
            ],
          );
        },
      ),
    );
  }

  /// Each moving layer gets its own repaint boundary, so the wave repaints
  /// the paw and nothing else (README §4, Performance).
  Widget _layer(Widget child) => RepaintBoundary(child: child);

  Widget _head(Size size) {
    return AnimatedBuilder(
      animation: rise,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _riseFrom * size.height * (1 - rise.value)),
        child: child,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _Layer(PandaAssets.body),
          if (blink case final blink?) ...[
            _lid(size, blink, left: 0.413, top: 0.367),
            _lid(size, blink, left: 0.652, top: 0.486),
          ],
        ],
      ),
    );
  }

  Widget _lid(
    Size size,
    Animation<double> blink, {
    required double left,
    required double top,
  }) {
    return Positioned(
      left: left * size.width,
      top: top * size.height,
      width: 0.064 * size.width,
      height: 0.10 * size.height,
      child: AnimatedBuilder(
        animation: blink,
        builder: (context, child) =>
            Transform.scale(scaleX: 1, scaleY: blink.value, child: child),
        child: const DecoratedBox(
          decoration: ShapeDecoration(
            shape: OvalBorder(),
            color: BulletinColors.pandaLine,
          ),
        ),
      ),
    );
  }

  Widget _wavingPaw(Size size) {
    return AnimatedBuilder(
      animation: pawUp,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _pawFrom * size.height * (1 - pawUp.value)),
        child: Transform.rotate(
          angle: _radians(_pawTiltDegrees * (1 - pawUp.value)),
          child: child,
        ),
      ),
      child: AnimatedBuilder(
        animation: waveDegrees,
        builder: (context, child) => Transform.rotate(
          key: const ValueKey('panda-wave'),
          angle: _radians(waveDegrees.value),
          alignment: _wavePivot,
          child: child,
        ),
        child: const _Layer(PandaAssets.paw),
      ),
    );
  }

  Widget _ledgeBar(Size size, Animation<double> ledge) {
    return Positioned(
      left: _ledgeInset * size.width,
      right: _ledgeInset * size.width,
      top: _ledgeLine * size.height,
      height: _ledgeHeight * size.height,
      // The boundary goes INSIDE the Positioned: a Positioned must sit
      // directly in its Stack.
      child: _layer(
        AnimatedBuilder(
          animation: ledge,
          builder: (context, child) =>
              Transform.scale(scaleX: ledge.value, scaleY: 1, child: child),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: BulletinColors.pandaLine,
              borderRadius: BorderRadius.all(Radius.circular(3)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _grippingPaw(Size size) {
    return FadeTransition(
      opacity: grip,
      child: AnimatedBuilder(
        animation: grip,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, _gripFrom * size.height * (1 - grip.value)),
          child: child,
        ),
        child: const _Layer(PandaAssets.grip),
      ),
    );
  }
}

class _Layer extends StatelessWidget {
  const _Layer(this.asset);

  final String asset;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
      // Keeps the previous frame on a rebuild instead of flashing empty.
      gaplessPlayback: true,
      excludeFromSemantics: true,
    );
  }
}

class _BottomClipper extends CustomClipper<Rect> {
  const _BottomClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(_BottomClipper oldClipper) => oldClipper.rect != rect;
}
