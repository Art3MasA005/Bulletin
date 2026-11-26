/// The motion primitives every screen is built from (MOTION.md §3, §4, §6).
///
/// Each one degrades the same way under reduced motion: movement and scale
/// disappear, a 150 ms opacity fade remains (MOTION.md §1.9). That rule lives
/// here, once, so no screen can forget it.
library;

import 'package:flutter/material.dart';

import 'motion.dart';

/// Fades in while travelling [offset] px to rest. Positive rises from below
/// (`fadeUp`); negative drops from above (`slideDown`, for field errors).
///
/// The delay is part of the controller's timeline rather than a [Timer], so a
/// widget test's fake clock drives it like any other frame.
class FadeUp extends StatefulWidget {
  const FadeUp({
    required this.child,
    this.offset = 12,
    this.duration = MotionDurations.section,
    this.delay = Duration.zero,
    this.curve = MotionCurves.out,
    super.key,
  });

  final Widget child;
  final double offset;
  final Duration duration;
  final Duration delay;
  final Curve curve;

  @override
  State<FadeUp> createState() => _FadeUpState();
}

class _FadeUpState extends State<FadeUp> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  late Animation<double> _progress;
  late double _offset;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (reduceMotionOf(context)) {
      _controller.duration = MotionDurations.reduced;
      _progress = _controller;
      _offset = 0;
    } else {
      final total = widget.delay + widget.duration;
      _controller.duration = total;
      _progress = CurvedAnimation(
        parent: _controller,
        curve: Interval(
          total == Duration.zero ? 0 : widget.delay.inMicroseconds / total.inMicroseconds,
          1,
          curve: widget.curve,
        ),
      );
      _offset = widget.offset;
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _progress,
      child: AnimatedBuilder(
        animation: _progress,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, _offset * (1 - _progress.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Press feedback (MOTION.md §4.1): down in 100 ms `out`, back up in 150 ms
/// `spring`. Use [PressScale.button] (.98) on full-width buttons and
/// [PressScale.icon] (.92) on icon and round buttons.
///
/// It only animates; the tap itself, and its semantics, belong to the
/// child's own button, so the press never steals an accessibility action.
class PressScale extends StatefulWidget {
  const PressScale({
    required this.child,
    required this.scale,
    this.enabled = true,
    super.key,
  });

  const PressScale.button({required Widget child, bool enabled = true, Key? key})
    : this(child: child, scale: 0.98, enabled: enabled, key: key);

  const PressScale.icon({required Widget child, bool enabled = true, Key? key})
    : this(child: child, scale: 0.92, enabled: enabled, key: key);

  final Widget child;
  final double scale;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  // Trivial local animation state: the CLAUDE.md exception for setState.
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _pressed && widget.enabled && !reduceMotionOf(context);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: pressed ? widget.scale : 1,
        duration: pressed ? MotionDurations.press : MotionDurations.micro,
        curve: pressed ? MotionCurves.out : MotionCurves.spring,
        child: widget.child,
      ),
    );
  }
}

/// Shakes its child sideways each time [trigger] changes: X 0, −10, 9, −6,
/// 4, 0 over 420 ms, 120 ms after the trigger (MOTION.md §4.3). The wrong
/// password state. No shake at all under reduced motion; the red border and
/// the message carry the meaning on their own.
class Shake extends StatefulWidget {
  const Shake({required this.trigger, required this.child, super.key});

  /// Any value; a new value replays the shake. A counter of failed attempts
  /// works, so a second wrong password shakes again.
  final Object? trigger;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  static const _delay = 120;
  static const _duration = 420;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _delay + _duration),
  );

  late final Animation<double> _dx = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0), weight: _delay.toDouble()),
    for (final (from, to) in const [
      (0.0, -10.0),
      (-10.0, 9.0),
      (9.0, -6.0),
      (-6.0, 4.0),
      (4.0, 0.0),
    ])
      TweenSequenceItem(
        tween: Tween(begin: from, end: to).chain(CurveTween(curve: Curves.easeInOut)),
        weight: _duration / 5,
      ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(Shake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger &&
        widget.trigger != null &&
        !reduceMotionOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _dx,
      builder: (context, child) =>
          Transform.translate(offset: Offset(_dx.value, 0), child: child),
      child: widget.child,
    );
  }
}

/// A check or badge popping in: scale 0 → 1.14 → 1 over 450 ms `spring`,
/// after [delay] (MOTION.md §6.7). A fade under reduced motion.
class PopIn extends StatefulWidget {
  const PopIn({required this.child, this.delay = Duration.zero, super.key});

  final Widget child;
  final Duration delay;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  late Animation<double> _scale;
  late Animation<double> _opacity;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (reduceMotionOf(context)) {
      _controller.duration = MotionDurations.reduced;
      _scale = kAlwaysCompleteAnimation;
      _opacity = _controller;
    } else {
      final total = widget.delay + MotionDurations.sheetIn;
      _controller.duration = total;
      final start = widget.delay.inMicroseconds / total.inMicroseconds;
      _scale = TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 0, end: 1.14), weight: 60),
        TweenSequenceItem(tween: Tween(begin: 1.14, end: 1), weight: 40),
      ]).animate(CurvedAnimation(parent: _controller, curve: Interval(start, 1)));
      _opacity = kAlwaysCompleteAnimation;
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

enum NavDirection { forward, back }

/// Steps inside one screen (MOTION.md §3.2, §6.5). Forward: the old step
/// lifts 8 px and fades in 150 ms (`exit`); the new one rises 12 px over
/// 250 ms (`out`), starting at 90 ms. Back mirrors it. Give each step a
/// distinct key.
class StepSwitcher extends StatelessWidget {
  const StepSwitcher({required this.direction, required this.child, super.key});

  final NavDirection direction;
  final Widget child;

  static const _total = Duration(milliseconds: 340);
  static const _inDelay = 90 / 340;

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotionOf(context);
    final forward = direction == NavDirection.forward;
    final enterFrom = reduced ? 0.0 : (forward ? 12.0 : -12.0);
    final exitTo = reduced ? 0.0 : (forward ? -8.0 : 12.0);

    return AnimatedSwitcher(
      duration: reduced ? MotionDurations.reduced : _total,
      reverseDuration: reduced ? MotionDurations.reduced : MotionDurations.stepOut,
      switchInCurve: reduced
          ? Curves.linear
          : const Interval(_inDelay, 1, curve: MotionCurves.out),
      switchOutCurve: reduced ? Curves.linear : MotionCurves.exit.flipped,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      transitionBuilder: (step, animation) {
        final incoming = step.key == child.key;
        final distance = incoming ? enterFrom : exitTo;
        return FadeTransition(
          opacity: animation,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, inner) => Transform.translate(
              offset: Offset(0, distance * (1 - animation.value)),
              child: inner,
            ),
            // The outgoing step stops taking input at frame 0 (MOTION.md §1.7).
            // Always wrapped, so becoming "outgoing" never changes the widget
            // type and remounts the step (its fields would blank mid-fade).
            child: IgnorePointer(ignoring: !incoming, child: step),
          ),
        );
      },
      child: child,
    );
  }
}
