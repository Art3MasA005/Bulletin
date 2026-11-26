/// A pushed screen (README §5 "Push screen", "Edge-swipe back").
///
/// The incoming screen slides in from 100% to 0 while the one below moves to
/// −30% under a .08 black scrim, 400 ms `out`; pop runs it backwards. The
/// screen below is moved through `delegatedTransition`, so it slides the
/// same way whatever route it is, and its own page transition stays still.
///
/// Back by dragging from a 24 px left edge zone, 1:1 with the finger: past
/// 35% of the width, or flung faster than 800 px/s, it pops; otherwise it
/// springs back over 300 ms `back`.
///
/// Reduced motion: a 150 ms fade, nothing moves (MOTION.md).
library;

import 'package:flutter/widgets.dart';

import '../motion/motion.dart';
import '../theme/theme.dart';

class PushRoute<T> extends PageRoute<T> {
  PushRoute({required this.builder, required this.reduceMotion, super.settings});

  /// A push that reads reduced motion where it is pushed from.
  factory PushRoute.of(BuildContext context, WidgetBuilder builder) =>
      PushRoute(builder: builder, reduceMotion: reduceMotionOf(context));

  final WidgetBuilder builder;
  final bool reduceMotion;

  static const _duration = Duration(milliseconds: 400);
  static const _edge = 24.0;
  static const _commitFraction = 0.35;
  static const _commitVelocity = 800.0;
  static const _springBack = Duration(milliseconds: 300);
  static const _below = -0.3;

  @override
  Duration get transitionDuration => reduceMotion ? MotionDurations.reduced : _duration;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  /// Linear under a finger, `out` otherwise.
  Animation<double> _curved(Animation<double> animation) =>
      (navigator?.userGestureInProgress ?? false)
      ? animation
      : CurvedAnimation(parent: animation, curve: MotionCurves.out);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion) return FadeTransition(opacity: animation, child: child);
    return SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(_curved(animation)),
      child: Stack(
        children: [
          child,
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _edge,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => _dragStart(),
              onHorizontalDragUpdate: (d) => _dragUpdate(d.primaryDelta ?? 0, context),
              onHorizontalDragEnd: (d) => _dragEnd(d.primaryVelocity ?? 0),
              onHorizontalDragCancel: () => _dragEnd(0),
            ),
          ),
        ],
      ),
    );
  }

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      reduceMotion ? null : _belowTransition;

  static Widget? _belowTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    final t = CurvedAnimation(parent: secondaryAnimation, curve: MotionCurves.out);
    return SlideTransition(
      position: Tween(begin: Offset.zero, end: const Offset(_below, 0)).animate(t),
      child: Stack(
        children: [
          ?child,
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: t,
                child: const ColoredBox(color: BulletinColors.pushScrim),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── edge swipe ─────────────────────────────────────────────────────────────

  bool _dragging = false;

  void _dragStart() {
    if (isFirst || !isCurrent || _dragging) return;
    _dragging = true;
    navigator?.didStartUserGesture();
  }

  void _dragUpdate(double dx, BuildContext context) {
    if (!_dragging) return;
    final width = MediaQuery.sizeOf(context).width;
    controller?.value -= dx / width;
  }

  void _dragEnd(double velocity) {
    if (!_dragging) return;
    _dragging = false;
    final controller = this.controller!;
    final pop = velocity > _commitVelocity || controller.value < 1 - _commitFraction;
    if (pop) {
      navigator?.pop();
    } else {
      controller.animateTo(1, duration: _springBack, curve: MotionCurves.springBack);
    }
    if (controller.isAnimating) {
      void done(AnimationStatus status) {
        if (status.isAnimating) return;
        controller.removeStatusListener(done);
        navigator?.didStopUserGesture();
      }

      controller.addStatusListener(done);
    } else {
      navigator?.didStopUserGesture();
    }
  }
}
