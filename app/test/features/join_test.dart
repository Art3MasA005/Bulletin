// The Join step against a fake repository: a wrong code lands on the code
// field, a code too short to be one never reaches the server, offline shows
// its notice, both exits sign out, an empty display name falls back to the
// sign-up name, a join re-resolves membership (which is
// what moves the router on), and the screen survives Bangla at 200%.
import 'dart:async';

import 'package:bulletin/core/net/api_client.dart' show Membership;
import 'package:bulletin/core/providers.dart';
import 'package:bulletin/core/theme/theme.dart';
import 'package:bulletin/features/auth/data/auth_repository.dart';
import 'package:bulletin/features/auth/data/join_repository.dart';
import 'package:bulletin/features/auth/domain/join.dart';
import 'package:bulletin/features/auth/presentation/join/join_controller.dart';
import 'package:bulletin/features/auth/presentation/join/join_screen.dart';
import 'package:bulletin/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test.dart' show FakeAuth;

class FakeJoin implements JoinRepository {
  final calls = <(String, String?)>[];
  JoinResult result = const JoinFailed(JoinError.codeNotFound);
  Completer<void>? hold;

  @override
  Future<JoinResult> join(String inviteCode, {String? displayName}) async {
    calls.add((inviteCode, displayName));
    await hold?.future;
    return result;
  }
}

Future<(FakeJoin, FakeAuth)> pumpJoin(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  double textScale = 1,
  FakeJoin? join,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final fakeJoin = join ?? FakeJoin();
  final fakeAuth = FakeAuth();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        joinRepositoryProvider.overrideWithValue(fakeJoin),
        authRepositoryProvider.overrideWithValue(fakeAuth),
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
        home: const JoinScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  return (fakeJoin, fakeAuth);
}

Finder field(int index) => find.byType(TextField).at(index);

Future<void> tapJoin(WidgetTester tester) async {
  // A notice can push the button below the fold; the page scrolls to it.
  await tester.ensureVisible(find.text('Join institution').last);
  await tester.pump();
  await tester.tap(find.text('Join institution').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('the code is upper-cased as typed', (tester) async {
    await pumpJoin(tester);
    await tester.enterText(field(0), 'gub-test-00');
    await tester.pump();
    expect(find.text('GUB-TEST-00'), findsOneWidget);
  });

  testWidgets('a wrong code is shown on the code field, and editing clears it', (
    tester,
  ) async {
    final (join, _) = await pumpJoin(tester);
    await tester.enterText(field(0), 'GUB-0000-00');
    await tapJoin(tester);

    expect(join.calls, [('GUB-0000-00', null)]);
    expect(
      find.text("This code doesn't match any institution. Check it with your office."),
      findsOneWidget,
    );
    expect(
      find.text('Letters and numbers only. The letter O and the number 0 are different.'),
      findsNothing,
      reason: 'the error replaces the helper',
    );

    await tester.enterText(field(0), 'GUB-0000-0');
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text("This code doesn't match any institution. Check it with your office."),
      findsNothing,
    );
  });

  testWidgets('a code too short to be one never reaches the server', (tester) async {
    final (join, _) = await pumpJoin(tester);
    await tester.enterText(field(0), 'GU');
    await tapJoin(tester);

    expect(join.calls, isEmpty);
    expect(
      find.text("This code doesn't match any institution. Check it with your office."),
      findsOneWidget,
    );
  });

  testWidgets('offline shows the notice, and the button stays live for a retry', (
    tester,
  ) async {
    final join = FakeJoin()..result = const JoinFailed(JoinError.offline);
    await pumpJoin(tester, join: join);
    await tester.enterText(field(0), 'GUB-TEST-00');
    await tapJoin(tester);

    expect(find.text("You're offline. Connect to the internet to join."), findsOneWidget);
    await tapJoin(tester);
    expect(join.calls, hasLength(2));
  });

  testWidgets('the display name is sent trimmed, and only when given', (tester) async {
    final (join, _) = await pumpJoin(tester);
    await tester.enterText(field(0), 'GUB-TEST-00');
    await tester.enterText(field(1), '  Nusrat  ');
    await tapJoin(tester);
    expect(join.calls.single.$2, 'Nusrat');
  });

  testWidgets('left empty, the display name falls back to the sign-up name', (
    tester,
  ) async {
    final (join, auth) = await pumpJoin(tester);
    auth.fullName = 'Nusrat Jahan';
    await tester.enterText(field(0), 'GUB-TEST-00');
    await tapJoin(tester);
    expect(join.calls.single.$2, 'Nusrat Jahan');
  });

  testWidgets('a busy join sends one request and says so', (tester) async {
    final join = FakeJoin()..hold = Completer<void>();
    await pumpJoin(tester, join: join);
    await tester.enterText(field(0), 'GUB-TEST-00');
    await tapJoin(tester);

    expect(find.text('Joining'), findsOneWidget);
    await tester.tap(find.text('Joining'));
    await tester.pump();
    expect(join.calls, hasLength(1));

    join.hold!.complete();
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('back and "Sign out" both sign out', (tester) async {
    final (_, auth) = await pumpJoin(tester);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pump();
    await tester.tap(find.text('Sign out'));
    await tester.pump();
    expect(auth.calls, ['signOut', 'signOut']);
  });

  testWidgets('Bangla at 200% text scale does not overflow', (tester) async {
    await pumpJoin(tester, locale: const Locale('bn'), textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('প্রতিষ্ঠানে যোগ দিন'), findsWidgets);
  });

  test('a join re-resolves membership, which moves the router on', () async {
    var resolved = 0;
    final join = FakeJoin()
      ..result = const Joined(
        Membership(
          userId: 'u',
          institutionId: 'i',
          institutionName: 'Green University',
          role: 'student',
        ),
      );
    final container = ProviderContainer(
      overrides: [
        joinRepositoryProvider.overrideWithValue(join),
        authRepositoryProvider.overrideWithValue(FakeAuth()),
        membershipProvider.overrideWith((ref) async {
          resolved++;
          return null;
        }),
      ],
    );
    addTearDown(container.dispose);
    final membership = container.listen(membershipProvider, (_, _) {});
    addTearDown(membership.close);
    final form = container.listen(joinControllerProvider, (_, _) {});
    addTearDown(form.close);
    await container.read(membershipProvider.future);

    await container
        .read(joinControllerProvider.notifier)
        .submit(code: 'gub-test-00', displayName: '');
    await container.read(membershipProvider.future);

    expect(join.calls.single, ('gub-test-00', null));
    expect(resolved, 2);
    expect(container.read(joinControllerProvider).failure, isNull);
  });

  test('invite codes normalise as the server reads them', () {
    expect(normalizeInviteCode('  gub-test-00 '), 'GUB-TEST-00');
    expect(isPlausibleInviteCode('abc'), isFalse);
    expect(isPlausibleInviteCode('abcd'), isTrue);
    expect(isPlausibleInviteCode('A' * 33), isFalse);
  });
}
