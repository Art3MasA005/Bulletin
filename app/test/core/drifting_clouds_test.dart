// The drifting clouds (handoff CHANGES.md): each cloud crosses from fully
// off-screen left to fully off-screen right and loops, starts part-way in so
// they are spread out on the first frame, bobs no more than 4 px, and under
// reduced motion runs no ticker at all.
import 'package:bulletin/core/widgets/drifting_clouds.dart';
import 'package:bulletin/features/auth/presentation/welcome/welcome_clouds.dart';
import 'package:bulletin/features/auth/presentation/widgets/auth_header_clouds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final scenes = {'welcome': welcomeClouds, 'auth header': authHeaderClouds};

  for (final MapEntry(key: name, value: scene) in scenes.entries) {
    group(name, () {
      test('every cloud starts fully off the left and ends fully off the right', () {
        for (final c in scene.clouds) {
          expect(c.rect.left + c.from + c.rect.width, lessThanOrEqualTo(0));
          expect(c.rect.left + c.to, greaterThanOrEqualTo(390));
        }
      });

      test('the clouds are spread out on the first frame', () {
        final xs = [for (final c in scene.clouds) c.rect.left + cloudOffset(c, 0).dx];
        expect(xs.where((x) => x > -100 && x < 390), isNotEmpty);
        expect(xs.toSet(), hasLength(xs.length));
      });
    });
  }

  test('a cloud loops: one full drift later it is back where it was', () {
    final c = welcomeClouds.clouds[1];
    for (final t in [0.0, 7.3, 21.0]) {
      expect(cloudOffset(c, t + c.pace.drift).dx, closeTo(cloudOffset(c, t).dx, 1e-6));
    }
  });

  test('the drift is linear and moves left to right', () {
    final c = welcomeClouds.clouds[1];
    final a = cloudOffset(c, 1).dx;
    final b = cloudOffset(c, 2).dx;
    final d = cloudOffset(c, 3).dx;
    expect(b, greaterThan(a));
    expect(d - b, closeTo(b - a, 1e-6));
  });

  test('the bob stays within 4 px, upwards', () {
    for (final c in [...welcomeClouds.clouds, ...authHeaderClouds.clouds]) {
      for (var t = 0.0; t < 20; t += 0.25) {
        expect(cloudOffset(c, t).dy, inInclusiveRange(-4, 0));
      }
    }
  });

  testWidgets('moving clouds keep a ticker; reduced motion keeps none', (tester) async {
    Widget host({required bool reduce}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: DriftingClouds(welcomeClouds),
      ),
    );

    await tester.pumpWidget(host(reduce: false));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(host(reduce: true));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.transientCallbackCount, 0);
  });
}
