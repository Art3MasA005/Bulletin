/// What Bulletin is doing before the first word arrives (CHANGES.md,
/// "Working steps").
///
/// A soft card, white 60 %, radius 18. A finished step is a 20 px pale green
/// circle with a green check; the active one is a 10 px orange dot that
/// breathes. Each step fades up (250 ms `out`).
library;

import 'package:flutter/material.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../../../l10n/app_localizations.dart';

class WorkingSteps extends StatelessWidget {
  const WorkingSteps({this.readCourses, super.key});

  /// Courses read from the attached routine; shown as a finished step.
  final int? readCourses;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final read = readCourses;
    final steps = [
      if (read != null) _Step(label: l.stepReadCourses(read), done: true),
      _Step(label: l.stepSearching, done: false),
    ];

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Space.md),
        decoration: BoxDecoration(
          color: BulletinColors.threadCard,
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          border: Border.all(color: BulletinColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [for (final step in steps) _StepRow(step: step)],
        ),
      ),
    );
  }
}

class _Step {
  const _Step({required this.label, required this.done});
  final String label;
  final bool done;
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    return FadeUp(
      duration: MotionDurations.stepIn,
      child: Row(
        spacing: 10,
        children: [
          SizedBox.square(
            dimension: 20,
            child: step.done ? const _DoneMark() : const _ActiveDot(),
          ),
          Expanded(
            child: Text(
              step.label,
              style: BulletinText.resolve(BulletinText.stepLabel, step.label),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneMark extends StatelessWidget {
  const _DoneMark();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BulletinColors.stepDone,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: LineIcon(
          LineIcons.check,
          color: BulletinColors.success,
          size: 11,
          strokeWidth: 3.2,
        ),
      ),
    );
  }
}

/// 10 px dot, a 5 px halo, `blBreathe 1.6s`: scale 1 -> 1.04 -> 1.
class _ActiveDot extends StatefulWidget {
  const _ActiveDot();

  @override
  State<_ActiveDot> createState() => _ActiveDotState();
}

class _ActiveDotState extends State<_ActiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ScaleTransition(
        scale: Tween<double>(
          begin: 1,
          end: 1.04,
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: BulletinColors.brandStrong,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: BulletinColors.stepDotHalo, spreadRadius: 5)],
          ),
        ),
      ),
    );
  }
}
