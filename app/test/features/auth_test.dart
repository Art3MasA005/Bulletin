// The auth steps against a fake repository. What these pin is behaviour a
// restyle could silently break: a malformed email never reaching the server,
// a wrong password landing on the password field (not in a generic box), the
// sign-up that returns no session moving to check-email instead of looking
// dead, and every step surviving Bangla at 200% text scale.
import 'dart:async';

import 'package:bulletin/core/theme/theme.dart';
import 'package:bulletin/core/widgets/bulletin_logo.dart';
import 'package:bulletin/core/widgets/crystal_glass.dart';
import 'package:bulletin/core/widgets/drifting_clouds.dart';
import 'package:bulletin/features/auth/data/auth_repository.dart';
import 'package:bulletin/features/auth/domain/auth_result.dart';
import 'package:bulletin/features/auth/presentation/auth_flow.dart';
import 'package:bulletin/features/auth/presentation/auth_flow_controller.dart';
import 'package:bulletin/features/auth/presentation/check_email/check_email_screen.dart';
import 'package:bulletin/features/auth/presentation/create_account/create_account_screen.dart';
import 'package:bulletin/features/auth/presentation/sign_in/sign_in_screen.dart';
import 'package:bulletin/features/auth/presentation/widgets/auth_sheet_scaffold.dart';
import 'package:bulletin/features/auth/presentation/widgets/sheet_panda.dart';
import 'package:bulletin/features/auth/presentation/welcome/welcome_screen.dart';
import 'package:bulletin/features/splash/domain/launch_phase.dart';
import 'package:bulletin/features/splash/presentation/launch_controller.dart';
import 'package:bulletin/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuth implements AuthRepository {
  final calls = <String>[];
  AuthResult<void> signInResult = const AuthOk(null);
  AuthResult<SignUpOutcome> signUpResult = const AuthOk(SignUpOutcome.confirmationSent);
  Completer<void>? hold;

  @override
  Future<AuthResult<void>> signIn({
    required String email,
    required String password,
  }) async {
    calls.add('signIn:$email');
    await hold?.future;
    return signInResult;
  }

  @override
  Future<AuthResult<SignUpOutcome>> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    calls.add('signUp:$email');
    return signUpResult;
  }

  @override
  Future<AuthResult<void>> sendPasswordReset(String email) async {
    calls.add('reset:$email');
    return const AuthOk(null);
  }

  @override
  Future<AuthResult<void>> resendConfirmation(String email) async {
    calls.add('resend:$email');
    return const AuthOk(null);
  }

  @override
  String? fullName;

  @override
  Future<AuthResult<void>> signOut() async {
    calls.add('signOut');
    return const AuthOk(null);
  }
}

/// The splash has already left, so screens play their entry at once.
class _Launched extends LaunchController {
  @override
  LaunchPhase build() => LaunchPhase.done;
}

/// The flow, already at [step]: most tests are about sign in onwards.
class _StartAt extends AuthFlowController {
  _StartAt(this.step);

  final AuthStep step;

  @override
  AuthFlowState build() => AuthFlowState(step: step);
}

Future<FakeAuth> pumpFlow(
  WidgetTester tester, {
  FakeAuth? auth,
  Locale locale = const Locale('en'),
  double textScale = 1,
  AuthStep start = AuthStep.signIn,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final fake = auth ?? FakeAuth();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fake),
        launchPhaseProvider.overrideWith(_Launched.new),
        if (start != AuthStep.welcome)
          authFlowProvider.overrideWith(() => _StartAt(start)),
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
        home: const AuthFlow(),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  return fake;
}

Finder field(int index) => find.byType(TextField).at(index);

Future<void> tapText(WidgetTester tester, String text) async {
  // With large text the target can sit below what the scroll view has built.
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(find.text(text).last);
  await tester.pump(); // lay out at the new scroll offset before tapping
  await tester.tap(find.text(text).last);
  await settleStep(tester);
}

