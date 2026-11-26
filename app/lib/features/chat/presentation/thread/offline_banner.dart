/// "You're offline. Answers need a connection." (CHANGES.md; prototype
/// `chat.offline`): a white card, radius 14, under the top bar, that slides
/// down 8 px as it fades in.
library;

import 'package:flutter/material.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../../../l10n/app_localizations.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final text = L.of(context).offlineBanner;
    return Semantics(
      liveRegion: true,
      child: FadeUp(
        offset: -8,
        duration: MotionDurations.stepIn,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: BulletinColors.white,
            borderRadius: BrandRadii.notice,
            boxShadow: BrandLifts.banner,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: LineIcon(LineIcons.wifiOff, color: BulletinColors.ink, size: 20),
              ),
              Expanded(
                child: Text(text, style: BulletinText.resolve(BulletinText.bannerText, text)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
