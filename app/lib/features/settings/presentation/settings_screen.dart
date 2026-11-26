/// Settings (handoff README §2.11; prototype `L.settings`).
///
/// Canvas, a 48 px white back square at y = 56, "Settings" 24/600, then
/// four groups fading up in turn (80, 120, 160, 200 ms): the interface
/// language, the profile (display name, email), the institution card, and
/// for an admin the Documents row. Sign out sits at the bottom.
///
/// The language switch changes the app at once and is remembered. The
/// display name saves when the field is submitted or loses focus, through
/// [DisplayNameController]; Home greets by it right after.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/motion/motion_widgets.dart';
import '../../../core/net/api_client.dart' show Membership;
import '../../../core/providers.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/line_icons.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import 'settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({this.onOpenDocuments, super.key});

  /// Opens Documents; the row shows only to an admin, and only when given.
  final VoidCallback? onOpenDocuments;

  static const _delays = [80, 120, 160, 200];

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    // Leave Settings first: signing out swaps the screen beneath it.
    Navigator.of(context).popUntil((route) => route.isFirst);
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final membership = ref.watch(membershipProvider).valueOrNull;
    final insets = MediaQuery.viewPaddingOf(context);
    final title = l.settingsTitle;

    Widget group(int i, Widget child) => FadeUp(
      delay: Duration(milliseconds: _delays[i]),
      child: child,
    );

    final showDocuments = (membership?.isAdmin ?? false) && onOpenDocuments != null;

    return Scaffold(
      backgroundColor: BulletinColors.canvas,
      body: Padding(
        padding: EdgeInsets.only(top: math.max(56, insets.top + 8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: BackSquareButton(
                semanticLabel: l.backLabel,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: BulletinText.resolve(BulletinText.screenTitle, title),
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    20,
                    24,
                    math.max(36, insets.bottom + 16),
                  ),
                  child: ConstrainedBox(
                    // Sign out sits at the bottom when everything fits.
                    constraints: BoxConstraints(
                      minHeight: math.max(
                        0,
                        box.maxHeight - 20 - math.max(36, insets.bottom + 16),
                      ),
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 24,
                        children: [
                          group(0, const _Language()),
                          group(1, _Profile(membership: membership)),
                          if (membership != null)
                            group(2, _Institution(membership: membership)),
                          if (showDocuments)
                            group(3, _DocumentsRow(onTap: onOpenDocuments!)),
                          const Spacer(),
                          _SignOutButton(
                            onPressed: () => unawaited(_signOut(context, ref)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Overline extends StatelessWidget {
  const _Overline(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text.toUpperCase(),
      style: BulletinText.resolve(BulletinText.sectionLabel, text),
    ),
  );
}

// ── language ─────────────────────────────────────────────────────────────────

class _Language extends ConsumerWidget {
  const _Language();

  static const _track = BorderRadius.all(Radius.circular(16));
  static const _thumb = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final current = Localizations.localeOf(context).languageCode;
    final bangla = current == 'bn';
    final reduce = reduceMotionOf(context);

    Widget option(String code, String label) {
      final on = current == code;
      return Expanded(
        child: Semantics(
          inMutuallyExclusiveGroup: true,
          checked: on,
          button: true,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.read(localeProvider.notifier).set(Locale(code)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Sizes.minTouchTarget),
              child: Center(
                child: AnimatedDefaultTextStyle(
                  duration: MotionDurations.micro,
                  style: BulletinText.resolve(
                    BulletinText.segmentLabel,
                    label,
                  ).copyWith(color: on ? BulletinColors.ink : BulletinColors.muted),
                  child: Text(label),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        _Overline(l.interfaceLanguage),
        DecoratedBox(
          decoration: const BoxDecoration(
            color: BulletinColors.hairline,
            borderRadius: _track,
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedAlign(
                    duration: reduce ? Duration.zero : const Duration(milliseconds: 250),
                    curve: MotionCurves.out,
                    alignment: bangla ? Alignment.centerRight : Alignment.centerLeft,
                    child: const FractionallySizedBox(
                      widthFactor: 0.5,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: BulletinColors.white,
                          borderRadius: _thumb,
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    option('en', l.languageEnglish),
                    option('bn', l.languageBangla),
                  ],
                ),
              ],
            ),
          ),
        ),
        Text(
          l.answerLangNote,
          style: BulletinText.resolve(BulletinText.fieldHelper, l.answerLangNote),
        ),
      ],
    );
  }
}

// ── profile ──────────────────────────────────────────────────────────────────

class _Profile extends ConsumerStatefulWidget {
  const _Profile({required this.membership});

  final Membership? membership;

  @override
  ConsumerState<_Profile> createState() => _ProfileState();
}

class _ProfileState extends ConsumerState<_Profile> {
  late final _name = TextEditingController(text: widget.membership?.displayName ?? '');
  final _focus = FocusNode();

  static const _radius = BorderRadius.all(Radius.circular(12));

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save() => unawaited(
    ref
        .read(displayNameControllerProvider.notifier)
        .save(_name.text, current: widget.membership?.displayName),
  );

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final save = ref.watch(displayNameControllerProvider);
    final email = widget.membership?.email;

    ref.listen(displayNameControllerProvider, (_, next) {
      if (next == NameSave.failed) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.errorGeneric)));
      }
    });

    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: _radius,
      borderSide: BorderSide(color: color),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        _Overline(l.settingsProfile),
        Text(
          l.displayNameLabel,
          style: BulletinText.resolve(BulletinText.settingsLabel, l.displayNameLabel),
        ),
        TextField(
          controller: _name,
          focusNode: _focus,
          maxLength: 60,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => ref.read(displayNameControllerProvider.notifier).edited(),
          onSubmitted: (_) => _save(),
          style: BulletinText.resolve(BulletinText.fieldInput, _name.text),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: BulletinColors.white,
            constraints: const BoxConstraints(minHeight: 52),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            enabledBorder: border(BulletinColors.sendInert),
            focusedBorder: border(BulletinColors.brandStrong),
            suffixIcon: switch (save) {
              NameSave.saving => const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: BulletinColors.muted,
                  ),
                ),
              ),
              NameSave.saved => Semantics(
                label: l.displayNameSaved,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: LineIcon(
                    LineIcons.check,
                    color: BulletinColors.success,
                    strokeWidth: 2.2,
                  ),
                ),
              ),
              _ => null,
            },
          ),
        ),
        if (email != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              spacing: Space.md,
              children: [
                Text(
                  l.settingsEmail,
                  style: BulletinText.resolve(
                    BulletinText.settingsRow,
                    l.settingsEmail,
                  ).copyWith(color: BulletinColors.muted),
                ),
                Expanded(
                  child: Text(
                    email,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: BulletinText.settingsRow,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── institution ──────────────────────────────────────────────────────────────

String roleLabel(L l, String role) => switch (role) {
  'admin' => l.roleAdmin,
  'teacher' => l.roleTeacher,
  _ => l.roleStudent,
};

class _Institution extends StatelessWidget {
  const _Institution({required this.membership});

  final Membership membership;

  static const _card = BorderRadius.all(Radius.circular(20));
  static const _tile = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final name = membership.institutionName;
    final role = roleLabel(l, membership.role);
    final code = membership.inviteCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        _Overline(l.institutionLabel),
        DecoratedBox(
          decoration: const BoxDecoration(
            color: BulletinColors.white,
            borderRadius: _card,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                _IconTile(glyph: LineIcons.building, radius: _tile),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      if (name != null)
                        Text(
                          name,
                          style: BulletinText.resolve(
                            BulletinText.settingsCardTitle,
                            name,
                          ),
                        ),
                      Text(
                        role,
                        style: BulletinText.resolve(
                          BulletinText.settingsRow,
                          role,
                        ).copyWith(color: BulletinColors.muted),
                      ),
                      if (code != null)
                        Wrap(
                          spacing: 6,
                          children: [
                            Text(
                              l.joinedWithCode,
                              style: BulletinText.resolve(
                                BulletinText.pillCaption,
                                l.joinedWithCode,
                              ),
                            ),
                            Text(code, style: BulletinText.settingsCode),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.glyph, required this.radius});

  final LineGlyph glyph;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(color: BulletinColors.peach, borderRadius: radius),
    alignment: Alignment.center,
    child: LineIcon(glyph, color: BulletinColors.brandStrong),
  );
}

class _DocumentsRow extends StatelessWidget {
  const _DocumentsRow({required this.onTap});

  final VoidCallback onTap;

  static const _card = BorderRadius.all(Radius.circular(20));
  static const _tile = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Semantics(
      button: true,
      label: '${l.documentsTitle}, ${l.documentsRowSub}',
      excludeSemantics: true,
      child: PressScale(
        scale: 0.98,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: BulletinColors.white,
              borderRadius: _card,
            ),
            child: Row(
              spacing: Space.md,
              children: [
                _IconTile(glyph: LineIcons.document, radius: _tile),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.documentsTitle,
                        style: BulletinText.resolve(
                          BulletinText.settingsCardTitle,
                          l.documentsTitle,
                        ),
                      ),
                      Text(
                        l.documentsRowSub,
                        style: BulletinText.resolve(
                          BulletinText.pillCaption,
                          l.documentsRowSub,
                        ),
                      ),
                    ],
                  ),
                ),
                LineIcon(
                  LineIcons.chevronRight,
                  color: BulletinColors.muted,
                  size: 18,
                  strokeWidth: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.onPressed});

  final VoidCallback onPressed;

  static const _radius = BorderRadius.all(Radius.circular(18));

  @override
  Widget build(BuildContext context) {
    final label = L.of(context).signOutAction;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        scale: 0.98,
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BulletinColors.white,
              borderRadius: _radius,
              border: Border.all(color: BulletinColors.sendInert),
            ),
            child: Text(
              label,
              style: BulletinText.resolve(
                BulletinText.buttonLabel,
                label,
              ).copyWith(color: BulletinColors.error),
            ),
          ),
        ),
      ),
    );
  }
}
