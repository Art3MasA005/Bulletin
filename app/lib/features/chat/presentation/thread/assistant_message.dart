/// One answer from Bulletin (CHANGES.md, "Chat with answers"): a 28 px orange
/// panda and "Bulletin" above, then whichever of the four things the message
/// is right now:
///
///   working   the steps card, until the first word arrives
///   answer    the text with a blinking caret while it streams; when it is
///             done, the collapsed sources
///   notFound  the "found nothing" card
///   failed    the error and a Retry
///
/// The answer has no bubble. A message that is still arriving is wrapped in
/// a `RepaintBoundary` by the caller, so each token repaints one message and
/// not the whole thread.
library;

import 'package:flutter/material.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/bulletin_logo.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/citation.dart';
import '../../domain/message.dart';
import 'answer_text.dart';
import 'not_found_card.dart';
import 'source_list.dart';
import 'working_steps.dart';

class AssistantMessage extends StatelessWidget {
  const AssistantMessage({
    required this.message,
    required this.role,
    this.onOpenSource,
    this.onRetry,
    super.key,
  });

  final ChatMessage message;

  /// The caller's role, so a refusal can name the scope it searched.
  final String role;

  final void Function(Citation citation)? onOpenSource;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    final Widget body;
    if (message.isWorking) {
      body = WorkingSteps(readCourses: message.readCourses);
    } else if (message.isNotFound) {
      body = NotFoundCard(
        text: message.text.isEmpty ? l.notFoundBody : message.text,
        role: role,
      );
    } else if (message.hasFailed) {
      body = _Failed(detail: message.errorDetail ?? l.errorGeneric, onRetry: onRetry);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: AnswerText(text: message.text, streaming: message.isStreaming),
          ),
          // The sources appear once the answer is complete, so the evidence
          // never sits under half a sentence.
          if (!message.isStreaming && message.citations.isNotEmpty)
            SourceList(citations: message.citations, onOpen: onOpenSource),
        ],
      );
    }

    return FadeUp(
      duration: MotionDurations.stepIn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [const _Header(), body],
      ),
    );
  }
}

/// A 28 px brand circle holding the panda, and the name beside it.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final name = L.of(context).appTitle;
    return Semantics(
      header: true,
      child: Row(
        spacing: Space.sm,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: BulletinColors.brand,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const BulletinMark(size: 24),
          ),
          Text(name, style: BulletinText.resolve(BulletinText.assistantName, name)),
        ],
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        color: BulletinColors.errorSurface,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(color: BulletinColors.dangerTint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: LineIcon(
                  LineIcons.alert,
                  color: BulletinColors.error,
                  size: 18,
                  strokeWidth: 2,
                ),
              ),
              Expanded(
                child: Text(
                  detail,
                  style: BulletinText.resolve(
                    BulletinText.stepLabel,
                    detail,
                  ).copyWith(color: BulletinColors.error),
                ),
              ),
            ],
          ),
          if (onRetry != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  minimumSize: const Size(Sizes.minTouchTarget, Sizes.minTouchTarget),
                  foregroundColor: BulletinColors.brandStrong,
                ),
                child: Text(
                  l.retryLabel,
                  style: BulletinText.resolve(
                    BulletinText.pillAction,
                    l.retryLabel,
                  ).copyWith(color: BulletinColors.brandStrong),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
