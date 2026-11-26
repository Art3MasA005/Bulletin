/// The user's bubble (CHANGES.md): `#FFE3D0`, dark text, radius 22 22 8 22,
/// 15 / 1.55, at most 288 px wide, on the right.
///
/// When the phone was offline the question never left: the bubble dims to
/// 70 %, and a line under it says "Not sent. You're offline." with a Retry
/// button (min 48 px tall) that slides down into place.
library;

import 'package:flutter/material.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/message.dart';

class UserBubble extends StatelessWidget {
  const UserBubble({required this.message, this.onRetry, super.key});

  final ChatMessage message;
  final VoidCallback? onRetry;

  static const _radius = BorderRadius.only(
    topLeft: Radius.circular(22),
    topRight: Radius.circular(22),
    bottomLeft: Radius.circular(22),
    bottomRight: Radius.circular(8),
  );

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Sizes.userBubbleMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: Space.xs,
          children: [
            Opacity(
              opacity: message.notSent ? 0.7 : 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: const BoxDecoration(
                  color: BulletinColors.userBubble,
                  borderRadius: _radius,
                ),
                child: Text(
                  message.text,
                  style: BulletinText.resolve(BulletinText.userBubbleText, message.text),
                ),
              ),
            ),
            if (message.notSent) _NotSent(onRetry: onRetry),
          ],
        ),
      ),
    );
  }
}

class _NotSent extends StatelessWidget {
  const _NotSent({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final line = BulletinText.resolve(BulletinText.meta, l.notSentOffline).copyWith(
      color: BulletinColors.error,
    );

    // A Wrap, not a Row: at 200 % in Bangla the sentence and the button do not
    // fit on one line, and the button drops under it instead of overflowing.
    return FadeUp(
      offset: -8,
      duration: MotionDurations.toggle,
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              LineIcon(
                LineIcons.alert,
                color: BulletinColors.error,
                size: 16,
                strokeWidth: 2,
              ),
              Flexible(child: Text(l.notSentOffline, style: line)),
            ],
          ),
          Semantics(
            button: true,
            label: l.retryMessage,
            excludeSemantics: true,
            child: InkWell(
              onTap: onRetry,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Sizes.minTouchTarget),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                      LineIcon(
                        LineIcons.retry,
                        color: BulletinColors.brandStrong,
                        size: 16,
                        strokeWidth: 2,
                      ),
                      Flexible(
                        child: Text(
                          l.retryMessage,
                          style: BulletinText.resolve(
                            BulletinText.pillAction,
                            l.retryMessage,
                          ).copyWith(color: BulletinColors.brandStrong),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
