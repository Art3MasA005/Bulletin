import 'package:bulletin/core/theme/theme.dart';
import 'package:bulletin/features/chat/domain/citation.dart';
import 'package:bulletin/features/chat/presentation/source_card.dart';
import 'package:bulletin/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Citation citation({
  String lang = 'en',
  String snippet = 'Final examinations commence on 05 September 2026.',
  int page = 3,
  String? title = 'Exam Routine, Summer 2026',
  int n = 1,
}) => Citation(
  n: n,
  chunkId: n,
  documentId: 'doc-1',
  pageNo: page,
  lang: lang,
  snippet: snippet,
  title: title,
);

Widget host(Widget child, {Locale locale = const Locale('en'), double textScale = 1.0}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: L.localizationsDelegates,
    supportedLocales: L.supportedLocales,
    theme: buildBulletinTheme(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  testWidgets('shows the title, page number and snippet', (tester) async {
    await tester.pumpWidget(host(SourceCard(citation: citation(), onOpen: (_) {})));

    expect(find.text('Exam Routine, Summer 2026'), findsOneWidget);
    expect(find.text('Page 3'), findsOneWidget);
    expect(find.textContaining('05 September 2026'), findsOneWidget);
    expect(find.text('Open page 3'), findsOneWidget);
  });

  testWidgets('the left rule takes the source language, not the UI language', (
    tester,
  ) async {
    // DESIGN §4: a Bangla source under an English answer shows the bn marker.
    await tester.pumpWidget(host(SourceCard(citation: citation(lang: 'bn'))));

    final rule = tester
        .widgetList<Container>(find.byType(Container))
        .firstWhere(
          (c) =>
              c.constraints?.maxWidth == Sizes.sourceRule ||
              c.color == BulletinColors.bnMarker,
          orElse: () => Container(),
        );
    expect(rule.color, BulletinColors.bnMarker);
    expect(find.text('BN'), findsOneWidget);
  });

  testWidgets('a Bangla snippet renders untranslated in an English UI', (tester) async {
    const bangla = 'চূড়ান্ত পরীক্ষা ০৫ সেপ্টেম্বর ২০২৬ তারিখে শুরু হবে।';
    await tester.pumpWidget(
      host(
        SourceCard(
          citation: citation(lang: 'bn', snippet: bangla),
        ),
      ),
    );

    expect(find.text(bangla), findsOneWidget);
    final text = tester.widget<Text>(find.text(bangla));
    // ...and in the Bengali face, or the conjuncts render as boxes.
    expect(text.style?.fontFamily, Fonts.bangla);
  });

  testWidgets('Bangla at 200% text scale does not overflow', (tester) async {
    // CLAUDE.md: widget tests rendering Bangla at 200% text scale, asserting
    // no overflow. ক্ষ, জ্ঞ, ঞ্চ, র্ধ্ব are the conjuncts that clip first.
    const bangla =
        'পরীক্ষা সংক্রান্ত বিজ্ঞপ্তি: ক্ষ জ্ঞ ঞ্চ র্ধ্ব — চূড়ান্ত পরীক্ষা শুরু হবে।';
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        SourceCard(
          citation: citation(lang: 'bn', snippet: bangla, title: bangla),
          onOpen: (_) {},
        ),
        textScale: 2.0,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the whole card is one tap target', (tester) async {
    Citation? opened;
    await tester.pumpWidget(
      host(SourceCard(citation: citation(), onOpen: (c) => opened = c)),
    );

    await tester.tap(find.byType(SourceCard));
    expect(opened?.pageNo, 3);
  });

  testWidgets('meets the 48px minimum touch target', (tester) async {
    await tester.pumpWidget(
      host(
        SourceCard(
          citation: citation(snippet: ''),
          onOpen: (_) {},
        ),
      ),
    );
    final size = tester.getSize(find.byType(SourceCard));
    expect(size.height, greaterThanOrEqualTo(Sizes.minTouchTarget));
  });

  testWidgets('two cards show, the rest collapse to a count', (tester) async {
    final many = [for (var i = 1; i <= 5; i++) citation(n: i, page: i)];
    await tester.pumpWidget(host(SourceList(citations: many, onOpen: (_) {})));

    expect(find.byType(SourceCard), findsNWidgets(2));
    expect(find.text('3 more sources'), findsOneWidget);

    await tester.tap(find.text('3 more sources'));
    await tester.pumpAndSettle();
    expect(find.byType(SourceCard), findsNWidgets(5));
  });

  testWidgets('no sources renders nothing at all', (tester) async {
    await tester.pumpWidget(host(const SourceList(citations: [])));
    expect(find.byType(SourceCard), findsNothing);
  });

  testWidgets('the card is never frosted (CLAUDE.md #11)', (tester) async {
    await tester.pumpWidget(host(SourceCard(citation: citation(), onOpen: (_) {})));
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('renders in Bangla locale too', (tester) async {
    await tester.pumpWidget(
      host(
        SourceCard(citation: citation(), onOpen: (_) {}),
        locale: const Locale('bn'),
      ),
    );
    expect(find.text('পৃষ্ঠা 3'), findsOneWidget);
  });
}
