// The confirmation sheet is a correctness boundary (CLAUDE.md #3), so these
// tests care about what the sheet *refuses* to return as much as what it does.
//
// The bug each of them would have caught is a silent one: a misread course
// code cannot be detected downstream, so if the sheet ever hands back an
// unedited code, or hands back anything at all when the user dismissed it, the
// student gets a confident answer about a course they are not taking.
import 'dart:async';

import 'package:bulletin/core/theme/theme.dart';
import 'package:bulletin/features/attachments/domain/extraction.dart';
import 'package:bulletin/features/attachments/presentation/confirm_sheet.dart';
import 'package:bulletin/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RoutineExtraction extraction({
  List<ExtractedCourse>? courses,
  bool ok = true,
  String? semester = 'Summer 2026',
}) => RoutineExtraction(
  attachmentId: 'att-1',
  semester: semester,
  ok: ok,
  courses:
      courses ??
      const [
        ExtractedCourse(code: 'CSE 3103', confidence: 0.97, needsReview: false),
        ExtractedCourse(code: 'CSE 3108', confidence: 0.62, needsReview: true),
      ],
);

/// What the sheet resolved to, and whether it resolved at all.
///
/// `codes == null` after the sheet closes means the user backed out. That is a
/// different outcome from an empty list, and the send path depends on the
/// difference.
class Outcome {
  List<String>? codes;
  bool closed = false;
}

Future<Outcome> openSheet(
  WidgetTester tester,
  RoutineExtraction value, {
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) async {
  final outcome = Outcome();
  late BuildContext hostContext;

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      theme: buildBulletinTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    ),
  );

  unawaited(
    showConfirmExtractionSheet(hostContext, value).then((codes) {
      outcome
        ..codes = codes
        ..closed = true;
    }),
  );
  await tester.pumpAndSettle();
  return outcome;
}

void main() {
  testWidgets('renders every extracted code as an editable mono field', (tester) async {
    await openSheet(tester, extraction());

    expect(find.text('CSE 3103'), findsOneWidget);
    expect(find.text('CSE 3108'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(
      find.text('Found 2 courses in your routine. Correct these if needed.'),
      findsOneWidget,
    );
  });

  testWidgets('a low-confidence code is flagged with its score', (tester) async {
    // DESIGN §5: the number is shown, not just a coloured dot — a student can
    // act on "0.62", not on a shade of orange.
    await openSheet(tester, extraction());

    expect(find.textContaining('0.62'), findsOneWidget);
    expect(find.textContaining('Check this one'), findsOneWidget);
  });

  testWidgets('dismissing the sheet confirms nothing', (tester) async {
    // CLAUDE.md #3: walking away is not confirmation. If this ever resolves to
    // a list, the send path proceeds on unverified OCR output.
    final outcome = await openSheet(tester, extraction());

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(outcome.closed, isTrue);
    expect(outcome.codes, isNull);
  });

  testWidgets('a corrected code replaces the misread one', (tester) async {
    final outcome = await openSheet(tester, extraction());

    // The whole reason the sheet exists: 3108 was really 3109.
    await tester.enterText(find.text('CSE 3108'), 'cse 3109');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Looks right'));
    await tester.pumpAndSettle();

    // Upper-cased on the way out, so the join query does not depend on how the
    // user happened to type it.
    expect(outcome.codes, ['CSE 3103', 'CSE 3109']);
  });

  testWidgets('a blank row is dropped rather than confirmed', (tester) async {
    final outcome = await openSheet(tester, extraction());

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));

    await tester.tap(find.textContaining('Looks right'));
    await tester.pumpAndSettle();

    expect(outcome.codes, ['CSE 3103', 'CSE 3108']);
  });

  testWidgets('a failed extraction opens with one blank row, not a dead end', (
    tester,
  ) async {
    await openSheet(tester, extraction(courses: const [], ok: false, semester: null));

    expect(find.textContaining('could not be read'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('confirm is inert until at least one code is present', (tester) async {
    await openSheet(tester, extraction(courses: const [], ok: false, semester: null));

    Color? buttonColor() => tester
        .widgetList<Material>(
          find.ancestor(
            of: find.textContaining('Looks right'),
            matching: find.byType(Material),
          ),
        )
        .first
        .color;

    expect(buttonColor(), BulletinColors.inert);

    await tester.enterText(find.byType(TextField), 'CSE 4101');
    await tester.pumpAndSettle();

    expect(buttonColor(), BulletinColors.accent);
  });

  testWidgets('Bangla at 200% text scale does not overflow', (tester) async {
    await openSheet(tester, extraction(), locale: const Locale('bn'), textScale: 2.0);

    expect(tester.takeException(), isNull);
  });
}
