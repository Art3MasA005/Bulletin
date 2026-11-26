// The hand-over between phases (README §5, MOTION.md): into the main app the
// old layer stays on top and fades + scales to 1.03 over 400 ms; elsewhere
// the new screen fades in over 300; while membership loads the old screen
// holds; reduced motion collapses it all to a 150 ms fade.
import 'package:bulletin/core/net/api_client.dart' show Membership;
import 'package:bulletin/core/routing/app_phase.dart';
import 'package:bulletin/core/routing/phase_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _member = Membership(userId: 'u', institutionId: 'i', role: 'student');

Widget screen(String name) => ColoredBox(
  key: ValueKey(name),
  color: const Color(0xFFFFFFFF),
  child: Center(child: Text(name)),
);

Future<void> pumpPhase(WidgetTester tester, AppPhase phase, {bool reduce = false}) {
  final name = phase.name;
  return tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: PhaseSwitcher(phase: phase, child: screen(name)),
      ),
    ),
  );
}

/// The opacity and scale the [name] screen is drawn at right now.
({double opacity, double scale}) drawn(WidgetTester tester, String name) {
  final target = find.byKey(ValueKey(name));
  final opacities = tester.widgetList<Opacity>(
    find.ancestor(of: target, matching: find.byType(Opacity)),
  );
  final fades = tester.widgetList<FadeTransition>(
    find.ancestor(of: target, matching: find.byType(FadeTransition)),
  );
  final scales = tester.widgetList<Transform>(
    find.ancestor(of: target, matching: find.byType(Transform)),
  );
  var opacity = 1.0;
  for (final o in opacities) {
    opacity *= o.opacity;
  }
  for (final f in fades) {
    opacity *= f.opacity.value;
  }
  var scale = 1.0;
  for (final t in scales) {
    scale *= t.transform.getMaxScaleOnAxis();
  }
  return (opacity: opacity, scale: scale);
}

void main() {
  group('appPhaseFor', () {
    test('signed out is auth, whatever membership says', () {
      expect(
        appPhaseFor(signedIn: false, membership: const AsyncData(_member)),
        AppPhase.auth,
      );
    });
    test('signed in: loading, then join or main', () {
      expect(
        appPhaseFor(signedIn: true, membership: const AsyncLoading()),
        AppPhase.loading,
      );
      expect(
        appPhaseFor(signedIn: true, membership: const AsyncData(null)),
        AppPhase.join,
      );
      expect(
        appPhaseFor(signedIn: true, membership: const AsyncData(_member)),
        AppPhase.main,
      );
      expect(
        appPhaseFor(
          signedIn: true,
          membership: AsyncError(Exception('x'), StackTrace.empty),
        ),
        AppPhase.join,
      );
    });
  });

  testWidgets('into main: auth stays on top, fades and grows to 1.03 over 400 ms', (
    tester,
  ) async {
    await pumpPhase(tester, AppPhase.auth);
    await pumpPhase(tester, AppPhase.main);

    // Both drawn, auth last (on top).
    final stack = tester.widget<Stack>(find.byType(Stack));
    expect(stack.children.last.key, const ValueKey(AppPhase.auth));
    expect(find.text('main'), findsOneWidget);
    expect(find.text('auth'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    final mid = drawn(tester, 'auth');
    expect(mid.opacity, inExclusiveRange(0, 1));
    expect(mid.scale, inExclusiveRange(1, 1.03));
    expect(
      drawn(tester, 'main').opacity,
      1,
      reason: 'Home is there beneath from the start',
    );

    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();
    expect(find.text('auth'), findsNothing);
    expect(find.text('main'), findsOneWidget);
  });

  testWidgets('the leaving screen is never rebuilt from scratch', (tester) async {
    // Re-parenting it would replay its entrance and drop what was typed.
    var built = 0;
    Widget counted(AppPhase phase) => MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: PhaseSwitcher(
          phase: phase,
          child: phase == AppPhase.auth
              ? _Counted(onInit: () => built++)
              : screen(phase.name),
        ),
      ),
    );
    await tester.pumpWidget(counted(AppPhase.auth));
    await tester.pumpWidget(counted(AppPhase.main));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(counted(AppPhase.auth));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      built,
      1,
      reason:
          'built once: not again while leaving, and coming back mid-way '
          'finds the same screen still there',
    );
  });

  testWidgets('signing out: auth fades in over the main app in 300 ms', (tester) async {
    await pumpPhase(tester, AppPhase.main);
    await pumpPhase(tester, AppPhase.auth);
    await tester.pump(const Duration(milliseconds: 100));
    expect(drawn(tester, 'auth').opacity, inExclusiveRange(0, 1));
    expect(drawn(tester, 'auth').scale, 1);

    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();
    expect(find.text('main'), findsNothing);
  });

  testWidgets('while membership loads, the previous screen holds', (tester) async {
    await pumpPhase(tester, AppPhase.auth);
    await pumpPhase(tester, AppPhase.loading);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('auth'), findsOneWidget);
    expect(find.text('loading'), findsNothing);

    await pumpPhase(tester, AppPhase.main);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('main'), findsOneWidget);
    expect(find.text('auth'), findsNothing);
  });

  testWidgets('a cold start with nothing before shows loading', (tester) async {
    await pumpPhase(tester, AppPhase.loading);
    expect(find.text('loading'), findsOneWidget);
  });

  testWidgets('reduced motion: a 150 ms fade, no scale', (tester) async {
    await pumpPhase(tester, AppPhase.auth, reduce: true);
    await pumpPhase(tester, AppPhase.main, reduce: true);
    await tester.pump(const Duration(milliseconds: 75));
    expect(drawn(tester, 'auth').scale, 1);
    await tester.pump(const Duration(milliseconds: 90));
    await tester.pump();
    expect(find.text('auth'), findsNothing);
  });
}

class _Counted extends StatefulWidget {
  const _Counted({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const Text('auth');
}
