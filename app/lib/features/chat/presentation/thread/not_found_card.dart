/// The not-found card (CHANGES.md: "soft white card, 36 px round search
/// icon").
///
/// A refusal must not read as an answer: it has no panda-and-prose look, it
/// carries a "found nothing" icon, and it says what happened in the
/// institution's own terms. Under it, a quiet mono line states which
/// documents were searched. Retrieval is audience-filtered (PRD §4), so the
/// honest claim is "nothing YOU can see covers this", not "this does not
/// exist".
library;

import 'package:flutter/material.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../../../l10n/app_localizations.dart';

class NotFoundCard extends StatelessWidget {
  const NotFoundCard({required this.text, required this.role, super.key});

  final String text;

  /// Decides which scope line is true for this caller.
  final String role;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scope = switch (role) {
      'admin' => l.scopeNoteAdmin,
      'teacher' => l.scopeNoteTeacher,
      _ => l.scopeNoteStudent,
    };

    return FadeUp(
      duration: MotionDurations.stepIn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.sm,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: BulletinColors.threadCardStrong,
              borderRadius: BrandRadii.card,
              border: Border.all(color: BulletinColors.hairline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: BulletinColors.canvas,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: LineIcon(
                      LineIcons.searchMinus,
                      color: BulletinColors.muted,
                      size: 18,
                      strokeWidth: 1.9,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      text,
                      style: BulletinText.resolve(BulletinText.notFoundText, text),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              scope,
              style: BulletinText.resolve(
                BulletinText.meta.copyWith(
                  fontFamily: Fonts.mono,
                  color: BulletinColors.inkFaint,
                ),
                scope,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
