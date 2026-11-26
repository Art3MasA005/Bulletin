// The chat thread (CHANGES.md, "Chat with answers"): the user's bubble and its
// "Not sent" state, the working steps, the streaming caret, the sources that
// collapse and open in place, the not-found card, the offline banner, and
// Bangla at 200% text scale without an overflow.
import 'package:bulletin/core/net/sse.dart';
import 'package:bulletin/core/theme/theme.dart';
import 'package:bulletin/features/chat/data/chat_controller.dart';
import 'package:bulletin/features/chat/domain/citation.dart';
import 'package:bulletin/features/chat/domain/message.dart';
import 'package:bulletin/features/chat/presentation/thread/chat_thread.dart';
import 'package:bulletin/features/chat/presentation/thread/message_bubble.dart';
import 'package:bulletin/features/chat/presentation/thread/not_found_card.dart';
import 'package:bulletin/features/chat/presentation/thread/offline_banner.dart';
import 'package:bulletin/features/chat/presentation/thread/source_list.dart';
import 'package:bulletin/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_controller_test.dart' show ScriptedApi, delta, done, meta;

Citation citation({
  int n = 1,
  String lang = 'en',
  String title = 'Exam Routine, Summer 2026',
  String snippet = 'Final examinations commence on 05 September 2026.',
  int page = 3,
}) => Citation(
  n: n,
  chunkId: n,
  documentId: 'doc-$n',
  pageNo: page,
  lang: lang,
  snippet: snippet,
  title: title,
);

Widget host(
  Widget child, {
  Locale locale = const Locale('en'),
  double textScale = 1,
  bool scroll = true,
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: L.localizationsDelegates,
    supportedLocales: L.supportedLocales,
    theme: buildBulletinTheme(),
    home: MediaQuery(
      data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: scroll
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: child,
              )
            : child,
      ),
    ),
  );
}

ChatMessage assistant({
  String text = '',
  AnswerStatus status = AnswerStatus.answered,
  List<Citation> citations = const [],
  int? readCourses,
}) => ChatMessage(
  id: 'a-${text.hashCode}-${status.name}',
  role: MessageRole.assistant,
  text: text,
  status: status,
  citations: citations,
  readCourses: readCourses,
);

Finder caret() => find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Caret');

