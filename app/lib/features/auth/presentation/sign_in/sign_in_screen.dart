/// Sign in (handoff README §2.3, CHANGES.md; prototype `ab.signin`).
///
/// The shared orange header and white sheet ([AuthSheetScaffold]) holding
/// email and password, the primary action, the invite-code action, the
/// create-account link and the terms line. Errors slide down 8 px in 220 ms;
/// a wrong password shakes the field.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../../../l10n/app_localizations.dart';
import '../auth_flow_controller.dart';
import '../auth_messages.dart';
import '../widgets/auth_field.dart';
import '../widgets/auth_sheet_scaffold.dart';
import '../widgets/legal_line.dart';
import 'sign_in_controller.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({this.onBack, super.key});

  /// Back to Welcome. Null hides the back button.
  final VoidCallback? onBack;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  // Debug builds start with the test account filled in (AppConfig.devAccount);
  // release builds start empty.
  final _email = TextEditingController(text: AppConfig.devAccount?.email);
  final _password = TextEditingController(text: AppConfig.devAccount?.password);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    ref
        .read(signInControllerProvider.notifier)
        .submit(email: _email.text, password: _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final state = ref.watch(signInControllerProvider);
    final controller = ref.read(signInControllerProvider.notifier);
    final flow = ref.read(authFlowProvider.notifier);

    final otherFailure = state.failure != null && !state.wrongPassword
        ? authErrorText(l, state.failure!, serverMessage: state.failureMessage)
        : null;

    return AuthSheetScaffold(
      onBack: widget.onBack,
      title: l.authSignInTitle,
      subtitle: l.authSignInSubtitle,
      children: [
        _EmailGroup(controller: _email, invalid: state.emailInvalid),
        _PasswordGroup(
          controller: _password,
          state: state,
          onSubmit: _submit,
          onToggle: controller.togglePasswordVisibility,
          onReset: () => controller.requestPasswordReset(_email.text),
        ),
        if (state.wrongPassword) NoticeBox.error(l.authWrongPassword),
        if (otherFailure != null) NoticeBox.error(otherFailure),
        if (state.resetSentTo case final sentTo?)
          NoticeBox.success(l.authResetSent(sentTo)),
        if (state.resetNeedsEmail) NoticeBox.error(l.authResetNeedsEmail),
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: PrimaryButton(
            label: l.authSignInAction,
            busyLabel: l.authSigningIn,
            busy: state.busy,
            trailing: LineIcons.arrowRight,
            onPressed: _submit,
          ),
        ),
        _OrDivider(label: l.authOr),
        // Joining needs an account first (the backend's join endpoint takes
        // a signed-in user), so the invite path starts at create account;
        // after it the router lands on the join step by itself.
        SecondaryButton(
          label: l.authJoinWithInvite,
          leading: LineIcons.building,
          onPressed: () => flow.goTo(AuthStep.createAccount),
        ),
        const Spacer(),
        AuthSwitchLine(
          question: l.authNewHere,
          action: l.authCreateAccountLink,
          onTap: () => flow.goTo(AuthStep.createAccount),
        ),
        LegalLine(
          prefix: l.authTermsPrefix,
          emphasis: l.authTermsLink,
          suffix: l.authTermsSuffix,
        ),
      ],
    );
  }
}

class _EmailGroup extends StatelessWidget {
  const _EmailGroup({required this.controller, required this.invalid});

  final TextEditingController controller;
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        _Label(l.authEmailLabel),
        AuthField(
          controller: controller,
          semanticLabel: l.authEmailLabel,
          leading: LineIcons.mail,
          hint: l.authEmailHint,
          error: invalid,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
        ),
        if (invalid) FieldError(l.authEmailInvalid),
      ],
    );
  }
}

class _PasswordGroup extends StatelessWidget {
  const _PasswordGroup({
    required this.controller,
    required this.state,
    required this.onSubmit,
    required this.onToggle,
    required this.onReset,
  });

  final TextEditingController controller;
  final SignInState state;
  final VoidCallback onSubmit;
  final VoidCallback onToggle;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        Row(
          spacing: Space.md,
          children: [
            Expanded(child: _Label(l.authPasswordLabel)),
            // A 48 px tap target, no exceptions (DESIGN §3): the label row is
            // taller than the prototype's 18 px rather than the link smaller.
            Flexible(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextLink(label: l.authResetPassword, onPressed: onReset),
              ),
            ),
          ],
        ),
        Shake(
          trigger: state.wrongPassword ? state.attempts : null,
          child: AuthField(
            controller: controller,
            semanticLabel: l.authPasswordLabel,
            leading: LineIcons.lock,
            error: state.wrongPassword,
            obscure: state.obscurePassword,
            onToggleObscure: onToggle,
            toggleLabel: state.obscurePassword ? l.showPassword : l.hidePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        if (!state.wrongPassword)
          Text(
            l.authPasswordHelper,
            style: BulletinText.resolve(BulletinText.fieldHelper, l.authPasswordHelper),
          ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Text(text, style: BulletinText.resolve(BulletinText.fieldLabel, text)),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: Space.md,
      children: [
        const Expanded(child: Divider(color: BulletinColors.divider, height: 1)),
        Text(
          label,
          style: BulletinText.resolve(
            BulletinText.fieldHelper.copyWith(height: 1.4),
            label,
          ),
        ),
        const Expanded(child: Divider(color: BulletinColors.divider, height: 1)),
      ],
    );
  }
}
