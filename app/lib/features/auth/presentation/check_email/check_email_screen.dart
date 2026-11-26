/// Check your email (handoff README §2.4; prototype `ab.check`): the account
/// exists, a confirmation link is on its way. Resend after a cooldown, or go
/// back and use a different address.
///
/// The prototype's "Open email app" button is left out: Android has no
/// standard intent for "the inbox", and a button that opens a compose window
/// instead would mislead (TASKS.md).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../../../l10n/app_localizations.dart';
import '../auth_flow_controller.dart';
import '../auth_messages.dart';
import '../widgets/auth_field.dart';
import '../widgets/auth_step_scaffold.dart';
import 'check_email_controller.dart';

class CheckEmailScreen extends ConsumerWidget {
  const CheckEmailScreen({required this.email, super.key});

  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final state = ref.watch(checkEmailControllerProvider);
    void toCreate() => ref.read(authFlowProvider.notifier).goTo(AuthStep.createAccount);

    return AuthStepScaffold(
      onBack: toCreate,
      title: l.checkTitle,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          _ResendButton(
            state: state,
            onPressed: () =>
                ref.read(checkEmailControllerProvider.notifier).resend(email),
          ),
          TextLink(
            label: l.checkDifferentEmail,
            onPressed: toCreate,
            style: BulletinText.footer.copyWith(
              color: BulletinColors.brandStrong,
              fontWeight: FontWeight.w600,
              fontVariations: Weights.semiBold,
            ),
          ),
        ],
      ),
      children: [
        _CreatedCard(email: email),
        if (state.failure case final failure?)
          NoticeBox.error(authErrorText(l, failure, serverMessage: state.failureMessage))
        else if (state.resent)
          NoticeBox.success(l.checkResent),
      ],
    );
  }
}

class _CreatedCard extends StatelessWidget {
  const _CreatedCard({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final body = l.checkBody(email);
    final at = body.indexOf(email);

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: BulletinColors.white,
          borderRadius: BrandRadii.card,
          boxShadow: BrandLifts.hairline,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.md,
          children: [
            PopIn(
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: BulletinColors.success,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: LineIcon(
                  LineIcons.check,
                  color: BulletinColors.white,
                  size: 24,
                  strokeWidth: 2.2,
                ),
              ),
            ),
            Text(
              l.checkHeading,
              style: BulletinText.resolve(BulletinText.cardHeading, l.checkHeading),
            ),
            // The address in bold, wherever the language puts it.
            Text.rich(
              TextSpan(
                style: BulletinText.resolve(BulletinText.cardBody, body),
                children: at < 0
                    ? [TextSpan(text: body)]
                    : [
                        TextSpan(text: body.substring(0, at)),
                        TextSpan(
                          text: email,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontVariations: Weights.semiBold,
                          ),
                        ),
                        TextSpan(text: body.substring(at + email.length)),
                      ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White, hairline-bordered. Inert with a mono countdown while cooling down.
class _ResendButton extends StatelessWidget {
  const _ResendButton({required this.state, required this.onPressed});

  final CheckEmailState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final enabled = state.canResend;
    final s = state.secondsLeft;
    final countdown = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    final label = BulletinText.resolve(
      BulletinText.buttonLabel.copyWith(
        color: enabled ? BulletinColors.ink : BulletinColors.muted,
        fontWeight: FontWeight.w500,
        fontVariations: Weights.medium,
      ),
      l.checkResend,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: enabled ? l.checkResend : '${l.checkResend} $countdown',
      excludeSemantics: true,
      child: PressScale.button(
        enabled: enabled,
        child: Material(
          color: BulletinColors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BrandRadii.buttonCompact,
            side: BorderSide(color: BulletinColors.inertBorder),
          ),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BrandRadii.buttonCompact,
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 54),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: Space.sm,
                children: [
                  if (state.sending)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: BulletinColors.muted,
                      ),
                    ),
                  Text(l.checkResend, style: label),
                  if (!enabled && !state.sending)
                    Text(
                      countdown,
                      style: BulletinText.courseCode.copyWith(
                        color: BulletinColors.muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
