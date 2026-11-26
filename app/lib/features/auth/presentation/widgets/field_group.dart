/// A labelled field: the label, an optional quiet note after it
/// ("· Optional"), the field, then a helper or an error below.
///
/// Two weights, both in the prototype: quiet (13/500, gap 6) on the canvas
/// steps, and [strong] (13/600, gap 8) on the white sheet of Sign in and
/// Sign up.
library;

import 'package:flutter/widgets.dart';

import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/line_icons.dart';

class FieldGroup extends StatelessWidget {
  const FieldGroup({
    required this.label,
    required this.field,
    this.note,
    this.below,
    this.strong = false,
    super.key,
  });

  final bool strong;

  final String label;

  /// Muted text after the label, such as "Optional".
  final String? note;
  final Widget field;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final labelStyle = strong ? BulletinText.fieldLabel : BulletinText.fieldLabelQuiet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: strong ? Space.sm : 6,
      children: [
        // The field carries the label for screen readers.
        ExcludeSemantics(
          child: Text.rich(
            TextSpan(
              text: label,
              children: [
                // "Optional": 12/500 muted, set a little apart.
                if (note case final quiet?)
                  TextSpan(
                    text: '  $quiet',
                    style: BulletinText.resolve(BulletinText.fieldHelper, quiet).copyWith(
                      fontWeight: FontWeight.w500,
                      fontVariations: Weights.medium,
                    ),
                  ),
              ],
            ),
            style: BulletinText.resolve(labelStyle, label),
          ),
        ),
        field,
        ?below,
      ],
    );
  }
}

/// The grey line under a field, optionally led by a 16 px icon (the Join
/// code's info mark).
class FieldHelper extends StatelessWidget {
  const FieldHelper(this.text, {this.glyph, super.key});

  final String text;
  final LineGlyph? glyph;

  @override
  Widget build(BuildContext context) {
    final line = Text(text, style: BulletinText.resolve(BulletinText.fieldHelper, text));
    if (glyph == null) return line;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: LineIcon(
            glyph!,
            color: BulletinColors.mutedIcon,
            size: 16,
            strokeWidth: 1.9,
          ),
        ),
        Expanded(child: line),
      ],
    );
  }
}
