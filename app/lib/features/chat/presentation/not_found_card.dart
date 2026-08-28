/// The not-found card. Handoff spec §3, DESIGN §6.3, §8.
///
/// It must not resemble an answer, and the difference is structural rather
/// than decorative: no fill, a heavier border, muted text, and a header that
/// names the state ("No source found"). A student who cannot tell a refusal
/// from an answer will read the refusal as one.
///
/// The honesty line beneath it — "Answered from student-scoped documents
/// only" — is deliberate. Retrieval was audience-filtered (PRD §4), so the
/// truthful statement is "nothing YOU can see covers this", not "this does not
/// exist". Saying it in mono, quietly, keeps the claim accurate without
/// making a student feel walled off.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../../../l10n/app_localizations.dart';

class NotFoundCard extends StatelessWidget {
  const NotFoundCard({
    required this.text,
    required this.role,
    this.onRephrase,
    this.onSwitchLanguage,
    this.askInOtherLanguageLabel,
    super.key,
  });

  final String text;

  /// Decides which honesty line is true for this caller.
  final String role;

  final VoidCallback? onRephrase;
  final VoidCallback? onSwitchLanguage;
  final String? askInOtherLanguageLabel;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scopeNote = switch (role) {
      'admin' => l.scopeNoteAdmin,
      'teacher' => l.scopeNoteTeacher,
      _ => l.scopeNoteStudent,
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(right: Sizes.assistantRightInset, bottom: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(
              // No fill: `paper` would make it a card like any other.
              color: Colors.transparent,
              borderRadius: Radii.cardAll,
              border: Border.all(color: BulletinColors.hairlineStrong),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: BulletinColors.inkFaint, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 7,
                        height: 1.5,
                        color: BulletinColors.inkFaint,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Text(
                      l.notFoundTitle,
                      style: BulletinText.resolve(
                        BulletinText.sourceTitle.copyWith(color: BulletinColors.inkMuted),
                        l.notFoundTitle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Text(
                  text,
                  style: BulletinText.resolve(
                    BulletinText.messageBody.copyWith(color: BulletinColors.inkMuted),
                    text,
                  ),
                ),
                const SizedBox(height: Space.md),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    if (onRephrase != null)
                      _QuietAction(label: l.rephrase, onTap: onRephrase!),
                    if (onSwitchLanguage != null)
                      _QuietAction(
                        label: askInOtherLanguageLabel ?? l.askInBangla,
                        onTap: onSwitchLanguage!,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            scopeNote,
            style: BulletinText.resolve(
              BulletinText.meta.copyWith(
                fontFamily: Fonts.mono,
                color: BulletinColors.inkFaint,
              ),
              scopeNote,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuietAction extends StatelessWidget {
  const _QuietAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x0A1C1B2E),
      borderRadius: Radii.chipAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.chipAll,
        child: Container(
          constraints: const BoxConstraints(minHeight: Sizes.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          alignment: Alignment.center,
          child: Text(
            label,
            style: BulletinText.resolve(
              BulletinText.meta.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontVariations: Weights.medium,
              ),
              label,
            ),
          ),
        ),
      ),
    );
  }
}
