// The model picker (handoff README, "Model picker"): the server's list, the
// pick reaching /chat as a key, the thread's pill and "New chat", no picker
// when nothing is offered, the blur budget with the menu open, and Bangla at
// 200%.
import 'package:bulletin/features/chat/domain/model_choice.dart';
import 'package:bulletin/features/chat/presentation/home/home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_test.dart' show askFirstSuggestion, blurs, pumpHome;

const _offered = <Map<String, dynamic>>[
  {'key': 'gemma', 'name': 'Gemma 4', 'maker': 'Google', 'cost': 'low', 'default': true},
  {
    'key': 'haiku',
    'name': 'Claude Haiku 5.5',
    'maker': 'Anthropic',
    'cost': 'low',
    'default': false,
  },
  {
    'key': 'terra',
    'name': 'GPT-6.1 Terra',
    'maker': 'OpenAI',
    'cost': 'high',
    'default': false,
  },
];

Future<void> openMenu(WidgetTester tester, String current) async {
  // "Model: …" or "মডেল: …".
  await tester.tap(find.bySemanticsLabel(RegExp(': ${RegExp.escape(current)}\$')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('currentModel', () {
    final offered = [for (final m in _offered) ModelChoice.fromJson(m)];
    test('the pick, while it is offered', () {
      expect(currentModel(offered, 'haiku')!.key, 'haiku');
    });
    test('else the server default', () {
      expect(currentModel(offered, null)!.key, 'gemma');
      expect(currentModel(offered, 'gone')!.key, 'gemma');
    });
    test('nothing offered, no model', () {
      expect(currentModel(const [], 'haiku'), isNull);
    });
  });

  testWidgets('Home shows the default; picking another sends its key', (tester) async {
    final (:models, asked: _, auth: _) = await pumpHome(tester, offered: _offered);
    expect(find.text('Gemma 4'), findsOneWidget);

    await openMenu(tester, 'Gemma 4');
    expect(find.text('AI MODEL'), findsOneWidget);
    expect(find.text('Google · Default'), findsOneWidget);
    expect(find.text('OpenAI · Stronger, costs more'), findsOneWidget);

    await tester.tap(find.text('Claude Haiku 5.5'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('AI MODEL'), findsNothing, reason: 'picking closes the menu');
    expect(find.text('Claude Haiku 5.5'), findsOneWidget);

    await askFirstSuggestion(tester);
    expect(models, ['haiku']);
  });

  testWidgets('tapping outside closes the menu without changing the pick', (
    tester,
  ) async {
    final (:models, asked: _, auth: _) = await pumpHome(tester, offered: _offered);
    await openMenu(tester, 'Gemma 4');
    await tester.tapAt(const Offset(200, 700));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('AI MODEL'), findsNothing);

    await askFirstSuggestion(tester);
    expect(models, ['gemma']);
  });

  testWidgets('the menu adds no blur (CLAUDE.md #11)', (tester) async {
    await pumpHome(tester, offered: _offered);
    await openMenu(tester, 'Gemma 4');
    expect(blurs(tester), lessThanOrEqualTo(2));
  });

  testWidgets('nothing offered: the plain Bulletin pill, nothing to open', (
    tester,
  ) async {
    final (:models, asked: _, auth: _) = await pumpHome(tester);
    expect(find.text('Bulletin'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Model:')), findsNothing);

    await askFirstSuggestion(tester);
    expect(models, [null], reason: 'no key: the server default answers');
  });

  testWidgets('in a thread: Bulletin over the model, and New chat goes Home', (
    tester,
  ) async {
    await pumpHome(tester, offered: _offered);
    await askFirstSuggestion(tester);
    expect(find.byType(HomeView), findsNothing);
    expect(find.text('Bulletin'), findsOneWidget);
    expect(find.text('Gemma 4'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('New chat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(HomeView), findsOneWidget);
    expect(find.bySemanticsLabel('New chat'), findsNothing);
  });

  testWidgets('Bangla at 200% with the menu open does not overflow', (tester) async {
    await pumpHome(tester, offered: _offered, locale: const Locale('bn'), textScale: 2);
    await openMenu(tester, 'Gemma 4');
    expect(tester.takeException(), isNull);
    expect(find.text('এআই মডেল'.toUpperCase()), findsOneWidget);
  });
}
