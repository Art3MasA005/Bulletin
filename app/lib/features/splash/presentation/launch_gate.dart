/// Puts the splash above the whole app and hands over to it.
///
/// It sits above the Navigator (in `MaterialApp.builder`), so the app beneath
/// is built DURING the splash: auth is restored and the membership request is
/// in flight while the panda waves, instead of starting after it.
///
/// The handover, from handoff README §5 and MOTION.md §3.8: the splash fades
/// out and grows to 1.06 over 420 ms (`exit`) while the app fades in over
/// 300 ms (`out`) beneath it. The splash stops taking input the moment it
/// starts to leave.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/widgets/panda_rig.dart';
import '../domain/launch_phase.dart';
import '../domain/splash_timeline.dart';
import 'launch_controller.dart';
import 'splash_screen.dart';

class LaunchGate extends ConsumerStatefulWidget {
  const LaunchGate({required this.child, this.prepare = PandaAssets.precache, super.key});

  /// The app: the Navigator and everything in it.
  final Widget child;

  /// Passed through to [SplashScreen.prepare].
  final SplashPrepare prepare;

  @override
  ConsumerState<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends ConsumerState<LaunchGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: SplashTimeline.exit,
  );

  late Animation<double> _splashOpacity;
  late Animation<double> _splashScale;
  late Animation<double> _appOpacity;
  bool _wired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;

    if (reduceMotionOf(context)) {
      // One short linear crossfade, no scale (MOTION.md §1.9).
      _exit.duration = MotionDurations.reduced;
      _splashOpacity = ReverseAnimation(_exit);
      _splashScale = kAlwaysCompleteAnimation;
      _appOpacity = _exit;
      return;
    }

    final leaving = CurvedAnimation(parent: _exit, curve: MotionCurves.exit);
    _splashOpacity = Tween<double>(begin: 1, end: 0).animate(leaving);
    _splashScale = Tween<double>(
      begin: 1,
      end: SplashTimeline.exitScale,
    ).animate(leaving);
    _appOpacity = CurvedAnimation(
      parent: _exit,
      curve: Interval(
        0,
        SplashTimeline.reveal.inMilliseconds / SplashTimeline.exit.inMilliseconds,
        curve: MotionCurves.out,
      ),
    );
  }

  void _onSplashFinished() {
    final launch = ref.read(launchPhaseProvider.notifier);
    launch.beginReveal();
    _exit.forward().whenCompleteOrCancel(() {
      if (mounted) launch.complete();
    });
  }

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(launchPhaseProvider);

    // The app stays the FIRST child of a Stack for the gate's whole life, so
    // removing the splash later never remounts it and never loses its state.
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: phase == LaunchPhase.splash,
          child: FadeTransition(
            opacity: _appOpacity,
            // Dark status-bar icons by default once the orange splash is
            // gone; a screen with its own coloured header sets its own region.
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.dark,
              child: widget.child,
            ),
          ),
        ),
        if (phase != LaunchPhase.done)
          IgnorePointer(
            ignoring: phase != LaunchPhase.splash,
            child: FadeTransition(
              opacity: _splashOpacity,
              child: ScaleTransition(
                scale: _splashScale,
                child: SplashScreen(
                  onFinished: _onSplashFinished,
                  autoAdvance: ref.read(splashAutoAdvanceProvider),
                  prepare: widget.prepare,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
