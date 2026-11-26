/// One message in the thread: the user's bubble, or Bulletin's answer.
///
/// `RepaintBoundary` wraps the message being written: without it, every token
/// repaints the whole list on a mid-range device.
library;

import 'package:flutter/material.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../domain/citation.dart';
import '../../domain/message.dart';
import 'assistant_message.dart';
import 'user_bubble.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.role,
    this.onOpenSource,
    this.onRetry,
    super.key,
  });

  final ChatMessage message;
  final String role;
  final void Function(Citation citation)? onOpenSource;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final body = message.isUser
        ? FadeUp(
            duration: MotionDurations.stepIn,
            child: UserBubble(message: message, onRetry: onRetry),
          )
        : AssistantMessage(
            message: message,
            role: role,
            onOpenSource: onOpenSource,
            onRetry: onRetry,
          );

    // Only the message being written needs its own layer; a boundary around
    // every settled message would cost memory for no benefit.
    return message.isStreaming ? RepaintBoundary(child: body) : body;
  }
}
