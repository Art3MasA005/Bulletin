/// Which auth step is on screen, and which way the last move went.
///
/// One controller for the flow, so "back" is a state change rather than a
/// Navigator pop: the steps share one surface and animate through
/// [StepSwitcher] (MOTION.md §3.2), not as pushed routes.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion_widgets.dart';

/// In flow order: moving to a later step is "forward".
enum AuthStep { welcome, signIn, createAccount, checkEmail }

@immutable
class AuthFlowState {
  const AuthFlowState({
    this.step = AuthStep.welcome,
    this.direction = NavDirection.forward,
    this.pendingEmail,
  });

  final AuthStep step;
  final NavDirection direction;

  /// The address a confirmation link was sent to, for the check-email step.
  final String? pendingEmail;
}

class AuthFlowController extends AutoDisposeNotifier<AuthFlowState> {
  @override
  AuthFlowState build() => const AuthFlowState();

  void goTo(AuthStep step, {String? pendingEmail}) {
    if (step == state.step) return;
    state = AuthFlowState(
      step: step,
      direction: step.index > state.step.index ? NavDirection.forward : NavDirection.back,
      pendingEmail: pendingEmail ?? state.pendingEmail,
    );
  }

  /// System back, from the current step. False at the first step, so the
  /// back gesture falls through and leaves the app (MOTION.md §3.9).
  bool back() {
    switch (state.step) {
      case AuthStep.welcome:
        return false;
      case AuthStep.signIn:
        goTo(AuthStep.welcome);
      case AuthStep.createAccount:
        goTo(AuthStep.signIn);
      case AuthStep.checkEmail:
        goTo(AuthStep.createAccount);
    }
    return true;
  }
}

final authFlowProvider = NotifierProvider.autoDispose<AuthFlowController, AuthFlowState>(
  AuthFlowController.new,
);
