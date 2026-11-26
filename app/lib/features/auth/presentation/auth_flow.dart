/// The signed-out half of the app: welcome, sign in, create account, check
/// email.
///
/// Steps change inside one screen through [StepSwitcher] (MOTION.md §3.2):
/// the old step lifts and fades out in 150 ms, the new one rises in 250 ms
/// after 90. System back walks the steps backwards, then leaves the app.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion_widgets.dart';
import 'auth_flow_controller.dart';
import 'check_email/check_email_screen.dart';
import 'create_account/create_account_screen.dart';
import 'sign_in/sign_in_screen.dart';
import 'welcome/welcome_screen.dart';

class AuthFlow extends ConsumerWidget {
  const AuthFlow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(authFlowProvider);
    final steps = ref.read(authFlowProvider.notifier);

    return PopScope(
      canPop: flow.step == AuthStep.welcome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) steps.back();
      },
      child: StepSwitcher(
        direction: flow.direction,
        child: switch (flow.step) {
          AuthStep.welcome => WelcomeScreen(
            key: const ValueKey(AuthStep.welcome),
            onLogIn: () => steps.goTo(AuthStep.signIn),
          ),
          AuthStep.signIn => SignInScreen(
            key: const ValueKey(AuthStep.signIn),
            onBack: () => steps.goTo(AuthStep.welcome),
          ),
          AuthStep.createAccount => const CreateAccountScreen(
            key: ValueKey(AuthStep.createAccount),
          ),
          AuthStep.checkEmail => CheckEmailScreen(
            key: const ValueKey(AuthStep.checkEmail),
            email: flow.pendingEmail ?? '',
          ),
        },
      ),
    );
  }
}
