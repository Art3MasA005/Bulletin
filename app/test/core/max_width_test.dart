// MaxWidth caps width for measurement as well as layout. A ConstrainedBox
// does not, and the Sign in / Sign up sheet overflowed because of it.
import 'package:bulletin/core/widgets/max_width.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the measured height is the height it lays out at', (tester) async {
    const text = 'You will confirm your email before your first question, every time.';
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 342,
            child: MaxWidth(
              maxWidth: 120,
              child: Text(text, style: TextStyle(fontSize: 14)),
            ),
          ),
        ),
      ),
    );
    final box = tester.renderObject<RenderBox>(find.byType(MaxWidth));
    expect(tester.getSize(find.byType(Text)).width, lessThanOrEqualTo(120));
    expect(box.getMaxIntrinsicHeight(342), box.size.height);
  });
}
