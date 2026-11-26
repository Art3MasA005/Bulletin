// The splash is timed to the millisecond by the handoff (README §4), and the
// client already rejected one build for a visible stop in the wave. These
// tests pin the parts a refactor would break silently: the wave never
// pausing mid-swing, then coming to rest with the paw down, the auto-advance clock, the tap-to-skip, reduced motion, and the
// hand-over to the app beneath.
import 'dart:math' as math;

import 'package:bulletin/core/theme/theme.dart';
import 'package:bulletin/features/splash/domain/launch_phase.dart';
import 'package:bulletin/features/splash/domain/splash_timeline.dart';
import 'package:bulletin/features/splash/presentation/launch_controller.dart';
import 'package:bulletin/features/splash/presentation/launch_gate.dart';
import 'package:bulletin/features/splash/presentation/splash_screen.dart';
import 'package:bulletin/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Image decoding needs real async, which the fake clock never runs.
Future<void> noPrepare(BuildContext _) async {}

Widget host(
  Widget child, {
  Locale locale = const Locale('en'),
  double textScale = 1,
  bool reduceMotion = false,
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: L.localizationsDelegates,
    supportedLocales: L.supportedLocales,
    theme: buildBulletinTheme(),
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduceMotion,
      ),
      child: app!,
    ),
    home: child,
  );
}

