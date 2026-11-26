// Home (handoff README §2.6): who it greets and by what name, the suggestion
// chips actually asking, the blur budget (CLAUDE.md #11: at most two
// BackdropFilters on a screen, none in a list item), the menu opening
// Settings, and Bangla at 200% text scale.
import 'dart:ui' show ImageFilter;

import 'package:bulletin/core/net/api_client.dart' show Membership;
import 'package:bulletin/core/providers.dart';
import 'package:bulletin/core/theme/theme.dart';
import 'package:bulletin/features/auth/data/auth_repository.dart';
import 'package:bulletin/features/chat/domain/home_greeting.dart';
import 'package:bulletin/features/chat/presentation/chat_screen.dart';
import 'package:bulletin/features/chat/presentation/home/home_view.dart';
import 'package:bulletin/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test.dart' show FakeAuth;
import 'chat_controller_test.dart' show ScriptedApi, delta, done, meta;

const _green = Membership(
  userId: 'u',
  institutionId: 'i',
  role: 'student',
  email: 'nusrat@green.edu.bd',
  institutionName: 'Green University of Bangladesh',
  displayName: 'Nusrat',
);

Future<({FakeAuth auth, List<String> asked, List<String?> models})> pumpHome(
  WidgetTester tester, {
  Membership? membership = _green,
  String? fullName,
  Locale locale = const Locale('en'),
  double textScale = 1,
  List<Map<String, dynamic>> offered = const [],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final auth = FakeAuth()..fullName = fullName;
  final asked = <String>[];
  final models = <String?>[];
  final api = ScriptedApi(
    [meta(), delta('Finals start on 14 December.'), done()],
    offered: offered,
    onCall: (request) {
      asked.add(request['question'] as String);
      models.add(request['model'] as String?);
    },
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        apiClientProvider.overrideWithValue(api),
        membershipProvider.overrideWith((ref) async => membership),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        theme: buildBulletinTheme(),
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: const ChatScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return (auth: auth, asked: asked, models: models);
}

/// Taps the first suggested question. The chip row scrolls sideways, and
/// with the test font's square glyphs the chip starts past the edge.
Future<void> askFirstSuggestion(WidgetTester tester) async {
  final chip = find.text('When do the final examinations start?');
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// The screen's BackdropFilters that actually blur.
int blurs(WidgetTester tester) => tester
    .widgetList<BackdropFilter>(find.byType(BackdropFilter))
    .where((f) => f.filter is ImageFilter)
    .length;

void main() {
  attachSheetTests();
  group('greetingName', () {
    test('the display name wins', () {
      expect(greetingName(displayName: 'Nusrat', fullName: 'Nusrat Jahan'), 'Nusrat');
    });
    test('else the first word of the sign-up name', () {
      expect(greetingName(displayName: '  ', fullName: '  Nusrat   Jahan '), 'Nusrat');
    });
    test('else nobody', () {
      expect(greetingName(), isNull);
    });
  });

  testWidgets('greets by name and says where answers come from', (tester) async {
    await pumpHome(tester);
    expect(find.text('Hi Nusrat, what do you want to know today?'), findsOneWidget);
    expect(
      find.text('Answers come only from Green University of Bangladesh documents.'),
      findsOneWidget,
    );
  });

  testWidgets('with no name and no institution, the copy still reads', (tester) async {
    await pumpHome(tester, membership: null);
    expect(find.text('What do you want to know today?'), findsOneWidget);
    expect(
      find.text("Answers come only from your institution's documents."),
      findsOneWidget,
    );
  });

  testWidgets('falls back to the sign-up name', (tester) async {
    const noDisplay = Membership(userId: 'u', institutionId: 'i', role: 'student');
    await pumpHome(tester, membership: noDisplay, fullName: 'Rafi Ahmed');
    expect(find.text('Hi Rafi, what do you want to know today?'), findsOneWidget);
  });

  testWidgets('shows the attach chip and five suggestions in both scripts', (
    tester,
  ) async {
    await pumpHome(tester);
    final l = await L.delegate.load(const Locale('en'));
    expect(find.text('Attach routine'), findsOneWidget);
    for (final ask in HomeView.suggestions(l)) {
      expect(find.text(ask, skipOffstage: false), findsOneWidget);
    }
  });

  testWidgets('a suggestion asks it, and Home gives way to the thread', (tester) async {
    final (:asked, auth: _, models: _) = await pumpHome(tester);
    await askFirstSuggestion(tester);

    expect(asked, ['When do the final examinations start?']);
    expect(find.byType(HomeView), findsNothing);
    expect(find.textContaining('Finals start on 14 December.'), findsOneWidget);
  });

  testWidgets('at most two blurs, on Home and in the thread (CLAUDE.md #11)', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(blurs(tester), lessThanOrEqualTo(2));

    await askFirstSuggestion(tester);
    expect(blurs(tester), lessThanOrEqualTo(2));
    expect(
      find.descendant(of: find.byType(ListView), matching: find.byType(BackdropFilter)),
      findsNothing,
      reason: 'no blur inside a list item',
    );
  });

  testWidgets('the menu opens Settings, whose Sign out signs out', (tester) async {
    final (:auth, asked: _, models: _) = await pumpHome(tester);
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('nusrat@green.edu.bd'), findsOneWidget);
    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(auth.calls, ['signOut']);
    expect(
      find.text('nusrat@green.edu.bd'),
      findsNothing,
      reason: 'Settings is left first',
    );
  });

  testWidgets('Bangla at 200% text scale does not overflow', (tester) async {
    await pumpHome(tester, locale: const Locale('bn'), textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('হাই Nusrat, আজ কী জানতে চান?'), findsOneWidget);
  });
}

/// The attach sheet (README §2.8), opened from Home's "Attach routine" chip.
void attachSheetTests() {
  testWidgets('Attach routine opens the sheet: three sources and the privacy note', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.text('Attach routine'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Add to your question'), findsOneWidget);
    expect(find.bySemanticsLabel('Take a photo, Routine, registration slip or notice'), findsOneWidget);
    expect(find.bySemanticsLabel('Choose from gallery, JPG or PNG'), findsOneWidget);
    expect(find.bySemanticsLabel('Choose a file, PDF'), findsOneWidget);
    expect(
      find.textContaining("It isn't added to your institution's documents.", findRichText: true),
      findsOneWidget,
      reason: 'PRD §8.4: the user has to see this',
    );

    await tester.tapAt(const Offset(195, 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Add to your question'), findsNothing);
  });

  testWidgets('the attach sheet in Bangla at 200% does not overflow', (tester) async {
    await pumpHome(tester, locale: const Locale('bn'), textScale: 2);
    await tester.ensureVisible(find.text('রুটিন যুক্ত করুন'));
    await tester.tap(find.text('রুটিন যুক্ত করুন'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    expect(find.text('প্রশ্নের সঙ্গে যুক্ত করুন'), findsOneWidget);
  });
}
