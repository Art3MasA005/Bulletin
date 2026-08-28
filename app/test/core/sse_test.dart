import 'dart:convert';

import 'package:bulletin/core/net/sse.dart';
import 'package:flutter_test/flutter_test.dart';

Stream<List<int>> chunks(List<String> parts) =>
    Stream.fromIterable(parts.map(utf8.encode));

void main() {
  test('decodes events in order as they arrive', () async {
    final events = await decodeSse(
      chunks([
        'event: meta\ndata: {"conversation_id": "c1"}\n\n',
        'event: delta\ndata: {"text": "Hello "}\n\n',
        'event: delta\ndata: {"text": "world"}\n\n',
        'event: done\ndata: {"status": "answered"}\n\n',
      ]),
    ).toList();

    expect(events.map((e) => e.event), ['meta', 'delta', 'delta', 'done']);
    expect(events[1].data['text'], 'Hello ');
    expect(events.last.data['status'], 'answered');
  });

  test('an event split across chunks still arrives whole', () async {
    final events = await decodeSse(
      chunks(['event: del', 'ta\ndata: {"text": "spl', 'it"}\n', '\n']),
    ).toList();

    expect(events.single.event, 'delta');
    expect(events.single.data['text'], 'split');
  });

  test('a Bangla codepoint split across chunks is not corrupted', () async {
    // The reason this decoder is hand-written: 'পরীক্ষা' is multi-byte, and a
    // chunk boundary lands mid-character often enough to matter.
    final payload = utf8.encode('event: delta\ndata: {"text": "পরীক্ষা কবে"}\n\n');
    final events = await decodeSse(
      Stream.fromIterable([
        payload.sublist(0, 30),
        payload.sublist(30, 45),
        payload.sublist(45),
      ]),
    ).toList();

    expect(events.single.data['text'], 'পরীক্ষা কবে');
    expect(events.single.data['text'].toString().contains('�'), isFalse);
  });

  test('the final event survives a stream that ends without a blank line', () async {
    final events = await decodeSse(
      chunks(['event: done\ndata: {"status": "answered"}']),
    ).toList();

    expect(events.single.event, 'done');
  });

  test('comments and unknown fields are ignored', () async {
    final events = await decodeSse(
      chunks([': keep-alive\n', 'id: 7\n', 'event: delta\ndata: {"text": "x"}\n\n']),
    ).toList();

    expect(events.single.data['text'], 'x');
  });

  test('a data payload that is not JSON yields an empty map, not a crash', () async {
    final events = await decodeSse(chunks(['event: delta\ndata: not json\n\n'])).toList();
    expect(events.single.event, 'delta');
    expect(events.single.data, isEmpty);
  });

  test('multi-line data is joined with newlines', () async {
    final events = await decodeSse(
      chunks(['data: {"text":\ndata: "two lines"}\n\n']),
    ).toList();
    expect(events.single.data['text'], 'two lines');
  });

  test('an event with no name defaults to message', () async {
    final events = await decodeSse(chunks(['data: {"a": 1}\n\n'])).toList();
    expect(events.single.event, 'message');
  });
}
