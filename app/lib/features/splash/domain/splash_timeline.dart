/// The splash timeline, in the milliseconds the handoff specifies
/// (README §4, "Timeline"). Pure data: no Flutter, so it can be checked
/// against the spec without pumping a widget.
///
/// t = 0 is the moment all three panda layers have decoded, NOT the moment
/// the screen mounts. Everything holds at frame 0 until then.
library;

/// One element's slice of the shared clock.
typedef Beat = ({int delay, int duration});

/// One swing of the wave: the angle it swings TO, in degrees, and how long
/// it takes. Each swing starts where the previous one ended.
typedef Swing = ({double to, int duration});

extension BeatEnd on Beat {
  int get end => delay + duration;
}

abstract final class SplashTimeline {
  static const Beat ledge = (delay: 0, duration: 520);
  static const Beat rise = (delay: 180, duration: 900);
  static const Beat grip = (delay: 640, duration: 520);
  static const Beat pawUp = (delay: 720, duration: 600);

  /// The wave, from [waveStart]. Before it the paw holds at [waveFrom].
  ///
  /// It waves the way a person does and then stops: one and a half full
  /// swings between [waveFrom] and [waveTo], one smaller and slower swing
  /// back, then the paw settles upright (0°) and drops behind the ledge,
  /// leaving the panda peeking with its other paw on the ledge, as in the
  /// logo. Every swing turns only at its far end, so there is no hold
  /// mid-swing (the 0° stop the client rejected in an earlier build): the
  /// one place the arm comes to rest is the end.
  static const waveStart = 1100;
  static const waveFrom = 6.0;
  static const waveTo = -11.0;
  static const waveHalf = 520;

  static const List<Swing> swings = [
    (to: waveTo, duration: waveHalf),
    (to: waveFrom, duration: waveHalf),
    (to: waveTo, duration: waveHalf),
    (to: 4, duration: 560),
    (to: 0, duration: 420),
  ];

  /// When the swinging is over, relative to [waveStart].
  static int get swingsTotal => swings.fold(0, (sum, s) => sum + s.duration);

  /// The paw dropping behind the ledge, relative to [waveStart]. It starts
  /// during the last swing so the arm lowers as it settles, in one motion.
  static const Beat pawDown = (delay: 2200, duration: 620);

  /// The wave's own clock: from [waveStart] until the paw is down.
  static const waveTotal = 2820;

  /// The eyes close briefly once every [blinkPeriod], from [blinkStart].
  static const blinkStart = 1700;
  static const blinkPeriod = 3200;

  /// "Bulletin", letter by letter: each rises [letterRise] px and fades in.
  static const letterDelay = 1450;
  static const letterStagger = 50;
  static const letterDuration = 520;
  static const letterRise = 14.0;

  static Beat letter(int index) =>
      (delay: letterDelay + letterStagger * index, duration: letterDuration);

  static const Beat tagline = (delay: 1950, duration: 600);

  /// The one-shot part of the timeline ends when the tagline lands.
  static const introTotal = 2550;

  /// First launch: the full show, then on to Welcome.
  static const autoAdvance = Duration(milliseconds: 4200);

  /// A signed-in user has seen the show. The splash leaves once the tagline
  /// has landed instead of holding for the full 4.2 s on every cold start.
  static const autoAdvanceReturning = Duration(milliseconds: introTotal + 50);

  /// Splash out (fade + scale to [exitScale]) and the screen beneath fading
  /// in, which overlap.
  static const exit = Duration(milliseconds: 420);
  static const exitScale = 1.06;
  static const reveal = Duration(milliseconds: 300);

  /// How long to wait for the panda layers before starting regardless. A
  /// bundled PNG decodes in milliseconds; this exists so a decode failure
  /// can never strand the user on the splash.
  static const prepareTimeout = Duration(seconds: 2);
}
