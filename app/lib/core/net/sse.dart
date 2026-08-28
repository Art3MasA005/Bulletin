/// A Server-Sent Events decoder. PRD §7.2 step 9.
///
/// Written by hand rather than pulled from a package for one reason: the
/// answer arrives here token by token, and the decoder has to hand each
/// `delta` to the UI the moment its blank line lands. A decoder that buffers
/// until the response completes turns a streaming answer into a spinner
/// followed by a paragraph, which is a different product.
///
/// The wire format the backend sends (app/api/chat.py):
///
///     event: meta
///     data: {"conversation_id": "...", "query_lang": "en"}
///
///     event: citations
///     data: {"citations": [...]}
///
///     event: delta
///     data: {"text": "The Final "}
///
///     event: done
///     data: {"status": "answered"}
///
/// Chunk boundaries fall anywhere, including mid-line and mid-UTF-8-sequence,
/// so bytes go through a streaming decoder and lines are held in a buffer
/// until a real newline arrives.
library;

import 'dart:convert';

/// One decoded SSE event.
class SseEvent {
  const SseEvent(this.event, this.data);

  /// The `event:` field, or "message" when the server omitted it.
  final String event;

  /// The `data:` payload, already JSON-decoded. Empty when it was not JSON.
  final Map<String, dynamic> data;

  @override
  String toString() => 'SseEvent($event, $data)';
}

/// Carriage return, named so the literal never has to appear inline.
const _cr = '\r';

/// Turns a byte stream into [SseEvent]s as they arrive.
Stream<SseEvent> decodeSse(Stream<List<int>> bytes) async* {
  // `utf8.decoder.bind` is the streaming form: it carries a partial multi-byte
  // character across chunk boundaries. `Utf8Decoder.convert` on each chunk does
  // NOT -- it decodes each chunk independently and emits U+FFFD for the half it
  // received, corrupting every Bangla word that straddles a boundary. Pinned by
  // the split-codepoint case in test/core/sse_test.dart.
  final text = utf8.decoder.bind(bytes);

  var buffer = '';
  String? eventName;
  final dataLines = <String>[];

  SseEvent? flush() {
    if (dataLines.isEmpty) {
      eventName = null;
      return null;
    }
    final payload = dataLines.join('\n');
    dataLines.clear();
    final name = eventName ?? 'message';
    eventName = null;

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(payload);
      data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      // A non-JSON payload is not fatal: the event still happened, and the
      // caller can decide what an unparseable body means.
      data = <String, dynamic>{};
    }
    return SseEvent(name, data);
  }

  void consumeLine(String rawLine) {
    var line = rawLine;
    if (line.endsWith(_cr)) {
      line = line.substring(0, line.length - 1);
    }
    if (line.startsWith(':')) return; // comment / keep-alive

    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'event':
        eventName = value;
      case 'data':
        dataLines.add(value);
      default:
        break; // id / retry are unused here
    }
  }

  await for (final chunk in text) {
    buffer += chunk;

    while (true) {
      final newline = buffer.indexOf('\n');
      if (newline < 0) break;

      final line = buffer.substring(0, newline);
      buffer = buffer.substring(newline + 1);

      if (line.isEmpty || line == _cr) {
        final event = flush();
        if (event != null) yield event;
        continue;
      }
      consumeLine(line);
    }
  }

  // A stream that ends without a trailing blank line still delivered its last
  // event -- dropping it would lose the final token of an answer -- and that
  // last line may still be sitting in the buffer unterminated.
  if (buffer.isNotEmpty) consumeLine(buffer);
  final last = flush();
  if (last != null) yield last;
}
