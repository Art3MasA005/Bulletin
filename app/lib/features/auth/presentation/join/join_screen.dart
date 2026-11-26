/// Join institution (handoff CHANGES.md "Join institution"; prototype
/// `ab.join`). PRD §4.
///
/// The router's middle state: signed in, not yet a member. Clean canvas, no
/// clouds or panda. A white back button and "Sign out" (both sign out: there
/// is nowhere else to go back to), the institution tile, title and subtitle,
/// then one white card holding the invite code (mono, upper case, so O and 0
/// are told apart), a divider and the optional display name. "Join
/// institution" sits at the bottom.
///
/// Motion: the title block rises 450 ms after 80, the card 520 ms after 40,
/// as on Sign in.
///
/// One deviation: the prototype greys the button out while offline. The app
/// has no connectivity watcher, so it learns it is offline from a failed
/// attempt; the notice appears then and the button stays live for a retry.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/join.dart';
import '../widgets/auth_field.dart';
import '../widgets/field_group.dart';
import 'join_controller.dart';

class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    ref
        .read(joinControllerProvider.notifier)
        .submit(code: _code.text, displayName: _name.text);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final state = ref.watch(joinControllerProvider);
    final controller = ref.read(joinControllerProvider.notifier);
    final insets = MediaQuery.viewPaddingOf(context);

    return Scaffold(
      // Clean canvas: no ambient glow behind this one (CHANGES.md).
      backgroundColor: BulletinColors.canvas,
      body: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              // 56 / 20 / 32 in the prototype's frame, kept clear of the
              // real status and navigation bars.
              padding: EdgeInsets.fromLTRB(
                20,
                math.max(56, insets.top + 8),
                20,
                math.max(32, insets.bottom + 16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopRow(onSignOut: controller.signOut),
                  const SizedBox(height: 28),
                  FadeUp(
                    offset: 14,
                    duration: const Duration(milliseconds: 450),
                    delay: const Duration(milliseconds: 80),
                    child: _Heading(title: l.joinTitle, subtitle: l.joinSubtitle),
                  ),
                  if (state.failure == JoinError.offline) ...[
                    const SizedBox(height: Space.lg),
                    NoticeBox.info(l.joinOffline, LineIcons.wifiOff),
                  ],
                  const SizedBox(height: Space.lg),
                  FadeUp(
                    offset: 14,
                    duration: const Duration(milliseconds: 520),
                    delay: const Duration(milliseconds: 40),
                    child: _Card(
                      code: _code,
                      name: _name,
                      state: state,
                      onCodeEdited: controller.codeEdited,
                      onSubmit: _submit,
                    ),
                  ),
                  if (state.failure case JoinError.alreadyMember || JoinError.other) ...[
                    const SizedBox(height: Space.md),
                    NoticeBox.error(_failureText(l, state)),
                  ],
                  // At least 20 above the button; all the slack when there is
                  // room, so the button sits at the bottom.
                  const Spacer(),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: l.joinAction,
                    busy: state.busy,
                    busyLabel: l.joinBusy,
                    trailing: LineIcons.arrowRight,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _failureText(L l, JoinState state) => switch (state.failure) {
    // The server names the institution and role; nothing else can.
    JoinError.alreadyMember => state.failureMessage ?? l.errorGeneric,
    _ => l.errorGeneric,
  };
}

class _TopRow extends StatelessWidget {
  const _TopRow({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        BackSquareButton(onPressed: onSignOut, semanticLabel: l.backLabel, size: 44),
        TextLink(
          label: l.signOutAction,
          onPressed: onSignOut,
          style: BulletinText.footer.copyWith(
            color: BulletinColors.muted,
            fontWeight: FontWeight.w600,
            fontVariations: Weights.semiBold,
          ),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.lg,
        children: [
          // The institution tile: 52, radius 16, peach, the building in brand.
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: BulletinColors.peach,
              borderRadius: BrandRadii.field,
            ),
            alignment: Alignment.center,
            child: LineIcon(
              LineIcons.building,
              color: BulletinColors.brandStrong,
              size: 24,
              strokeWidth: 1.8,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: BulletinText.resolve(BulletinText.canvasTitle, title),
                ),
              ),
              Text(
                subtitle,
                style: BulletinText.resolve(BulletinText.canvasSubtitle, subtitle),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The one white card: invite code, a rule, display name.
class _Card extends StatelessWidget {
  const _Card({
    required this.code,
    required this.name,
    required this.state,
    required this.onCodeEdited,
    required this.onSubmit,
  });

  final TextEditingController code;
  final TextEditingController name;
  final JoinState state;
  final VoidCallback onCodeEdited;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: BulletinColors.white,
        borderRadius: BrandRadii.cardLarge,
        boxShadow: BrandLifts.canvasCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 22,
        children: [
          FieldGroup(
            strong: true,
            label: l.inviteCodeLabel,
            field: AuthField(
              controller: code,
              semanticLabel: l.inviteCodeLabel,
              look: AuthFieldLook.code,
              hint: l.joinCodeHint,
              error: state.codeRejected,
              textCapitalization: TextCapitalization.characters,
              keyboardType: TextInputType.visiblePassword, // no autocorrect bar
              textInputAction: TextInputAction.next,
              onChanged: (_) => onCodeEdited(),
            ),
            below: state.codeRejected
                ? FieldError(l.joinCodeNotFound, compact: true)
                : FieldHelper(l.joinCodeHelper, glyph: LineIcons.info),
          ),
          const ColoredBox(color: BulletinColors.dividerCard, child: SizedBox(height: 1)),
          FieldGroup(
            strong: true,
            label: l.displayNameLabel,
            note: l.joinOptional,
            field: AuthField(
              controller: name,
              semanticLabel: l.displayNameLabel,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.nickname],
              onSubmitted: (_) => onSubmit(),
            ),
            below: FieldHelper(l.joinDisplayNameHelper),
          ),
        ],
      ),
    );
  }
}
