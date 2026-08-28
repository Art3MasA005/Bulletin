/// One message in the thread. DESIGN §6.3.
///
/// The three assistant states look different on purpose:
///
///   answered   paper surface, Markdown body, Source Cards beneath
///   notFound   bordered paper, NO fill, ink-muted — must not resemble an
///              answer, because it is the honest admission that the corpus
///              had nothing (DESIGN §6.3, §8)
///   failed     danger border and a retry affordance
///
/// `RepaintBoundary` wraps the streaming message: without it, every token
/// repaints the whole list on a mid-range device.
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/theme/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/citation.dart';
import '../domain/message.dart';
import 'not_found_card.dart';
import 'source_card.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.role,
    this.onOpenSource,
    this.onRetry,
    this.onRephrase,
    super.key,
  });

  final ChatMessage message;

  /// The caller's role, so a refusal can name the scope it searched.
  final String role;

  final void Function(Citation citation)? onOpenSource;
  final VoidCallback? onRetry;
  final VoidCallback? onRephrase;

  @override
  Widget build(BuildContext context) {
    final body = message.isUser
        ? _UserBubble(message: message)
        : _AssistantBubble(
            message: message,
            role: role,
            onOpenSource: onOpenSource,
            onRetry: onRetry,
            onRephrase: onRephrase,
          );

    // Only the message being written needs its own layer; a boundary around
    // every settled message would cost memory for no benefit.
    return message.isStreaming ? RepaintBoundary(child: body) : body;
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: Space.xxxl, bottom: Space.md),
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
        decoration: const BoxDecoration(
          color: BulletinColors.accentSoft,
          borderRadius: Radii.cardAll,
        ),
        child: Text(
          message.text,
          style: BulletinText.resolve(BulletinText.messageBody, message.text),
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.message,
    required this.role,
    this.onOpenSource,
    this.onRetry,
    this.onRephrase,
  });

  final ChatMessage message;
  final String role;
  final void Function(Citation citation)? onOpenSource;
  final VoidCallback? onRetry;
  final VoidCallback? onRephrase;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    if (message.isNotFound) {
      return NotFoundCard(
        text: message.text.isEmpty ? l.notFoundBody : message.text,
        role: role,
        onRephrase: onRephrase,
      );
    }
    if (message.hasFailed) {
      return _Failed(detail: message.errorDetail ?? l.errorGeneric, onRetry: onRetry);
    }

    return Container(
      margin: const EdgeInsets.only(right: Sizes.assistantRightInset, bottom: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
            decoration: const BoxDecoration(
              color: BulletinColors.paper,
              borderRadius: Radii.cardAll,
            ),
            child: message.text.isEmpty
                ? const _Writing()
                : MarkdownBody(
                    data: message.text,
                    styleSheet: _markdownStyle(message.text),
                    selectable: true,
                  ),
          ),
          if (message.citations.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            SourceList(citations: message.citations, onOpen: onOpenSource),
          ],
        ],
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(String text) {
    final base = BulletinText.resolve(BulletinText.messageBody, text);
    return MarkdownStyleSheet(
      p: base,
      strong: base.copyWith(
        fontWeight: FontWeight.w600,
        fontVariations: Weights.semiBold,
      ),
      listBullet: base,
      // Course codes and dates inside an answer are data.
      code: BulletinText.courseCode,
      codeblockDecoration: const BoxDecoration(
        color: BulletinColors.accentSoft,
        borderRadius: Radii.chipAll,
      ),
      blockquoteDecoration: const BoxDecoration(
        color: BulletinColors.accentSoft,
        borderRadius: Radii.chipAll,
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.detail, this.onRetry});

  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(right: Sizes.assistantRightInset, bottom: Space.md),
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
      decoration: BoxDecoration(
        borderRadius: Radii.cardAll,
        border: Border.all(color: BulletinColors.danger.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detail,
            style: BulletinText.resolve(
              BulletinText.messageBody,
              detail,
            ).copyWith(color: BulletinColors.danger),
          ),
          if (onRetry != null) TextButton(onPressed: onRetry, child: Text(l.retryLabel)),
        ],
      ),
    );
  }
}

/// Three dots while the first token is still on its way.
class _Writing extends StatefulWidget {
  const _Writing();

  @override
  State<_Writing> createState() => _WritingState();
}

class _WritingState extends State<_Writing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(right: Space.xs),
                  child: Opacity(opacity: _opacityFor(i), child: const _Dot()),
                ),
            ],
          );
        },
      ),
    );
  }

  double _opacityFor(int index) {
    final phase = (_controller.value * 3 - index) % 3;
    return phase < 1 ? 0.35 + phase * 0.65 : 0.35;
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: BulletinColors.inkFaint,
        shape: BoxShape.circle,
      ),
    );
  }
}
