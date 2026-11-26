// Settings (handoff README §2.11): the language switch changes the app at
// once and is remembered, the display name saves and Home greets by it,
// only an admin sees Documents, Sign out leaves Settings first, the push
// slides and the edge swipe goes back, and Bangla at 200% fits.
import 'package:bulletin/core/net/api_client.dart';
import 'package:bulletin/core/net/result.dart';
import 'package:bulletin/core/prefs/preferences.dart';
import 'package:bulletin/core/providers.dart';
import 'package:bulletin/core/routing/push_route.dart';
import 'package:bulletin/core/theme/theme.dart';
import 'package:bulletin/features/auth/data/auth_repository.dart';
import 'package:bulletin/features/settings/data/profile_repository.dart';
import 'package:bulletin/features/settings/presentation/settings_screen.dart';
import 'package:bulletin/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_test.dart' show FakeAuth;

Membership member({String role = 'student', String? name = 'Nusrat'}) => Membership(
  userId: 'u',
  institutionId: 'i',
  role: role,
  email: 'nusrat@green.edu.bd',
  institutionName: 'Green University of Bangladesh',
  displayName: name,
  inviteCode: 'GUB-TEST-00',
);

class FakeProfile implements ProfileRepository {
  final renamed = <String>[];
  Result<Membership>? answer;

  @override
  Future<Result<Membership>> rename(String displayName) async {
    renamed.add(displayName);
    return answer ?? Ok(member(name: displayName));
  }
}

class SettingsHarness {
  SettingsHarness(this.prefs, this.auth, this.profile);
  final SharedPreferences prefs;
  final FakeAuth auth;
  final FakeProfile profile;
}

/// A first screen with a button that pushes Settings, as Home does.
Future<SettingsHarness> pumpSettings(
  WidgetTester tester, {
  Membership? membership,
  bool withDocuments = false,
  Locale? locale,
  double textScale = 1,
  bool open = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final auth = FakeAuth();
  final profile = FakeProfile();
  final role = (membership ?? member()).role;
  final first = membership ?? member();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profile),
        // What the server would answer after a rename.
        membershipProvider.overrideWith(
          (ref) async => profile.renamed.isEmpty
              ? first
              : member(role: role, name: profile.renamed.last),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          locale: ref.watch(localeProvider) ?? locale ?? const Locale('en'),
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          theme: buildBulletinTheme(),
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: app!,
          ),
          home: Scaffold(
            body: Center(
              child: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => Navigator.of(context).push(
                    PushRoute<void>.of(
                      context,
                      (_) =>
                          SettingsScreen(onOpenDocuments: withDocuments ? () {} : null),
                    ),
                  ),
                  child: Text(
                    'home:${ref.watch(membershipProvider).valueOrNull?.displayName}',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  if (open) {
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
  }
  return SettingsHarness(prefs, auth, profile);
}

void main() {
  testWidgets('shows the profile, the institution and the joining code', (tester) async {
    await pumpSettings(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('nusrat@green.edu.bd'), findsOneWidget);
    expect(find.text('Green University of Bangladesh'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('GUB-TEST-00'), findsOneWidget);
  });

  testWidgets('Bangla switches the app at once and is remembered', (tester) async {
    final h = await pumpSettings(tester);
    await tester.tap(find.text('বাংলা'));
    await tester.pumpAndSettle();
    expect(find.text('সেটিংস'), findsOneWidget);
    expect(h.prefs.getString(PrefKeys.locale), 'bn');
  });

  testWidgets('the display name saves on done, and Home greets by it', (tester) async {
    final h = await pumpSettings(tester);
    await tester.enterText(find.byType(TextField), 'Nusrat J');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(h.profile.renamed, ['Nusrat J']);
    expect(find.bySemanticsLabel('Saved'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('home:Nusrat J'), findsOneWidget);
  });

  testWidgets('an unchanged name is not sent', (tester) async {
    final h = await pumpSettings(tester);
    await tester.tap(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(h.profile.renamed, isEmpty);
  });

  testWidgets('a failed save says so', (tester) async {
    final h = await pumpSettings(tester);
    h.profile.answer = const Failure(FailureKind.offline);
    await tester.enterText(find.byType(TextField), 'Rafi');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('a student does not see Documents', (tester) async {
    await pumpSettings(tester, withDocuments: true);
    expect(find.text('Documents'), findsNothing);
  });

  testWidgets('an admin does', (tester) async {
    await pumpSettings(tester, membership: member(role: 'admin'), withDocuments: true);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('Sign out leaves Settings, then signs out', (tester) async {
    final h = await pumpSettings(tester);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(h.auth.calls, ['signOut']);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('the push slides in from the right, the screen below moves left', (
    tester,
  ) async {
    await pumpSettings(tester, open: false);
    final restX = tester.getTopLeft(find.byType(TextButton)).dx;
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(find.text('Settings')).dx, greaterThan(24));
    expect(tester.getTopLeft(find.byType(TextButton)).dx, lessThan(restX));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Settings')).dx, 24);
  });

  testWidgets('a swipe from the left edge goes back', (tester) async {
    await pumpSettings(tester);
    await tester.dragFrom(const Offset(8, 400), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('a short slow swipe springs back', (tester) async {
    await pumpSettings(tester);
    await tester.timedDragFrom(
      const Offset(8, 400),
      const Offset(60, 0),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Settings')).dx, 24);
  });

  testWidgets('Bangla at 200% does not overflow', (tester) async {
    await pumpSettings(
      tester,
      membership: member(role: 'admin'),
      withDocuments: true,
      locale: const Locale('bn'),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('সেটিংস'), findsOneWidget);
  });
}