/// A step change: the frame that starts it, the animation, then the frame
/// in which the switcher drops the outgoing step.
Future<void> settleStep(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// Tears the tree down so autoDispose controllers (and their timers) go.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  group('welcome', () {
    testWidgets('is the first step, and Log in opens sign in', (tester) async {
      await pumpFlow(tester, start: AuthStep.welcome);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.text('Answers for every campus question.'), findsOneWidget);

      await tapText(tester, 'Log in');
      expect(find.byType(SignInScreen), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await settleStep(tester);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('Bangla at 200% text scale does not overflow', (tester) async {
      await pumpFlow(
        tester,
        start: AuthStep.welcome,
        locale: const Locale('bn'),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tapText(tester, 'লগ ইন করুন');
      expect(find.byType(SignInScreen), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a short phone scrolls to the button instead of overflowing', (
      tester,
    ) async {
      await pumpFlow(tester, start: AuthStep.welcome);
      tester.view.physicalSize = const Size(360, 640);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tapText(tester, 'Log in');
      expect(find.byType(SignInScreen), findsOneWidget);
      await unmount(tester);
    });
  });

  group('sign in', () {
    testWidgets('a malformed email is caught before any request', (tester) async {
      final auth = await pumpFlow(tester);
      await tester.enterText(field(0), 'nusrat@green');
      await tester.enterText(field(1), 'campus2026');
      await tapText(tester, 'Sign in');

      expect(auth.calls, isEmpty);
      expect(
        find.text('This email is incomplete. Add the domain, like name@green.edu.bd.'),
        findsOneWidget,
      );
    });

    testWidgets('a wrong password is shown as a password problem', (tester) async {
      final auth = FakeAuth()
        ..signInResult = const AuthFailed(AuthError.invalidCredentials);
      await pumpFlow(tester, auth: auth);
      await tester.enterText(field(0), 'student@example.com');
      await tester.enterText(field(1), 'not-it');
      await tapText(tester, 'Sign in');

      expect(auth.calls, ['signIn:student@example.com']);
      expect(
        find.text(
          "This password doesn't match the email. Check it, or reset your password.",
        ),
        findsOneWidget,
      );
      // The helper line gives way to the error.
      expect(find.text('At least 8 characters.'), findsNothing);
    });

    testWidgets('busy while the request is in flight, and one request only', (
      tester,
    ) async {
      final auth = FakeAuth()..hold = Completer<void>();
      await pumpFlow(tester, auth: auth);
      await tester.enterText(field(0), 'student@example.com');
      await tester.enterText(field(1), 'campus2026');
      await tapText(tester, 'Sign in');

      expect(find.text('Signing in'), findsOneWidget);
      await tester.tap(find.text('Signing in'));
      await tester.pump();
      expect(auth.calls, hasLength(1));

      auth.hold!.complete();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Signing in'), findsNothing);
    });

    testWidgets('reset password without an email asks for one', (tester) async {
      final auth = await pumpFlow(tester);
      await tapText(tester, 'Reset password');
      expect(auth.calls, isEmpty);
      expect(
        find.text('Enter your email above, then tap Reset password.'),
        findsOneWidget,
      );

      await tester.enterText(field(0), 'student@example.com');
      await tapText(tester, 'Reset password');
      expect(auth.calls, ['reset:student@example.com']);
    });

    testWidgets('Bangla at 200% text scale does not overflow', (tester) async {
      await pumpFlow(tester, locale: const Locale('bn'), textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets('the header: glass back button, drifting clouds, no logo tile', (
      tester,
    ) async {
      await pumpFlow(tester);
      final signIn = find.byType(SignInScreen);
      expect(
        find.descendant(of: signIn, matching: find.byType(CrystalGlass)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: signIn, matching: find.byType(DriftingClouds)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: signIn, matching: find.byType(BulletinMark)),
        findsNothing,
      );
      await unmount(tester);
    });
  });

  group('create account', () {
    testWidgets('the invite button starts at create account', (tester) async {
      await pumpFlow(tester);
      await tapText(tester, 'Join with invite code');
      expect(find.byType(CreateAccountScreen), findsOneWidget);
    });

    testWidgets('a short password error states the count', (tester) async {
      final auth = await pumpFlow(tester);
      await tapText(tester, 'Create account');
      await tester.enterText(field(0), 'Nusrat Jahan');
      await tester.enterText(field(1), 'student@example.com');
      await tester.enterText(field(2), 'abc12');
      await tapText(tester, 'Create account');

      expect(auth.calls, isEmpty);
      expect(find.text('Use at least 8 characters. This one has 5.'), findsOneWidget);
    });

    testWidgets('a sign-up with no session moves to check email', (tester) async {
      final auth = await pumpFlow(tester);
      await tapText(tester, 'Create account');
      await tester.enterText(field(0), 'Nusrat Jahan');
      await tester.enterText(field(1), 'student@example.com');
      await tester.enterText(field(2), 'campus2026');
      await tapText(tester, 'Create account');

      expect(auth.calls, ['signUp:student@example.com']);
      expect(find.byType(CheckEmailScreen), findsOneWidget);
      expect(
        find.textContaining('student@example.com', findRichText: true),
        findsWidgets,
      );
      // Resend is cooling down, so it is inert.
      await tester.tap(find.text('Resend link'));
      expect(auth.calls, hasLength(1));
      await unmount(tester);
    });

    testWidgets("uses Sign in's layout: header, glass back, clouds, panda", (
      tester,
    ) async {
      await pumpFlow(tester, start: AuthStep.createAccount);
      final create = find.byType(CreateAccountScreen);
      for (final part in [AuthSheetScaffold, CrystalGlass, DriftingClouds, SheetPanda]) {
        expect(find.descendant(of: create, matching: find.byType(part)), findsOneWidget);
      }
      expect(find.text('Already have an account?'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the panda paints above the drifting clouds', (tester) async {
      // A viewport paints earlier slivers over later ones; with the header
      // and the sheet as two slivers, the clouds crossed over the panda.
      await pumpFlow(tester);
      Element sliverOf(Finder f) => tester.element(
        find.ancestor(of: f, matching: find.byType(SliverFillRemaining)),
      );
      expect(
        sliverOf(find.byType(SheetPanda)),
        same(sliverOf(find.byType(DriftingClouds))),
        reason: 'header and sheet share one sliver, sheet painted last',
      );
      await unmount(tester);
    });

    testWidgets('back returns to sign in', (tester) async {
      await pumpFlow(tester);
      await tapText(tester, 'Create account');
      await tester.tap(find.bySemanticsLabel('Back'));
      await settleStep(tester);
      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets('Bangla at 200% text scale does not overflow', (tester) async {
      await pumpFlow(tester, locale: const Locale('bn'), textScale: 2);
      await tapText(tester, 'অ্যাকাউন্ট খুলুন');
      expect(tester.takeException(), isNull);
      expect(find.byType(CreateAccountScreen), findsOneWidget);
    });
  });

  testWidgets('the flow controller walks back step by step', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(authFlowProvider, (_, _) {});
    addTearDown(sub.close);
    final flow = container.read(authFlowProvider.notifier);

    flow.goTo(AuthStep.checkEmail, pendingEmail: 'a@b.cd');
    expect(flow.back(), isTrue);
    expect(container.read(authFlowProvider).step, AuthStep.createAccount);
    expect(flow.back(), isTrue);
    expect(container.read(authFlowProvider).step, AuthStep.signIn);
    expect(flow.back(), isTrue);
    expect(container.read(authFlowProvider).step, AuthStep.welcome);
    expect(flow.back(), isFalse, reason: 'back from the first step leaves the app');
  });

  testWidgets('the logo paints at icon and tile sizes', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [BulletinAppIcon(size: 120), BulletinMark(size: 36)]),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
