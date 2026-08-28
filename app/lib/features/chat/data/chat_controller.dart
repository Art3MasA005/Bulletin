/// The chat state, driven by the SSE stream. PRD §7.2 step 9.
///
/// One rule shapes this file: **a token appears on screen the moment it
/// arrives**. The notifier appends each `delta` to the last message and emits
/// new state; it never accumulates the answer and publishes it at the end.
///
/// The event order the backend guarantees (app/api/chat.py):
///
///     meta -> citations -> delta* -> done | error
///
/// Citations arrive before the first token, so the Source Cards can render
/// while the answer is still being written.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/net/api_client.dart';
import '../../../core/net/sse.dart';
import '../../../core/providers.dart';
import '../domain/citation.dart';
import '../domain/message.dart';

class ChatState {
  const ChatState({this.messages = const [], this.conversationId, this.sending = false});

  /// Oldest first. The view reverses for display.
  final List<ChatMessage> messages;

  /// Assigned by the server on the first question; sent back on every
  /// following one so the thread continues.
  final String? conversationId;

  final bool sending;

  ChatState copyWith({
    List<ChatMessage>? messages,
    String? conversationId,
    bool? sending,
  }) => ChatState(
    messages: messages ?? this.messages,
    conversationId: conversationId ?? this.conversationId,
    sending: sending ?? this.sending,
  );
}

class ChatController extends StateNotifier<ChatState> {
  ChatController(this._api, {String? conversationId})
    : super(ChatState(conversationId: conversationId));

  final ApiClient _api;
  StreamSubscription<SseEvent>? _subscription;

  /// The last few turns, for the backend's condenser (PRD §7.2 step 1).
  ///
  /// Capped at three pairs: the condenser only resolves pronouns, and sending
  /// a whole conversation would spend tokens to no effect.
  List<Map<String, String>> _history() {
    final done = state.messages.where((m) => !m.isStreaming).toList();
    final recent = done.length <= 6 ? done : done.sublist(done.length - 6);
    return [
      for (final message in recent)
        {'role': message.isUser ? 'user' : 'assistant', 'content': message.text},
    ];
  }

  Future<void> send(String question, {String? attachmentId}) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || state.sending) return;

    final history = _history();
    final pending = ChatMessage.pending();
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage.user(trimmed, attachmentId: attachmentId),
        pending,
      ],
      sending: true,
    );

    final stream = _api.chat(
      question: trimmed,
      conversationId: state.conversationId,
      attachmentId: attachmentId,
      history: history,
    );

    final completer = Completer<void>();
    _subscription = stream.listen(
      (event) => _apply(event, pending.id),
      onError: (Object error) {
        _fail(pending.id, error.toString());
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        // A stream that ends without `done` (the process died, the socket
        // dropped) leaves the message mid-write. Mark it failed rather than
        // leaving a spinner that never resolves.
        final message = _find(pending.id);
        if (message != null && message.isStreaming) {
          _fail(pending.id, null);
        }
        state = state.copyWith(sending: false);
        if (!completer.isCompleted) completer.complete();
      },
    );
    return completer.future;
  }

  void _apply(SseEvent event, String messageId) {
    switch (event.event) {
      case 'meta':
        final id = event.data['conversation_id'] as String?;
        if (id != null) state = state.copyWith(conversationId: id);

      case 'citations':
        _update(
          messageId,
          (message) =>
              message.copyWith(citations: Citation.listFrom(event.data['citations'])),
        );

      case 'delta':
        final text = event.data['text'] as String? ?? '';
        if (text.isEmpty) return;
        _update(messageId, (message) => message.copyWith(text: message.text + text));

      case 'done':
        final status = event.data['status'] == 'not_found'
            ? AnswerStatus.notFound
            : AnswerStatus.answered;
        _update(
          messageId,
          (message) => message.copyWith(
            status: status,
            // A not-found answer cites nothing. Leaving stale cards under it
            // would suggest the sources supported the refusal.
            citations: status == AnswerStatus.notFound ? const [] : message.citations,
          ),
        );

      case 'error':
        _fail(messageId, event.data['detail'] as String?);
    }
  }

  ChatMessage? _find(String id) {
    for (final message in state.messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  void _update(String id, ChatMessage Function(ChatMessage) transform) {
    state = state.copyWith(
      messages: [
        for (final message in state.messages)
          if (message.id == id) transform(message) else message,
      ],
    );
  }

  void _fail(String id, String? detail) {
    _update(
      id,
      (message) => message.copyWith(status: AnswerStatus.failed, errorDetail: detail),
    );
  }

  /// Drop a failed exchange so the user can ask again cleanly.
  void retryLast() {
    final messages = [...state.messages];
    while (messages.isNotEmpty && !messages.last.isUser) {
      messages.removeLast();
    }
    final question = messages.isNotEmpty ? messages.removeLast().text : null;
    state = state.copyWith(messages: messages, sending: false);
    if (question != null) send(question);
  }

  void loadHistory(List<ChatMessage> messages, {String? conversationId}) {
    state = ChatState(messages: messages, conversationId: conversationId);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// One controller per conversation; `null` is the new, unsaved conversation.
final chatControllerProvider =
    StateNotifierProvider.family<ChatController, ChatState, String?>((
      ref,
      conversationId,
    ) {
      return ChatController(ref.watch(apiClientProvider), conversationId: conversationId);
    });
