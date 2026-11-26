/// The small print under an auth form: "By signing in, you agree to our
/// **Terms of Use**." The emphasised part is styled as in the prototype but
/// is not a link: there is no terms page to open yet, and a link that goes
/// nowhere is worse than none (TASKS.md).
library;

import 'package:flutter/widgets.dart';

import '../../../../core/theme/theme.dart';

class LegalLine extends StatelessWidget {
  const LegalLine({
    required this.prefix,
    required this.emphasis,
    required this.suffix,
    super.key,
  });

  final String prefix;
  final String emphasis;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final base = BulletinText.resolve(BulletinText.legal, prefix + emphasis + suffix);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: emphasis,
            style: const TextStyle(
              color: BulletinColors.ink,
              fontWeight: FontWeight.w600,
              fontVariations: Weights.semiBold,
            ),
          ),
          TextSpan(text: suffix),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
