/// The hand-over between the app's phases (handoff README §5, MOTION.md
/// "Auth complete → main app").
///
/// Into the main app: the layer that was showing stays ON TOP, fades out and
/// scales up to 1.03 over 400 ms `exit`, and Home is already there beneath
/// it (its own sections rise in from 200 ms). Anywhere else (signing out,
/// signed in but not yet a member): the arriving screen fades in over the
/// old one in 300 ms `out`. Reduced motion: a 150 ms fade either way.
///
/// While membership is still loading the previous screen stays up, so a
/// sign-in goes straight from Sign in to Home with no spinner flashing
/// between them. Only a cold start, with nothing before it, shows the
/// loading screen (and the splash covers that).
library;

import 'package:flutter/widgets.dart';

import '../motion/motion.dart';
import 'app_phase.dart';

class PhaseSwitcher extends StatefulWidget {
  const PhaseSwitcher({required this.phase, required this.child, super.key});

  final AppPhase phase;
  final Widget child;

  static const handOver = Duration(milliseconds: 400);
  static const arrive = Duration(milliseconds: 300);
  static const handOverScale = 1.03;

  @override
  State<PhaseSwitcher> createState() => _PhaseSwitcherState();
}

class _PhaseSwitcherState extends State<PhaseSwitcher>
    with SingleTickerProviderStateMixin {
  late AppPhase _phase = widget.phase;
  late Widget _child = widget.child;

  /// The screen being left, while it animates away.
  AppPhase? _leavingPhase;
  Widget? _leaving;
  bool _intoMain = false;

  late final AnimationController _clock = AnimationController(vsync: this);

  @override
  void didUpdateWidget(PhaseSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.phase;

    // Hold the current screen while membership loads.
    if (next == AppPhase.loading && _phase != AppPhase.loading) return;

    if (next == _phase) {
      _child = widget.child;
      return;
    }

    _leavingPhase = _phase;
    _leaving = _child;
    _phase = next;
    _child = widget.child;
    _intoMain = next == AppPhase.main;

    final reduced = reduceMotionOf(context);
    _clock.duration = reduced
        ? MotionDurations.reduced
        : (_intoMain ? PhaseSwitcher.handOver : PhaseSwitcher.arrive);
    _clock.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted) return;
      setState(() {
        _leaving = null;
        _leavingPhase = null;
      });
    });
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotionOf(context);
    final leaving = _leaving;

    Widget layer(AppPhase phase, Widget child, _Role role) => _Layer(
      key: ValueKey(phase),
      clock: _clock,
      role: role,
      scaleUp: !reduced,
      child: child,
    );

    // Always a Stack, and every screen always inside the same _Layer, so a
    // screen keeps its element (and its state, its typed text, its finished
    // entrance) when it starts leaving. Re-parenting it would rebuild it from
    // scratch mid-transition.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (leaving == null)
          layer(_phase, _child, _Role.still)
        else if (_intoMain) ...[
          // Home beneath, already there; the old layer on top, leaving.
          layer(_phase, _child, _Role.still),
          layer(_leavingPhase!, leaving, _Role.leaving),
        ] else ...[
          layer(_leavingPhase!, leaving, _Role.behind),
          layer(_phase, _child, _Role.arriving),
        ],
      ],
    );
  }
}

enum _Role { still, leaving, arriving, behind }

/// One screen in the switcher. Same widget types in every role, so moving
/// between roles never rebuilds the screen beneath.
class _Layer extends StatelessWidget {
  const _Layer({
    required this.clock,
    required this.role,
    required this.scaleUp,
    required this.child,
    super.key,
  });

  final Animation<double> clock;
  final _Role role;
  final bool scaleUp;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // A leaving or covered screen is deaf: taps go to the one arriving.
      ignoring: role == _Role.leaving || role == _Role.behind,
      child: AnimatedBuilder(
        animation: clock,
        child: child,
        builder: (context, child) {
          var opacity = 1.0;
          var scale = 1.0;
          switch (role) {
            case _Role.leaving:
              final t = MotionCurves.exit.transform(clock.value);
              opacity = 1 - t;
              if (scaleUp) scale = 1 + (PhaseSwitcher.handOverScale - 1) * t;
            case _Role.arriving:
              opacity = MotionCurves.out.transform(clock.value);
            case _Role.still:
            case _Role.behind:
              break;
          }
          return Opacity(
            opacity: opacity,
            child: Transform.scale(scale: scale, child: child),
          );
        },
      ),
    );
  }
}
