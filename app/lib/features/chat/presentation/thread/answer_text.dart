/// An answer's text: Markdown, 16 / 1.65, no bubble (CHANGES.md).
///
/// While the answer is still being written a 2 x 1.1 em orange caret blinks
/// at the end of the text. It is a custom inline Markdown element rather than
/// a widget under the paragraph, so it follows the last word onto a new line
/// the way the prototype's does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../../core/motion/motion.dart';
import '../../../../core/theme/theme.dart';

class AnswerText extends StatelessWidget {
  const AnswerText({required this.text, this.streaming = false, super.key});

  final String text;
  final bool streaming;

  /// Private-use code point: never in real text, so it can mark where the
  /// caret goes without colliding with anything the model writes.
  static const _marker = '';

  @override
  Widget build(BuildContext context) {
    final base = BulletinText.resolve(BulletinText.answerBody, text);
    return MarkdownBody(
      data: streaming ? '$text$_marker' : text,
      styleSheet: _styleSheet(base),
      inlineSyntaxes: [_CaretSyntax(_marker)],
      builders: {'caret': _CaretBuilder(base.fontSize ?? 16)},
      // A text selection cannot hold the caret widget, and an answer that is
      // still arriving has nothing worth copying yet.
      selectable: !streaming,
    );
  }

  MarkdownStyleSheet _styleSheet(TextStyle base) {
    return MarkdownStyleSheet(
      p: base,
      pPadding: EdgeInsets.zero,
      strong: base.copyWith(fontWeight: FontWeight.w600, fontVariations: Weights.semiBold),
      listBullet: base,
      listIndent: 20,
      blockSpacing: 12,
      // Course codes and dates inside an answer are data: mono, on a peach tile.
      code: BulletinText.courseCode.copyWith(
        fontSize: 13,
        color: BulletinColors.brandText,
        backgroundColor: BulletinColors.peach,
      ),
      codeblockDecoration: const BoxDecoration(
        color: BulletinColors.peach,
        borderRadius: BrandRadii.square,
      ),
      blockquoteDecoration: const BoxDecoration(
        color: BulletinColors.peach,
        borderRadius: BrandRadii.square,
      ),
    );
  }
}

class _CaretSyntax extends md.InlineSyntax {
  _CaretSyntax(String marker) : super(RegExp.escape(marker));

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('caret'));
    return true;
  }
}

class _CaretBuilder extends MarkdownElementBuilder {
  _CaretBuilder(this.fontSize);

  final double fontSize;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => _Caret(height: fontSize * 1.1);
}

/// 2 px wide, 1.1 em tall, `blCaret 1.3s`: opacity 1 → .15 → 1. Still under
/// reduced motion.
class _Caret extends StatefulWidget {
  const _Caret({required this.height});

  final double height;

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionDurations.caretPulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // 1 -> .15 -> 1, eased like `ease-in-out`.
          final t = Curves.easeInOut.transform(
            _controller.value < .5 ? _controller.value * 2 : (1 - _controller.value) * 2,
          );
          return Opacity(opacity: 1 - 0.85 * t, child: child);
        },
        child: Container(
          width: 2,
          height: widget.height,
          decoration: const BoxDecoration(
            color: BulletinColors.brandStrong,
            borderRadius: BorderRadius.all(Radius.circular(1)),
          ),
        ),
      ),
    );
  }
}