void main() {
  group('the user bubble', () {
    testWidgets('is peach, with the question in it', (tester) async {
      await tester.pumpWidget(
        host(MessageBubble(message: ChatMessage.user('When do the finals start?'), role: 'student')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('When do the finals start?'), findsOneWidget);
      final box = tester.widget<Container>(
        find.ancestor(
          of: find.text('When do the finals start?'),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, BulletinColors.userBubble);
    });

    testWidgets('a question that never left says so, and Retry asks again', (tester) async {
      var retried = 0;
      final message = ChatMessage.user('When do the finals start?').copyWith(notSent: true);
      await tester.pumpWidget(
        host(MessageBubble(message: message, role: 'student', onRetry: () => retried++)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text("Not sent. You're offline."), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retried, 1);
      final retry = tester.getSize(find.ancestor(of: find.text('Retry'), matching: find.byType(InkWell)).first);
      expect(retry.height, greaterThanOrEqualTo(Sizes.minTouchTarget));
    });
  });

  group('the assistant', () {
    testWidgets('while it works: the steps card, and no text yet', (tester) async {
      await tester.pumpWidget(
        host(MessageBubble(message: ChatMessage.pending(), role: 'student')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Bulletin'), findsOneWidget, reason: 'the name over every answer');
      expect(find.text('Searching documents…'), findsOneWidget);
      expect(caret(), findsNothing);
    });

    testWidgets('a routine read first shows as a finished step', (tester) async {
      await tester.pumpWidget(
        host(MessageBubble(message: ChatMessage.pending(readCourses: 4), role: 'student')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Read 4 courses from your routine'), findsOneWidget);
      expect(find.text('Searching documents…'), findsOneWidget);
    });

    testWidgets('streaming: the text, a caret, and no sources yet', (tester) async {
      await tester.pumpWidget(
        host(
          MessageBubble(
            message: assistant(
              text: 'Finals start on **05 September**',
              status: AnswerStatus.streaming,
              citations: [citation()],
            ),
            role: 'student',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Finals start on', findRichText: true), findsOneWidget);
      expect(caret(), findsOneWidget);
      expect(find.text('SOURCES'), findsNothing, reason: 'the evidence waits for the end');
      expect(find.text('Searching documents…'), findsNothing);
    });

    testWidgets('done: no caret, and the sources appear collapsed', (tester) async {
      await tester.pumpWidget(
        host(
          MessageBubble(
            message: assistant(text: 'Finals start on 05 September.', citations: [citation()]),
            role: 'student',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(caret(), findsNothing);
      expect(find.text('SOURCES'), findsOneWidget);
      expect(find.text('Exam Routine, Summer 2026'), findsOneWidget);
      expect(find.text('Open page 3'), findsNothing, reason: 'collapsed by default');
    });

    testWidgets('not found: the card, the text and the scope line', (tester) async {
      await tester.pumpWidget(
        host(
          MessageBubble(
            message: assistant(status: AnswerStatus.notFound),
            role: 'student',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(NotFoundCard), findsOneWidget);
      expect(
        find.text(
          'Nothing in the published documents covers this. Try rephrasing, or ask the office.',
        ),
        findsOneWidget,
      );
      expect(find.text('Answered from student-scoped documents only.'), findsOneWidget);
    });

    testWidgets('failed: the detail and a Retry', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        host(
          MessageBubble(
            message: assistant(status: AnswerStatus.failed).copyWith(errorDetail: 'The model is busy.'),
            role: 'student',
            onRetry: () => retried++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('The model is busy.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, 1);
    });
  });

  group('sources', () {
    final many = [
      citation(n: 1, title: 'Exam Routine, Summer 2026', page: 3),
      citation(n: 2, title: 'Notice: Fees', page: 1, snippet: 'Fees are due on the 10th.'),
      citation(n: 3, title: 'Holiday Notice', page: 2),
      citation(n: 4, title: 'Registration', page: 5),
    ];

    testWidgets('collapsed rows: number, one-line title and page; two of four', (tester) async {
      await tester.pumpWidget(host(SourceList(citations: many, onOpen: (_) {})));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('SOURCES'), findsOneWidget);
      expect(find.text('Exam Routine, Summer 2026'), findsOneWidget);
      expect(find.text('Page 3'), findsOneWidget);
      expect(find.text('Notice: Fees'), findsOneWidget);
      expect(find.text('Holiday Notice'), findsNothing);
      expect(find.text('2 more sources'), findsOneWidget);
      // No snippet until a row is opened.
      expect(find.textContaining('05 September'), findsNothing);
    });

    testWidgets('a tap opens a row in place; a tap on another closes the first', (tester) async {
      await tester.pumpWidget(host(SourceList(citations: many, onOpen: (_) {})));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('Exam Routine, Summer 2026'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('05 September 2026'), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);
      expect(find.text('Open page 3'), findsOneWidget);

      await tester.tap(find.text('Notice: Fees'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('05 September 2026'), findsNothing, reason: 'one open at a time');
      expect(find.textContaining('Fees are due'), findsOneWidget);

      await tester.tap(find.text('Notice: Fees'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Fees are due'), findsNothing, reason: 'a second tap collapses');
    });

    testWidgets('Open page hands the citation over', (tester) async {
      Citation? opened;
      await tester.pumpWidget(host(SourceList(citations: many, onOpen: (c) => opened = c)));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Exam Routine, Summer 2026'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Open page 3'));
      expect(opened?.pageNo, 3);
      expect(opened?.n, 1);
    });

    testWidgets('+ N more reveals the rest', (tester) async {
      await tester.pumpWidget(host(SourceList(citations: many, onOpen: (_) {})));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('2 more sources'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Holiday Notice'), findsOneWidget);
      expect(find.text('Registration'), findsOneWidget);
      expect(find.textContaining('more source'), findsNothing);
    });

    testWidgets('a Bangla source: the BN tag and the snippet untranslated', (tester) async {
      const bangla = 'চূড়ান্ত পরীক্ষা ০৫ সেপ্টেম্বর ২০২৬ তারিখে শুরু হবে।';
      await tester.pumpWidget(
        host(
          SourceList(
            citations: [citation(lang: 'bn', snippet: bangla, title: 'পরীক্ষার রুটিন')],
            onOpen: (_) {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('পরীক্ষার রুটিন'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('BN'), findsOneWidget);
      final text = tester.widget<Text>(find.text(bangla));
      expect(text.style?.fontFamily, Fonts.bangla, reason: 'or the conjuncts render as boxes');
    });

    testWidgets('rows are never frosted (CLAUDE.md #11)', (tester) async {
      await tester.pumpWidget(host(SourceList(citations: many, onOpen: (_) {})));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('a row is a 48 px target and says whether it is open', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(SourceList(citations: many, onOpen: (_) {})));
      await tester.pump(const Duration(milliseconds: 600));
      final row = find.ancestor(
        of: find.text('Exam Routine, Summer 2026'),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(row.first).height, greaterThanOrEqualTo(Sizes.minTouchTarget));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Exam Routine, Summer 2026, Page 3')),
        isNotNull,
      );
      handle.dispose();
    });
  });

  testWidgets('the offline banner says so', (tester) async {
    await tester.pumpWidget(host(const OfflineBanner()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("You're offline. Answers need a connection."), findsOneWidget);
  });

  group('the thread', () {
    final scripted = [
      ChatMessage.user('When do the finals start?'),
      assistant(
        text: 'Finals start on **05 September 2026** [1].',
        citations: [citation(), citation(n: 2, title: 'Notice: Fees', page: 1)],
      ),
      ChatMessage.user('And the makeup exams?'),
      assistant(status: AnswerStatus.notFound),
    ];

    testWidgets('lists the exchange, newest at the bottom', (tester) async {
      await tester.pumpWidget(
        host(
          ChatThread(
            messages: scripted,
            role: 'student',
            controller: ScrollController(),
            topInset: 124,
            bottomInset: 128,
          ),
          scroll: false,
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      final newest = tester.getTopLeft(find.text('And the makeup exams?')).dy;
      final oldest = tester.getTopLeft(find.text('When do the finals start?')).dy;
      expect(newest, greaterThan(oldest), reason: 'the latest question sits lower');
    });

    testWidgets('Bangla at 200% does not overflow', (tester) async {
      const q = 'চূড়ান্ত পরীক্ষা কবে শুরু হবে?';
      const a = 'চূড়ান্ত পরীক্ষা ০৫ সেপ্টেম্বর ২০২৬ তারিখে শুরু হবে — ক্ষ জ্ঞ ঞ্চ র্ধ্ব [১]।';
      await tester.pumpWidget(
        host(
          ChatThread(
            messages: [
              ChatMessage.user(q),
              assistant(
                text: a,
                citations: [
                  citation(lang: 'bn', title: 'পরীক্ষার রুটিন, সামার ২০২৬', snippet: a),
                ],
              ),
              ChatMessage.user('আরেকটি প্রশ্ন').copyWith(notSent: true),
            ],
            role: 'student',
            controller: ScrollController(),
            topInset: 124,
            bottomInset: 128,
          ),
          locale: const Locale('bn'),
          textScale: 2,
          scroll: false,
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.takeException(), isNull);
      // The newest message is the one in view at the bottom of the list.
      expect(find.text('আরেকটি প্রশ্ন'), findsOneWidget);
    });
  });

  group('the controller, offline', () {
    test('a question that cannot leave is kept, marked, and the empty answer dropped', () async {
      final api = ScriptedApi([
        const SseEvent('error', {'detail': 'offline', 'offline': true}),
      ]);
      final controller = ChatController(api);
      await controller.send('when do finals start');

      final messages = controller.state.messages;
      expect(messages, hasLength(1));
      expect(messages.single.isUser, isTrue);
      expect(messages.single.notSent, isTrue);
      expect(controller.state.offline, isTrue);
      expect(controller.state.sending, isFalse);
    });

    test('a server error is not offline: it stays an answer-shaped failure', () async {
      final api = ScriptedApi([const SseEvent('error', {'detail': 'The model is busy.'})]);
      final controller = ChatController(api);
      await controller.send('when do finals start');

      expect(controller.state.offline, isFalse);
      expect(controller.state.messages.last.hasFailed, isTrue);
      expect(controller.state.messages.first.notSent, isFalse);
    });

    test('retry asks again, and a reply clears the offline state', () async {
      final events = <SseEvent>[
        const SseEvent('error', {'detail': 'offline', 'offline': true}),
      ];
      final api = ScriptedApi(events);
      final controller = ChatController(api);
      await controller.send('when do finals start');
      expect(controller.state.offline, isTrue);

      events
        ..clear()
        ..addAll([meta(), delta('On 05 September.'), done()]);
      controller.retryLast();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.offline, isFalse);
      final messages = controller.state.messages;
      expect(messages.where((m) => m.isUser), hasLength(1), reason: 'not asked twice');
      expect(messages.first.notSent, isFalse);
      expect(messages.last.text, 'On 05 September.');
    });

    test('the courses read from a routine ride on the waiting answer', () async {
      final api = ScriptedApi([meta(), delta('x'), done()]);
      final controller = ChatController(api);
      final future = controller.send('my exams', readCourses: 4);
      expect(controller.state.messages.last.readCourses, 4);
      await future;
    });
  });
}
