/// The thread: a reverse list, so a new message appears at the bottom without
/// a scroll animation to fight, and the list holds its place when the
/// keyboard opens. `addAutomaticKeepAlives: false`, because a long thread of
/// settled messages does not need to stay alive off-screen.
///
/// The top fades out under the floating bar (the prototype's mask: clear
/// until 16 px above the first row, solid 4 px below it), so a message slides
/// under the chrome instead of being cut by it. That is a gradient mask, not
/// a blur: the screen's two `BackdropFilter`s stay the top bar's and the
/// composer's (CLAUDE.md #11).
library;

import 'package:flutter/material.dart';

import '../../domain/citation.dart';
import '../../domain/message.dart';
import 'message_bubble.dart';

class ChatThread extends StatelessWidget {
  const ChatThread({
    required this.messages,
    required this.role,
    required this.controller,
    required this.topInset,
    required this.bottomInset,
    this.onOpenSource,
    this.onRetry,
    super.key,
  });

  /// Oldest first, as the controller keeps them.
  final List<ChatMessage> messages;
  final String role;
  final ScrollController controller;

  /// Where the first row may start, and the room the composer needs.
  final double topInset;
  final double bottomInset;

  final void Function(Citation citation)? onOpenSource;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final reversed = messages.reversed.toList(growable: false);

    return LayoutBuilder(
      builder: (context, box) {
        final height = box.maxHeight;
        final clearUntil = ((topInset - 16) / height).clamp(0.0, 1.0);
        final solidFrom = ((topInset + 4) / height).clamp(0.0, 1.0);

        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Color(0x00000000), Color(0x00000000), Color(0xFF000000)],
            stops: [0, clearUntil, solidFrom],
          ).createShader(rect),
          child: ListView.separated(
            controller: controller,
            reverse: true,
            addAutomaticKeepAlives: false,
            padding: EdgeInsets.fromLTRB(20, topInset, 20, bottomInset),
            itemCount: reversed.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final message = reversed[index];
              return MessageBubble(
                key: ValueKey(message.id),
                message: message,
                role: role,
                onOpenSource: onOpenSource,
                onRetry: message.hasFailed || message.notSent ? onRetry : null,
              );
            },
          ),
        );
      },
    );
  }
}
