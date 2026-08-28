/// The chat screen. DESIGN §6.2, §6.3.
///
/// A reverse `ListView`: new messages appear at the bottom without a scroll
/// animation to fight, and the list holds its position when the keyboard
/// opens. `addAutomaticKeepAlives: false` because a long thread of settled
/// messages does not need to stay alive off-screen.
///
/// The composer below it is the one frosted surface here; the app bar stays a
/// plain translucent one. The blur budget (CLAUDE.md #11, DESIGN §7) is why the app bar here is a
/// plain translucent surface rather than a frosted one: the frosted bar is
/// spent on the home screen, and a `BackdropFilter` above a scrolling list
/// repaints every frame the list moves.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/net/result.dart';
import '../../../core/theme/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../attachments/data/attachment_controller.dart';
import '../../attachments/presentation/confirm_sheet.dart';
import '../data/chat_controller.dart';
import '../domain/citation.dart';
import 'composer.dart';
import 'message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({this.conversationId, this.openingQuestion, super.key});

  final String? conversationId;

  /// A suggested question tapped on the home screen, sent on first frame.
  final String? openingQuestion;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    final opening = widget.openingQuestion;
    if (opening != null && opening.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_send(opening)));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Send, with the confirmation gate in front of it.
  ///
  /// CLAUDE.md #3: a question carrying an attachment cannot reach the backend
  /// until the user has confirmed the extracted course codes. The gate lives
  /// here rather than in the controller because confirming is a conversation
  /// with the user, and backing out of it must leave the typed question
  /// untouched in the field.
  Future<void> _send([String? text]) async {
    final question = text ?? _input.text;
    if (question.trim().isEmpty) return;

    final attachments = ref.read(attachmentControllerProvider.notifier);
    var attachment = ref.read(attachmentControllerProvider);

    if (attachment.staged != null) {
      // Still uploading: the server has not read the file, so there is nothing
      // to confirm yet. The send button is disabled in this state; this is the
      // keyboard-submit path.
      if (!attachment.staged!.isReady) return;

      final extraction = attachment.extraction;
      if (extraction != null && !extraction.confirmed) {
        final codes = await showConfirmExtractionSheet(context, extraction);
        if (codes == null) return; // dismissed — nothing confirmed, nothing sent
        final result = await attachments.confirm(codes);
        if (!mounted) return;
        if (result case Failure(:final message)) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message ?? L.of(context).errorGeneric)));
          return;
        }
        attachment = ref.read(attachmentControllerProvider);
      }
    }

    _input.clear();
    unawaited(
      ref
          .read(chatControllerProvider(widget.conversationId).notifier)
          .send(question, attachmentId: attachment.staged?.attachmentId),
    );
    // The attachment belongs to the question that carried it; the next one
    // starts from an empty composer.
    attachments.clear();

    // The list is reversed, so "scroll to newest" is offset zero.
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: Motion.sheet, curve: Curves.easeOut);
    }
  }

  void _openSource(Citation citation) {
    // The source viewer is a route of its own (DESIGN §6.5); until it exists,
    // say so rather than silently doing nothing on a tap the card advertises.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(L.of(context).openPage(citation.pageNo))));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final state = ref.watch(chatControllerProvider(widget.conversationId));
    final messages = state.messages.reversed.toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(l.appTitle)),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? _EmptyState(onPick: (q) => unawaited(_send(q)))
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    addAutomaticKeepAlives: false,
                    padding: const EdgeInsets.fromLTRB(
                      Space.lg,
                      Space.lg,
                      Space.lg,
                      Space.sm,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return MessageBubble(
                        key: ValueKey(message.id),
                        message: message,
                        role: 'student',
                        onOpenSource: _openSource,
                        onRetry: message.hasFailed
                            ? () => ref
                                  .read(
                                    chatControllerProvider(
                                      widget.conversationId,
                                    ).notifier,
                                  )
                                  .retryLast()
                            : null,
                      );
                    },
                  ),
          ),
          Composer(
            controller: _input,
            focusNode: _focus,
            sending: state.sending,
            hint: state.messages.isEmpty ? l.askHome : l.askFollowUp,
            onSend: () => unawaited(_send()),
          ),
        ],
      ),
    );
  }
}

/// The home empty state: a greeting and three suggested questions (DESIGN §6.1).
///
/// The suggestions are not filler. A student who has never used the app does
/// not know what it can answer, and three concrete questions teach that faster
/// than any onboarding copy.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick});

  final void Function(String question) onPick;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final suggestions = [l.suggestExamStart, l.suggestMakeupFee, l.suggestHoliday];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.greetingPlain, style: BulletinText.screenTitle),
            const SizedBox(height: Space.xl),
            Text(l.tryAsking, style: BulletinText.sectionLabel),
            const SizedBox(height: Space.md),
            for (final suggestion in suggestions) ...[
              _SuggestionChip(text: suggestion, onTap: () => onPick(suggestion)),
              const SizedBox(height: Space.sm),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BulletinColors.paper,
      borderRadius: Radii.chipAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.chipAll,
        child: Container(
          constraints: const BoxConstraints(minHeight: Sizes.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
          alignment: Alignment.centerLeft,
          child: Text(text, style: BulletinText.resolve(BulletinText.messageBody, text)),
        ),
      ),
    );
  }
}
