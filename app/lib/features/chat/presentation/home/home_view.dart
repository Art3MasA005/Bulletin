/// Home (handoff README §2.6; prototype `L.main`, `v.empty`): what a member
/// sees before the first question.
///
/// The breathing orb, "Hi {name}, what do you want to know today?", the
/// line saying where answers come from, and a row of glass chips: "Attach
/// routine" first, then suggested questions. The suggestions are not filler.
/// A student who has never used the app does not know what it can answer,
/// and concrete questions teach that faster than any onboarding copy.
///
/// Motion (prototype `home.a0`, `a2`, chips): the centre rises 400 ms after
/// 200, the chip row 400 ms after 280, each chip 400 ms after 320 + 40 i.
library;

import 'package:flutter/material.dart';

import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../../../l10n/app_localizations.dart';
import 'breathing_orb.dart';
import 'glass_chip.dart';

class HomeView extends StatelessWidget {
  const HomeView({
    required this.greeting,
    required this.institutionLine,
    required this.onAsk,
    required this.onAttach,
    super.key,
  });

  final String greeting;
  final String institutionLine;
  final void Function(String question) onAsk;
  final VoidCallback onAttach;

  /// Suggestions the corpus can answer, in both scripts: the row itself
  /// shows that a question can be asked in either language.
  static List<String> suggestions(L l) => [
    l.suggestExamStart,
    l.suggestMakeupFee,
    l.suggestHostelBn,
    l.suggestHoliday,
    l.suggestExamBn,
  ];

  static const _rise = Duration(milliseconds: 400);

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final asks = suggestions(l);

    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: FadeUp(
                duration: _rise,
                delay: const Duration(milliseconds: 200),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 28,
                  children: [
                    const BreathingOrb(),
                    Column(
                      spacing: 10,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            greeting,
                            textAlign: TextAlign.center,
                            style: BulletinText.resolve(
                              BulletinText.homeGreeting,
                              greeting,
                            ),
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(
                            institutionLine,
                            textAlign: TextAlign.center,
                            style: BulletinText.resolve(
                              BulletinText.homeNote,
                              institutionLine,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        FadeUp(
          duration: _rise,
          delay: const Duration(milliseconds: 280),
          // Room above and below for the glass's soft outer shadow, which a
          // tight scroll view would cut off.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              spacing: Space.sm,
              children: [
                GlassChip(
                  label: l.homeAttachRoutine,
                  glyph: LineIcons.paperclip,
                  onTap: onAttach,
                ),
                for (final (i, ask) in asks.indexed)
                  FadeUp(
                    duration: _rise,
                    delay: Duration(milliseconds: 320 + 40 * i),
                    child: GlassChip(
                      label: ask,
                      glyph: LineIcons.sparkle,
                      onTap: () => onAsk(ask),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
