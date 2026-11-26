/// The splash: the panda peeks over its ledge, waves a few times and lowers
/// its paw, the wordmark rises letter by letter, the tagline fades in. Handoff README §2.1 and §4.
///
/// This widget owns the CHOREOGRAPHY only: when each layer moves. What the
/// layers look like is [PandaRig]'s; what happens after the splash (the exit
/// and the screen beneath fading in) is [LaunchGate]'s. The screen reports
/// that it is done through [onFinished] (auto-advance, or a tap to skip) and
/// nothing else.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/brand_sky.dart';
import '../../../core/widgets/hero_sky.dart';
import '../../../core/widgets/panda_rig.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/splash_timeline.dart';

/// Loads whatever must be ready before frame 0 of the animation.
typedef SplashPrepare = Future<void> Function(BuildContext context);

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    required this.onFinished,
    this.autoAdvance = SplashTimeline.autoAdvance,
    this.prepare = PandaAssets.precache,
    super.key,
  });

  /// Called once, on auto-advance or on the first tap.
  final VoidCallback onFinished;

  final Duration autoAdvance;

  /// Defaults to decoding the panda layers. Tests inject a no-op: image
  /// decoding needs real async, which a widget test's fake clock does not run.
  final SplashPrepare prepare;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  /// The one-shot timeline: ledge, rise, grip, paw, letters, tagline.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: SplashTimeline.introTotal),
  );

  /// The wave, played once from its cue: the swings, then the paw going down.
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: SplashTimeline.waveTotal),
  );

  /// One blink period, repeated.
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: SplashTimeline.blinkPeriod),
  );

  _SplashMotion? _motion;
  Timer? _advance;
  bool _started = false;
  bool _finished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motion != null) return;

    final reduced = reduceMotionOf(context);
    if (reduced) _intro.duration = MotionDurations.reduced;
    _motion = reduced
        ? _SplashMotion.reduced(_intro)
        : _SplashMotion.full(intro: _intro, wave: _wave, blink: _blink);
    if (!reduced) _intro.addListener(_startLoopsOnCue);

    // Hold at frame 0 until the layers have decoded, then start on the next
    // frame, so the first animated frame is never also a decode frame.
    widget
        .prepare(context)
        .timeout(SplashTimeline.prepareTimeout)
        .catchError((Object _) {})
        .whenComplete(() {
          if (!mounted) return;
          SchedulerBinding.instance.scheduleFrameCallback((_) => _start());
          SchedulerBinding.instance.scheduleFrame();
        });
  }

  void _start() {
    if (!mounted || _started) return;
    _started = true;
    _intro.forward();
    // The auto-advance clock starts with the animation, not with mount.
    _advance = Timer(widget.autoAdvance, _finish);
  }

  /// The wave and the blink run on their own controllers but start on the
  /// intro's clock, so a slow first frame delays everything equally.
  void _startLoopsOnCue() {
    final elapsed = _intro.value * SplashTimeline.introTotal;
    if (elapsed >= SplashTimeline.waveStart && _wave.isDismissed && !_wave.isAnimating) {
      _wave.forward();
    }
    if (elapsed >= SplashTimeline.blinkStart && !_blink.isAnimating) {
      _blink.repeat();
    }
    if (!_wave.isDismissed && _blink.isAnimating) {
      _intro.removeListener(_startLoopsOnCue);
    }
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    _advance?.cancel();
    widget.onFinished();
  }

  @override
  void dispose() {
    _advance?.cancel();
    _intro.dispose();
    _wave.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = _motion!;
    final l = L.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      // The splash sits above the Navigator, so no Scaffold gives it a
      // Material: without this, every Text gets the debug yellow underline.
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _finish,
          child: ColoredBox(
            color: BulletinColors.brand,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const BrandSky(heroSky),
                Padding(
                  padding: const EdgeInsets.fromLTRB(40, 48, 40, 64),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 96),
                            child: Semantics(
                              image: true,
                              label: l.pandaWavingLabel,
                              child: SizedBox(
                                width: 300,
                                child: PandaRig(
                                  ledge: motion.ledge,
                                  rise: motion.rise,
                                  grip: motion.grip,
                                  pawUp: motion.pawUp,
                                  waveDegrees: motion.waveDegrees,
                                  blink: motion.blink,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _Wordmark(letters: motion.letters, rise: motion.letterRise),
                      const SizedBox(height: Space.sm),
                      _Tagline(text: l.splashTagline, opacity: motion.tagline),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every animated value on the splash, derived from the controllers once.
///
/// Two constructors, because reduced motion is not "the same animation,
/// faster": the panda is simply static, the loops never start, and the text
/// collapses to one short linear fade (MOTION.md §1.9).
class _SplashMotion {
  _SplashMotion.full({
    required AnimationController intro,
    required AnimationController wave,
    required AnimationController blink,
  }) : ledge = _beat(intro, SplashTimeline.ledge, MotionCurves.splash),
       rise = _beat(intro, SplashTimeline.rise, MotionCurves.splash),
       grip = _beat(intro, SplashTimeline.grip, MotionCurves.splash),
       // Up with the intro, down at the end of the wave: whichever is lower.
       pawUp = AnimationMin<double>(
         _beat(intro, SplashTimeline.pawUp, MotionCurves.splash),
         ReverseAnimation(
           _beat(
             wave,
             SplashTimeline.pawDown,
             MotionCurves.wave,
             total: SplashTimeline.waveTotal,
           ),
         ),
       ),
       // Before the wave starts the controller sits at 0, which holds the
       // paw at waveFrom, as the spec requires.
       waveDegrees = _swings(wave),
       blink = TweenSequence<double>([
         TweenSequenceItem(tween: ConstantTween(0), weight: 90),
         TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 5),
         TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 5),
       ]).animate(blink),
       letters = [
         for (var i = 0; i < _brand.length; i++)
           _beat(intro, SplashTimeline.letter(i), MotionCurves.out),
       ],
       tagline = _beat(intro, SplashTimeline.tagline, MotionCurves.out),
       letterRise = SplashTimeline.letterRise;

  _SplashMotion.reduced(AnimationController intro)
    : ledge = kAlwaysCompleteAnimation,
      rise = kAlwaysCompleteAnimation,
      grip = kAlwaysCompleteAnimation,
      pawUp = kAlwaysCompleteAnimation,
      waveDegrees = const AlwaysStoppedAnimation(0),
      blink = kAlwaysDismissedAnimation,
      letters = List.filled(_brand.length, intro),
      tagline = intro,
      letterRise = 0;

  final Animation<double> ledge;
  final Animation<double> rise;
  final Animation<double> grip;
  final Animation<double> pawUp;
  final Animation<double> waveDegrees;
  final Animation<double> blink;
  final List<Animation<double>> letters;
  final Animation<double> tagline;
  final double letterRise;

  static Animation<double> _beat(
    AnimationController clock,
    Beat beat,
    Curve curve, {
    int total = SplashTimeline.introTotal,
  }) {
    return CurvedAnimation(
      parent: clock,
      curve: msInterval(
        delay: beat.delay,
        duration: beat.duration,
        total: total,
        curve: curve,
      ),
    );
  }

  /// The swings in sequence on the wave's clock, each eased on its own (the
  /// arm slows into every turn), then held at the last angle while the paw
  /// goes down.
  static Animation<double> _swings(AnimationController wave) {
    var from = SplashTimeline.waveFrom;
    final items = <TweenSequenceItem<double>>[];
    for (final swing in SplashTimeline.swings) {
      items.add(
        TweenSequenceItem(
          tween: Tween(
            begin: from,
            end: swing.to,
          ).chain(CurveTween(curve: MotionCurves.wave)),
          weight: swing.duration.toDouble(),
        ),
      );
      from = swing.to;
    }
    final rest = SplashTimeline.waveTotal - SplashTimeline.swingsTotal;
    items.add(TweenSequenceItem(tween: ConstantTween(from), weight: rest.toDouble()));
    return TweenSequence(items).animate(wave);
  }
}

/// The wordmark is the brand, the same in both languages, so it is not an l10n
/// string; it is split into letters only to animate them.
const _brand = 'Bulletin';

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.letters, required this.rise});

  final List<Animation<double>> letters;

  /// How far each letter rises, in px; 0 under reduced motion.
  final double rise;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _brand,
      header: true,
      child: ExcludeSemantics(
        // Large text scales the wordmark up until it meets the screen edge,
        // then no further: it is a logo, and a logo that wraps or clips is
        // worse than one that stops growing.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < letters.length; i++)
                _RisingLetter(_brand[i], progress: letters[i], rise: rise),
            ],
          ),
        ),
      ),
    );
  }
}

class _RisingLetter extends StatelessWidget {
  const _RisingLetter(this.letter, {required this.progress, required this.rise});

  final String letter;
  final Animation<double> progress;
  final double rise;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: progress,
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, rise * (1 - progress.value)),
          child: child,
        ),
        child: Text(letter, style: BulletinText.splashWordmark),
      ),
    );
  }
}

class _Tagline extends StatelessWidget {
  const _Tagline({required this.text, required this.opacity});

  final String text;
  final Animation<double> opacity;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: opacity,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: BulletinText.resolve(BulletinText.splashTagline, text),
        ),
      ),
    );
  }
}
