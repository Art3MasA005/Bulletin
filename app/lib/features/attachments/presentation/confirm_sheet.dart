/// The extraction confirmation sheet. CLAUDE.md #3, PRD §8.3, DESIGN §5.
///
/// This is a correctness boundary, not a review screen. OCR on an alphanumeric
/// course code fails silently: `CSE 3103` read as `CSE 3108` produces a
/// perfectly confident answer about the wrong exam, and no stage after this
/// one can tell the difference. So the codes are rendered as *editable* mono
/// fields rather than a read-only list, and the sheet returns nothing at all
/// unless the user presses the confirm button.
///
/// Two consequences follow, and both are deliberate:
///
///   * Dismissing the sheet — swipe, back gesture, cancel — yields `null`.
///     Nothing is confirmed by walking away from it.
///   * A failed extraction is not a dead end. `ok == false` opens the sheet
///     with one empty row and the "add them by hand" copy, because a student
///     holding a photograph the model could not read still has a question.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/extraction.dart';

/// Opens the sheet and resolves to the confirmed codes, or `null` if the user
/// backed out without confirming.
Future<List<String>?> showConfirmExtractionSheet(
  BuildContext context,
  RoutineExtraction extraction,
) {
  return showModalBottomSheet<List<String>>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: BulletinColors.scrim,
    isScrollControlled: true,
    builder: (context) => ConfirmExtractionSheet(extraction: extraction),
  );
}

class ConfirmExtractionSheet extends StatefulWidget {
  const ConfirmExtractionSheet({required this.extraction, super.key});

  final RoutineExtraction extraction;

  @override
  State<ConfirmExtractionSheet> createState() => _ConfirmExtractionSheetState();
}

class _ConfirmExtractionSheetState extends State<ConfirmExtractionSheet> {
  late final List<_Row> _rows;

  @override
  void initState() {
    super.initState();
    _rows = [
      for (final course in widget.extraction.courses) _Row.from(course),
      // Nothing read: give the user the empty row rather than an empty sheet.
      if (widget.extraction.courses.isEmpty) _Row.blank(),
    ];
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.controller.dispose();
    }
    super.dispose();
  }

  List<String> get _codes => [
    for (final row in _rows)
      if (row.controller.text.trim().isNotEmpty) row.controller.text.trim().toUpperCase(),
  ];

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final failed = !widget.extraction.ok;
    final title = failed ? l.extractionFailed : l.foundCourses(_rows.length);

    return Padding(
      // The sheet holds text fields; without this it sits under the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: BulletinColors.paper,
          borderRadius: Radii.sheetTop,
        ),
        padding: const EdgeInsets.fromLTRB(
          Sizes.sheetPadding,
          Sizes.sheetPadding,
          Sizes.sheetPadding,
          Space.md,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: BulletinText.resolve(BulletinText.sheetTitle, title)),
              if (widget.extraction.semester case final semester?) ...[
                const SizedBox(height: Space.xs),
                Text(
                  semester,
                  style: BulletinText.courseCode.copyWith(
                    fontSize: 12,
                    color: BulletinColors.inkMuted,
                  ),
                ),
              ],
              const SizedBox(height: Space.lg),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
                  itemBuilder: (context, index) => _CourseRow(
                    row: _rows[index],
                    onRemove: _rows.length == 1
                        ? null
                        : () =>
                              setState(() => _rows.removeAt(index).controller.dispose()),
                    onChanged: () => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(height: Space.sm),
              _AddRowButton(
                label: l.addCourse,
                onTap: () => setState(() => _rows.add(_Row.blank())),
              ),
              const SizedBox(height: Space.lg),
              _ConfirmButton(
                label: l.confirmCta,
                // Confirming zero courses would send a join query with nothing
                // to join on.
                enabled: _codes.isNotEmpty,
                onTap: () => Navigator.pop(context, _codes),
              ),
              const SizedBox(height: Space.xs),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  l.cancelAction,
                  style: BulletinText.resolve(
                    BulletinText.meta.copyWith(fontSize: 14),
                    l.cancelAction,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One editable course. The mono field is the whole point of the sheet.
class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.row, required this.onChanged, this.onRemove});

  final _Row row;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final flagged = row.course?.needsReview ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
      decoration: BoxDecoration(
        color: flagged ? BulletinColors.warnTint : BulletinColors.chipFill,
        borderRadius: Radii.chipAll,
        border: Border.all(
          color: flagged
              ? BulletinColors.warn.withValues(alpha: 0.35)
              : BulletinColors.hairlineInput,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: row.controller,
                  onChanged: (_) => onChanged(),
                  textCapitalization: TextCapitalization.characters,
                  // Course codes are ASCII by definition, in both locales.
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 \-]')),
                  ],
                  style: BulletinText.courseCode.copyWith(
                    fontSize: 15,
                    color: BulletinColors.ink,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (row.course?.title case final title? when title.isNotEmpty)
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BulletinText.resolve(
                      BulletinText.meta.copyWith(fontSize: 12),
                      title,
                    ),
                  ),
                if (flagged) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: BulletinColors.warn,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      Flexible(
                        child: Text(
                          l.checkThisOne(row.course!.confidenceLabel),
                          style: BulletinText.meta.copyWith(
                            fontSize: 11,
                            color: BulletinColors.warn,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              iconSize: 18,
              tooltip: l.removeAttachment,
              constraints: const BoxConstraints(
                minWidth: Sizes.minTouchTarget,
                minHeight: Sizes.minTouchTarget,
              ),
              icon: const Icon(Icons.close, color: BulletinColors.inkFaint),
            ),
        ],
      ),
    );
  }
}

class _AddRowButton extends StatelessWidget {
  const _AddRowButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.chipAll,
        child: Container(
          height: Sizes.minTouchTarget,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, size: 18, color: BulletinColors.accent),
              const SizedBox(width: Space.xs),
              Text(
                label,
                style: BulletinText.resolve(
                  BulletinText.meta.copyWith(
                    fontSize: 14,
                    color: BulletinColors.accent,
                    fontWeight: FontWeight.w500,
                    fontVariations: Weights.medium,
                  ),
                  label,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({required this.label, required this.enabled, required this.onTap});

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: Radii.pillAll,
        boxShadow: enabled ? Lifts.accentButton : const <BoxShadow>[],
      ),
      child: Material(
        color: enabled ? BulletinColors.accent : BulletinColors.inert,
        borderRadius: Radii.pillAll,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: Radii.pillAll,
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: BulletinText.resolve(
                  BulletinText.messageBody.copyWith(
                    color: BulletinColors.paper,
                    fontWeight: FontWeight.w600,
                    fontVariations: Weights.semiBold,
                  ),
                  label,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row's editable state. The original `course` is kept only so the row can
/// keep showing its title and its low-confidence warning while the user edits
/// the code — the code itself always comes from the controller.
class _Row {
  _Row({required this.controller, this.course});

  factory _Row.from(ExtractedCourse course) => _Row(
    controller: TextEditingController(text: course.code),
    course: course,
  );

  factory _Row.blank() => _Row(controller: TextEditingController());

  final TextEditingController controller;
  final ExtractedCourse? course;
}
