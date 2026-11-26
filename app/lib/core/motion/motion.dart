/// The motion system. `docs/design/handoff/MOTION.md` is the source of truth;
/// handoff README §5 adds the per-screen timings.
///
/// Every curve and duration in the app comes from here, for the same reason
/// every colour comes from `tokens.dart`: a timing that lives at a call site
/// drifts from the spec and nobody notices until the app feels inconsistent.
///
/// The rules this encodes, in short: enters decelerate (`out`), exits
/// accelerate (`exit`) and run shorter, small things spring, big things glide,
/// and under reduced motion every slide, scale and stagger becomes a short
/// opacity fade while loops stop.
library;

import 'package:flutter/widgets.dart';

abstract final class MotionCurves {
  /// Screen and section enter, push, pop, indicators, progress bars.
  static const out = Cubic(0.33, 1, 0.68, 1);

  /// Every exit, dismiss and close; the splash exit.
  static const exit = Cubic(0.32, 0, 0.67, 0);

  /// Pop-in, dots, toggle knobs, check badges, icon rotation.
  static const spring = Cubic(0.34, 1.56, 0.64, 1);

  /// Bottom sheet enter, with a slight overshoot.
  static const sheet = Cubic(0.34, 1.25, 0.64, 1);

  /// A released drag that returns.
  static const springBack = Cubic(0.34, 1.3, 0.64, 1);

  /// A hero element landing.
  static const softPop = Cubic(0.34, 1.4, 0.64, 1);

  /// The panda's rise, grip and ledge (handoff README §4).
  static const splash = Cubic(0.22, 1, 0.36, 1);

  /// The panda's wave. Symmetric, so a ping-pong reads the same both ways.
  static const wave = Cubic(0.37, 0, 0.63, 1);
}

abstract final class MotionDurations {
  static const press = Duration(milliseconds: 100);
  static const micro = Duration(milliseconds: 150);
  static const fastOut = Duration(milliseconds: 120);
  static const stepOut = Duration(milliseconds: 150);
  static const fade = Duration(milliseconds: 200);
  static const toggle = Duration(milliseconds: 220);
  static const stepIn = Duration(milliseconds: 250);
  static const sheetOut = Duration(milliseconds: 280);
  static const menuOut = Duration(milliseconds: 300);
  static const pop = Duration(milliseconds: 340);
  static const section = Duration(milliseconds: 400);
  static const sheetIn = Duration(milliseconds: 450);
  static const heroSheet = Duration(milliseconds: 520);
  static const count = Duration(milliseconds: 900);
  static const stagger = Duration(milliseconds: 40);

  /// What every slide, scale and stagger collapses to under reduced motion.
  static const reduced = Duration(milliseconds: 150);

  /// The streaming caret's pulse. A loop, so it stops under reduced motion.
  static const caretPulse = Duration(milliseconds: 1300);
}

/// Whether the user has asked the platform for less motion.
///
/// Read through here rather than `MediaQuery` directly so the rule has one
/// name in the codebase and one place to change if it grows (an in-app
/// override, say).
bool reduceMotionOf(BuildContext context) => MediaQuery.disableAnimationsOf(context);

/// An [Interval] expressed in the milliseconds the spec is written in.
///
/// The handoff gives every keyframe as "duration D after delay T" on a shared
/// clock. One controller of length [total] plays the whole timeline, and each
/// element reads its own slice of it, so the elements cannot drift apart.
Interval msInterval({
  required int delay,
  required int duration,
  required int total,
  Curve curve = Curves.linear,
}) {
  assert(delay + duration <= total, 'interval ends after the timeline does');
  return Interval(delay / total, (delay + duration) / total, curve: curve);
}
