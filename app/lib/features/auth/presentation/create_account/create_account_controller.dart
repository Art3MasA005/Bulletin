/// Create-account form state.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_repository.dart';
import '../../domain/auth_result.dart';
import '../../domain/credentials.dart';
import '../auth_flow_controller.dart';

@immutable
class CreateAccountState {
  const CreateAccountState({
    this.busy = false,
    this.emailInvalid = false,
    this.shortPasswordLength,
    this.failure,
    this.failureMessage,
    this.obscurePassword = true,
  });

  final bool busy;
  final bool emailInvalid;

  /// The length of a too-short password, so the error can state it
  /// ("This one has 5."). Null when the password is long enough.
  final int? shortPasswordLength;

  final AuthError? failure;
  final String? failureMessage;
  final bool obscurePassword;
}

class CreateAccountController extends AutoDisposeNotifier<CreateAccountState> {
  @override
  CreateAccountState build() => const CreateAccountState();

  Future<void> submit({
    required String name,
    required String email,
    required String password,
  }) async {
    if (state.busy) return;
    final obscure = state.obscurePassword;

    if (!looksLikeEmail(email)) {
      state = CreateAccountState(emailInvalid: true, obscurePassword: obscure);
      return;
    }
    if (password.length < minPasswordLength) {
      state = CreateAccountState(
        shortPasswordLength: password.length,
        obscurePassword: obscure,
      );
      return;
    }

    state = CreateAccountState(busy: true, obscurePassword: obscure);
    final result = await ref
        .read(authRepositoryProvider)
        .signUp(name: name, email: email, password: password);

    switch (result) {
      case AuthOk(value: SignUpOutcome.confirmationSent):
        state = CreateAccountState(obscurePassword: obscure);
        ref
            .read(authFlowProvider.notifier)
            .goTo(AuthStep.checkEmail, pendingEmail: email.trim());
      case AuthOk(value: SignUpOutcome.signedIn):
        // A session exists; the router takes it from here.
        state = CreateAccountState(obscurePassword: obscure);
      case AuthFailed(:final error, :final message):
        state = CreateAccountState(
          failure: error,
          failureMessage: message,
          obscurePassword: obscure,
        );
    }
  }

  void togglePasswordVisibility() {
    final s = state;
    state = CreateAccountState(
      busy: s.busy,
      emailInvalid: s.emailInvalid,
      shortPasswordLength: s.shortPasswordLength,
      failure: s.failure,
      failureMessage: s.failureMessage,
      obscurePassword: !s.obscurePassword,
    );
  }
}

final createAccountControllerProvider =
    NotifierProvider.autoDispose<CreateAccountController, CreateAccountState>(
      CreateAccountController.new,
    );
