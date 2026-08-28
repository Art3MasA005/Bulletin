import 'dart:async';

import 'package:bulletin/core/net/api_client.dart';
import 'package:bulletin/core/net/sse.dart';
import 'package:bulletin/features/chat/data/chat_controller.dart';
import 'package:bulletin/features/chat/domain/message.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// An ApiClient whose chat() replays a scripted event stream.
class ScriptedApi extends ApiClient {
  ScriptedApi(this.events, {this.onCall}) : super(token: () => 'token', dio: Dio());

  final List<SseEvent> events;
  final void Function(Map<String, dynamic> request)? onCall;
  final controller = StreamController<SseEvent>();

  @override
  Stream<SseEvent> chat({
    required String question,
    String? conversationId,
    String? attachmentId,
    List<Map<String, String>> history = const [],
  }) async* {
    onCall?.call({
      'question': question,
      'conversation_id': conversationId,
      'attachment_id': attachmentId,
      'history': history,
    });
    for (final event in events) {
      yield event;
    }
  }
}

SseEvent meta([String id = 'conv-1']) => SseEvent('meta', {'conversation_id': id});
SseEvent citations(List<Map<String, dynamic>> list) =>
    SseEvent('citations', {'citations': list});
SseEvent delta(String text) => SseEvent('delta', {'text': text});
SseEvent done([String status = 'answered']) => SseEvent('done', {'status': status});

void main() {
  test('tokens append to the answer as they arrive', () async {
    final api = ScriptedApi([
      meta(),
      citations([
        {
          'n': 1,
          'chunk_id': 1,
          'doc_id': 'doc-1',
          'page_no': 3,
          'lang': 'en',
          'snippet': 's',
        },
      ]),
      delta('The Final '),
      delta('Examinations '),
      delta('start on 05 September 2026 [1].'),
      done(),
    ]);
    final controller = ChatController(api);

    await controller.send('when do finals start');

    final messages = controller.state.messages;
    expect(messages.map((m) => m.role), [MessageRole.user, MessageRole.assistant]);
    expect(messages.last.text, 'The Final Examinations start on 05 September 2026 [1].');
    expect(messages.last.status, AnswerStatus.answered);
    expect(messages.last.citations.single.pageNo, 3);
    expect(controller.state.conversationId, 'conv-1');
    expect(controller.state.sending, isFalse);
  });

  test('citations arrive before the first token so cards can render early', () async {
    final api = ScriptedApi([
      citations([
        {
          'n': 1,
          'chunk_id': 1,
          'doc_id': 'd',
          'page_no': 1,
          'lang': 'bn',
          'snippet': 'পরীক্ষা',
        },
      ]),
      delta('x'),
      done(),
    ]);
    final controller = ChatController(api);
    final seen = <int>[];
    controller.addListener((state) {
      final last = state.messages.isEmpty ? null : state.messages.last;
      if (last != null && !last.isUser) seen.add(last.citations.length);
    });

    await controller.send('q');
    // The first assistant state carrying citations came before the text did.
    expect(seen.first, 0); // pending, empty
    expect(seen.contains(1), isTrue);
    expect(controller.state.messages.last.citations.single.isBangla, isTrue);
  });

  test('a not-found answer is its own status and cites nothing', () async {
    final api = ScriptedApi([
      citations([
        {
          'n': 1,
          'chunk_id': 1,
          'doc_id': 'd',
          'page_no': 1,
          'lang': 'en',
          'snippet': 's',
        },
      ]),
      delta('Nothing in the published documents covers this.'),
      done('not_found'),
    ]);
    final controller = ChatController(api);

    await controller.send('how much is the hostel fee');

    final answer = controller.state.messages.last;
    expect(answer.status, AnswerStatus.notFound);
    // Stale cards under a refusal would suggest the sources supported it.
    expect(answer.citations, isEmpty);
  });

  test('an error event marks the message failed and keeps the detail', () async {
    final api = ScriptedApi([
      delta('half an ans'),
      const SseEvent('error', {'detail': 'the answer could not be completed'}),
    ]);
    final controller = ChatController(api);

    await controller.send('q');

    final answer = controller.state.messages.last;
    expect(answer.status, AnswerStatus.failed);
    expect(answer.errorDetail, 'the answer could not be completed');
    expect(answer.text, 'half an ans');
  });

  test('a stream that ends without done does not leave a spinner', () async {
    final api = ScriptedApi([delta('cut off')]);
    final controller = ChatController(api);

    await controller.send('q');

    expect(controller.state.messages.last.status, AnswerStatus.failed);
    expect(controller.state.sending, isFalse);
  });

  test('the conversation id is sent on the next question', () async {
    final requests = <Map<String, dynamic>>[];
    final api = ScriptedApi([meta('conv-9'), delta('a'), done()], onCall: requests.add);
    final controller = ChatController(api);

    await controller.send('first');
    await controller.send('second');

    expect(requests.first['conversation_id'], isNull);
    expect(requests.last['conversation_id'], 'conv-9');
  });

  test('history is capped at three turns', () async {
    final requests = <Map<String, dynamic>>[];
    final api = ScriptedApi([delta('a'), done()], onCall: requests.add);
    final controller = ChatController(api);

    for (var i = 0; i < 5; i++) {
      await controller.send('question $i');
    }

    final history = requests.last['history'] as List;
    expect(history.length, lessThanOrEqualTo(6));
  });

  test('an empty question sends nothing', () async {
    final requests = <Map<String, dynamic>>[];
    final api = ScriptedApi([done()], onCall: requests.add);
    final controller = ChatController(api);

    await controller.send('   ');

    expect(requests, isEmpty);
    expect(controller.state.messages, isEmpty);
  });

  test('an attachment id rides along with the question', () async {
    final requests = <Map<String, dynamic>>[];
    final api = ScriptedApi([delta('a'), done()], onCall: requests.add);
    final controller = ChatController(api);

    await controller.send('when are my exams', attachmentId: 'att-1');

    expect(requests.single['attachment_id'], 'att-1');
    expect(controller.state.messages.first.attachmentId, 'att-1');
  });
}