void useDesignFrame(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The wave's current angle, in degrees, read off its Transform.
double waveDegrees(WidgetTester tester) {
  final m = tester.widget<Transform>(find.byKey(const ValueKey('panda-wave'))).transform;
  return math.atan2(m.entry(1, 0), m.entry(0, 0)) * 180 / math.pi;
}

/// How far the waving paw has dropped from its raised place, in px.
double pawDrop(WidgetTester tester) {
  final transforms = tester.widgetList<Transform>(
    find.ancestor(
      of: find.byKey(const ValueKey('panda-wave')),
      matching: find.byType(Transform),
    ),
  );
  // Nearest first: the paw-up tilt, then the paw-up translate.
  return transforms.elementAt(1).transform.getTranslation().y;
}

void main() {
  group('timeline', () {
    test('every one-shot beat ends inside the intro', () {
      final beats = <Beat>[
        SplashTimeline.ledge,
        SplashTimeline.rise,
        SplashTimeline.grip,
        SplashTimeline.pawUp,
        SplashTimeline.tagline,
        for (var i = 0; i < 'Bulletin'.length; i++) SplashTimeline.letter(i),
      ];
      for (final beat in beats) {
        expect(beat.end, lessThanOrEqualTo(SplashTimeline.introTotal));
      }
    });

    test('the wave ends inside the first-launch splash, with time to see it rest', () {
      expect(
        SplashTimeline.pawDown.end,
        SplashTimeline.waveTotal,
        reason: 'the wave clock ends when the paw is down',
      );
      expect(SplashTimeline.pawDown.delay, lessThan(SplashTimeline.swingsTotal));
      expect(
        SplashTimeline.waveStart + SplashTimeline.waveTotal,
        lessThanOrEqualTo(SplashTimeline.autoAdvance.inMilliseconds - 250),
      );
    });

    test('the returning-user splash still lets the tagline land', () {
      expect(
        SplashTimeline.autoAdvanceReturning.inMilliseconds,
        greaterThan(SplashTimeline.tagline.end),
      );
      expect(SplashTimeline.autoAdvanceReturning, lessThan(SplashTimeline.autoAdvance));
    });
  });

  group('SplashScreen', () {
    testWidgets('auto-advances at 4200 ms, once', (tester) async {
      useDesignFrame(tester);
      var finished = 0;
      await tester.pumpWidget(
        host(SplashScreen(onFinished: () => finished++, prepare: noPrepare)),
      );
      await tester.pump(); // prepare completes; the start is scheduled
      await tester.pump(); // frame 0: the clock starts here

      await tester.pump(const Duration(milliseconds: 4150));
      expect(finished, 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(finished, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(finished, 1);
    });

    testWidgets('a tap skips, and a second tap does nothing', (tester) async {
      useDesignFrame(tester);
      var finished = 0;
      await tester.pumpWidget(
        host(SplashScreen(onFinished: () => finished++, prepare: noPrepare)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(SplashScreen));
      await tester.tap(find.byType(SplashScreen));
      expect(finished, 1);
    });

    testWidgets('the paw holds at +6° until the wave starts', (tester) async {
      useDesignFrame(tester);
      await tester.pumpWidget(host(SplashScreen(onFinished: () {}, prepare: noPrepare)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(waveDegrees(tester), closeTo(SplashTimeline.waveFrom, 0.01));
    });

    testWidgets('the wave never pauses mid-swing and stays between −11° and +6°', (
      tester,
    ) async {
      useDesignFrame(tester);
      await tester.pumpWidget(
        host(
          SplashScreen(
            onFinished: () {},
            prepare: noPrepare,
            autoAdvance: const Duration(minutes: 1),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: SplashTimeline.waveStart + 20));

      // Sample every 60 ms through every swing but the settling one, which
      // is meant to slow to a stop. A hold anywhere before it (the rejected
      // 0° stop) shows up as two equal consecutive samples.
      final swinging = SplashTimeline.swingsTotal - SplashTimeline.swings.last.duration;
      var previous = waveDegrees(tester);
      for (var i = 0; i < swinging ~/ 60 - 1; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        final now = waveDegrees(tester);
        expect(
          now,
          inInclusiveRange(SplashTimeline.waveTo - 0.01, SplashTimeline.waveFrom + 0.01),
        );
        expect(
          (now - previous).abs(),
          greaterThan(0.05),
          reason: 'wave stalled at sample $i',
        );
        previous = now;
      }
    });

    testWidgets('the wave comes to rest upright, and the paw goes down', (tester) async {
      useDesignFrame(tester);
      await tester.pumpWidget(
        host(
          SplashScreen(
            onFinished: () {},
            prepare: noPrepare,
            autoAdvance: const Duration(minutes: 1),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      // Mid-wave, after the paw has risen (pawUp ends at 1320).
      await tester.pump(const Duration(milliseconds: SplashTimeline.waveStart + 400));
      expect(pawDrop(tester), lessThan(1), reason: 'the paw is up while waving');

      await tester.pump(const Duration(milliseconds: SplashTimeline.waveTotal + 50));
      expect(waveDegrees(tester), closeTo(0, 0.01));
      expect(pawDrop(tester), greaterThan(150), reason: 'behind the ledge (0.85 x 190)');

      // And it stays there: no loop restarts it.
      await tester.pump(const Duration(seconds: 2));
      expect(waveDegrees(tester), closeTo(0, 0.01));
      expect(pawDrop(tester), greaterThan(150));
    });

    testWidgets('reduced motion: static panda, text in 150 ms, no loops', (tester) async {
      useDesignFrame(tester);
      await tester.pumpWidget(
        host(SplashScreen(onFinished: () {}, prepare: noPrepare), reduceMotion: true),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));

      final fades = tester.widgetList<FadeTransition>(
        find.descendant(
          of: find.byType(SplashScreen),
          matching: find.byType(FadeTransition),
        ),
      );
      for (final fade in fades) {
        expect(fade.opacity.value, 1);
      }
      expect(waveDegrees(tester), 0);
      await tester.pump(const Duration(seconds: 2));
      expect(waveDegrees(tester), 0);
    });

    testWidgets('Bangla at 200% text scale does not overflow', (tester) async {
      useDesignFrame(tester);
      await tester.pumpWidget(
        host(
          SplashScreen(onFinished: () {}, prepare: noPrepare),
          locale: const Locale('bn'),
          textScale: 2,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: SplashTimeline.introTotal));
      expect(tester.takeException(), isNull);
      expect(
        find.text('ক্যাম্পাসের ডকুমেন্ট থেকে উত্তর, সঙ্গে উৎসের পাতা।'),
        findsOneWidget,
      );
    });
  });

  group('LaunchGate', () {
    testWidgets('hands over to the app and leaves the tree', (tester) async {
      useDesignFrame(tester);
      final container = ProviderContainer(
        overrides: [
          splashAutoAdvanceProvider.overrideWithValue(SplashTimeline.autoAdvance),
        ],
      );
      addTearDown(container.dispose);
      var taps = 0;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: host(
            LaunchGate(
              prepare: noPrepare,
              child: Center(
                child: TextButton(onPressed: () => taps++, child: const Text('APP')),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // During the splash the app is built but takes no input.
      expect(find.text('APP'), findsOneWidget);
      await tester.tapAt(tester.getCenter(find.text('APP')));
      expect(taps, 0, reason: 'the tap went to the splash, which skips');
      expect(container.read(launchPhaseProvider), LaunchPhase.revealing);

      // The exit's first frame is its t = 0. A controller completes on the
      // first tick strictly AFTER its duration, hence the extra frame.
      await tester.pump();
      await tester.pump(SplashTimeline.exit);
      await tester.pump(const Duration(milliseconds: 16));
      expect(container.read(launchPhaseProvider), LaunchPhase.done);
      expect(find.byType(SplashScreen), findsNothing);

      await tester.tap(find.text('APP'));
      expect(taps, 1);
    });
  });
}
