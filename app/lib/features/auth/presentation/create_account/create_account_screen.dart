/// Create account (handoff CHANGES.md "Sign up"; prototype `ab.create`):
/// Sign in's layout — orange header with drifting clouds, glass back button
/// to Sign in, white sheet with the panda peeking over it — holding full
/// name, email and a password of at least 8 characters, whose error states
/// the current count. On a project that requires email confirmation (ours),
/// a successful sign-up moves to the check-email step.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../../../l10n/app_localizations.dart';
import '../auth_flow_controller.dart';
import '../auth_messages.dart';
import '../widgets/auth_field.dart';
import '../widgets/auth_sheet_scaffold.dart';
import '../widgets/field_group.dart';
import '../widgets/legal_line.dart';
import 'create_account_controller.dart';

class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    ref
        .read(createAccountControllerProvider.notifier)
        .submit(name: _name.text, email: _email.text, password: _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final state = ref.watch(createAccountControllerProvider);
    final controller = ref.read(createAccountControllerProvider.notifier);
    void toSignIn() => ref.read(authFlowProvider.notifier).goTo(AuthStep.signIn);

    return AuthSheetScaffold(
      onBack: toSignIn,
      title: l.createTitle,
      subtitle: l.createSubtitle,
      children: [
        FieldGroup(
          strong: true,
          label: l.createNameLabel,
          field: AuthField(
            controller: _name,
            semanticLabel: l.createNameLabel,
            leading: LineIcons.person,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
          ),
        ),
        FieldGroup(
          strong: true,
          label: l.authEmailLabel,
          field: AuthField(
            controller: _email,
            semanticLabel: l.authEmailLabel,
            leading: LineIcons.mail,
            hint: l.authEmailHint,
            error: state.emailInvalid,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
          ),
          below: state.emailInvalid ? FieldError(l.authEmailInvalid) : null,
        ),
        FieldGroup(
          strong: true,
          label: l.authPasswordLabel,
          field: AuthField(
            controller: _password,
            semanticLabel: l.authPasswordLabel,
            leading: LineIcons.lock,
            error: state.shortPasswordLength != null,
            obscure: state.obscurePassword,
            onToggleObscure: controller.togglePasswordVisibility,
            toggleLabel: state.obscurePassword ? l.showPassword : l.hidePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) => _submit(),
          ),
          below: switch (state.shortPasswordLength) {
            final count? => FieldError(l.createPasswordShort(count)),
            null => FieldHelper(l.authPasswordHelper),
          },
        ),
        if (state.failure case final failure?)
          NoticeBox.error(authErrorText(l, failure, serverMessage: state.failureMessage)),
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: PrimaryButton(
            label: l.createAction,
            busy: state.busy,
            trailing: LineIcons.arrowRight,
            onPressed: _submit,
          ),
        ),
        const Spacer(),
        AuthSwitchLine(
          question: l.createHaveAccount,
          action: l.createSignInLink,
          onTap: toSignIn,
        ),
        LegalLine(
          prefix: l.privacyPrefix,
          emphasis: l.privacyLink,
          suffix: l.privacySuffix,
        ),
      ],
    );
  }
}
