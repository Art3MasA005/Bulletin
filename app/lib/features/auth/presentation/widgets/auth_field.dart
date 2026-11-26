/// The text field used across the auth steps (handoff README §2.3).
///
/// Two looks, both in the handoff:
///
/// * [AuthFieldLook.filled] — sign-in: 54 px, radius 16, warm `field` fill,
///   a 20 px leading icon. Focus turns it white with a `brandStrong` border
///   and a 4 px `peach` ring.
/// * [AuthFieldLook.plain] — create account: 52 px, radius 14, white, no
///   icon. Focus adds a 3 px `peach` ring.
/// * [AuthFieldLook.code] — the invite code (CHANGES.md, Join): [filled] at
///   60 px with no icon, mono 20 with 3 px tracking and an 18 px inset,
///   upper case as typed.
///
/// An error replaces the border with 1.5 px `error` in both. Focus and error
/// changes animate in 150 ms (MOTION.md `micro`).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/line_icons.dart';

enum AuthFieldLook { filled, plain, code }

class AuthField extends StatefulWidget {
  const AuthField({
    required this.controller,
    required this.semanticLabel,
    this.look = AuthFieldLook.filled,
    this.leading,
    this.hint,
    this.error = false,
    this.obscure = false,
    this.onToggleObscure,
    this.toggleLabel,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.onChanged,
    this.textCapitalization = TextCapitalization.none,
    super.key,
  });

  final TextEditingController controller;

  /// Read by screen readers; the visible label sits above the field.
  final String semanticLabel;
  final AuthFieldLook look;
  final LineGlyph? leading;
  final String? hint;
  final bool error;

  /// A password field: [onToggleObscure] adds the show/hide eye button.
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final String? toggleLabel;

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The code field fills and focuses like the sign-in fields.
    final filled = widget.look != AuthFieldLook.plain;

    return ListenableBuilder(
      listenable: _focus,
      builder: (context, field) {
        final focused = _focus.hasFocus;
        final Color border;
        if (widget.error) {
          border = BulletinColors.error;
        } else if (focused && filled) {
          border = BulletinColors.brandStrong;
        } else {
          // White on white: invisible, but it keeps the box the same size
          // when the error or focus border appears.
          border = BulletinColors.white;
        }

        return AnimatedContainer(
          duration: MotionDurations.micro,
          curve: MotionCurves.out,
          constraints: BoxConstraints(
            minHeight: switch (widget.look) {
              AuthFieldLook.filled => 54,
              AuthFieldLook.plain => 52,
              AuthFieldLook.code => 60,
            },
          ),
          decoration: BoxDecoration(
            color: filled && !focused ? BulletinColors.field : BulletinColors.white,
            borderRadius: filled ? BrandRadii.field : BrandRadii.fieldCompact,
            border: Border.all(color: border, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: focused
                    ? BulletinColors.peach
                    : BulletinColors.peach.withValues(alpha: 0),
                spreadRadius: filled ? 4 : 3,
              ),
            ],
          ),
          child: field,
        );
      },
      child: Row(
        children: [
          if (widget.leading case final glyph?)
            Padding(
              padding: const EdgeInsets.only(left: 16 - 1.5, right: 12),
              child: LineIcon(glyph, color: BulletinColors.mutedIcon),
            )
          else
            SizedBox(width: (widget.look == AuthFieldLook.code ? 18 : 16) - 1.5),
          Expanded(
            child: Semantics(label: widget.semanticLabel, child: _input()),
          ),
          if (widget.onToggleObscure != null)
            Semantics(
              button: true,
              label: widget.toggleLabel,
              excludeSemantics: true,
              child: PressScale.icon(
                child: IconButtonShell(
                  onTap: widget.onToggleObscure!,
                  child: LineIcon(
                    widget.obscure ? LineIcons.eye : LineIcons.eyeOff,
                    color: BulletinColors.muted,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 16 - 1.5),
        ],
      ),
    );
  }

  Widget _input() {
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      obscureText: widget.obscure,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      textCapitalization: widget.textCapitalization,
      autocorrect: false,
      enableSuggestions: !widget.obscure,
      inputFormatters: switch (widget.look) {
        AuthFieldLook.code => const [_UpperCase()],
        _ when widget.keyboardType == TextInputType.emailAddress => [
          FilteringTextInputFormatter.deny(RegExp(r'\s')),
        ],
        _ => null,
      },
      style: _style,
      cursorColor: BulletinColors.brandStrong,
      decoration: InputDecoration(
        semanticCounterText: '',
        // The box above draws the border, fill and ring; the field itself is
        // bare so the two never fight.
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isCollapsed: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        hintText: widget.hint,
        hintStyle: _style.copyWith(color: BulletinColors.muted),
      ),
    );
  }

  TextStyle get _style => widget.look == AuthFieldLook.code
      ? BulletinText.inviteCode
      : BulletinText.fieldInput;
}

/// Upper-cases as the person types, as the prototype's code field does.
class _UpperCase extends TextInputFormatter {
  const _UpperCase();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

/// A 48 px tap target for an icon inside a field.
class IconButtonShell extends StatelessWidget {
  const IconButtonShell({required this.onTap, required this.child, super.key});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: SizedBox.square(
          dimension: Sizes.minTouchTarget,
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// The error line under a field: alert icon + red text, sliding down 8 px
/// over 220 ms `out` as it appears (handoff README §5, "Field error").
class FieldError extends StatelessWidget {
  const FieldError(this.message, {this.compact = false, super.key});

  final String message;

  /// 16 px icon and 13 px text, inside the Join card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FadeUp(
      offset: -8,
      duration: const Duration(milliseconds: 220),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.sm,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: LineIcon(
                LineIcons.alert,
                color: BulletinColors.error,
                size: compact ? 16 : 18,
                strokeWidth: 2,
              ),
            ),
            Expanded(
              child: Text(
                message,
                style: BulletinText.resolve(
                  compact
                      ? BulletinText.fieldError.copyWith(fontSize: 13)
                      : BulletinText.fieldError,
                  message,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Notice { error, success, info }

/// A boxed message: error (`errorSurface`), success, or info (a white card
/// with an ink icon, like the Join screen's offline notice).
class NoticeBox extends StatelessWidget {
  const NoticeBox.error(this.message, {super.key}) : _kind = _Notice.error, _glyph = null;

  const NoticeBox.success(this.message, {super.key})
    : _kind = _Notice.success,
      _glyph = null;

  const NoticeBox.info(this.message, this._glyph, {super.key}) : _kind = _Notice.info;

  final String message;
  final _Notice _kind;
  final LineGlyph? _glyph;

  @override
  Widget build(BuildContext context) {
    final (glyph, iconColor, surface, stroke) = switch (_kind) {
      _Notice.error => (
        LineIcons.alert,
        BulletinColors.error,
        BulletinColors.errorSurface,
        2.0,
      ),
      _Notice.success => (
        LineIcons.check,
        BulletinColors.success,
        BulletinColors.successTint,
        2.0,
      ),
      _Notice.info => (_glyph!, BulletinColors.ink, BulletinColors.white, 1.75),
    };
    return FadeUp(
      offset: -8,
      duration: const Duration(milliseconds: 220),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Space.md),
          decoration: BoxDecoration(color: surface, borderRadius: BrandRadii.notice),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: LineIcon(glyph, color: iconColor, strokeWidth: stroke),
              ),
              Expanded(
                child: Text(
                  message,
                  style: BulletinText.resolve(BulletinText.noticeBody, message),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
