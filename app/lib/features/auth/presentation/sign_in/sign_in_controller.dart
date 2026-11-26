/// Sign-in form state (CLAUDE.md: Riverpod for all state). The text itself
/// lives in the screen's text controllers; this holds what the form has
/// learned about it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_repository.dart';
import '../../domain/auth_result.dart';
import '../../domain/credentials.dart';

@immutable
class SignInState {
  const SignInState({
    this.busy = false,
    this.emailInvalid = false,
    this.failure,
    this.failureMessage,
    this.attempts = 0,
    this.obscurePassword = true,
    this.resetSentTo,
    this.resetNeedsEmail = false,
  });

  final bool busy;

  /// Caught before any request: the address is not shaped like one.
  final bool emailInvalid;

  final AuthError? failure;
  final String? failureMessage;

  /// Failed attempts so far. The password field shakes when this changes,
  /// so a second wrong password shakes again.
  final int attempts;

  final bool obscurePassword;

  /// Set once a reset link has been requested for this address.
  final String? resetSentTo;

  /// "Reset password" was tapped with no usable email in the field.
  final bool resetNeedsEmail;

  /// Wrong credentials are shown on the password field; every other failure
  /// goes in the error box.
  bool get wrongPassword => failure == AuthError.invalidCredentials;
}

class SignInController extends AutoDisposeNotifier<SignInState> {
  @override
  SignInState build() => const SignInState();

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  Future<void> submit({required String email, required String password}) async {
    if (state.busy) return;
    final s = state;

    if (!looksLikeEmail(email)) {
      state = SignInState(
        emailInvalid: true,
        attempts: s.attempts,
        obscurePassword: s.obscurePassword,
      );
      return;
    }

    state = SignInState(
      busy: true,
      attempts: s.attempts,
      obscurePassword: s.obscurePassword,
    );
    final result = await _auth.signIn(email: email, password: password);

    // On success the session appears and the router replaces this screen;
    // there is nothing to navigate to by hand.
    state = switch (result) {
      AuthOk() => SignInState(
        attempts: s.attempts,
        obscurePassword: state.obscurePassword,
      ),
      AuthFailed(:final error, :final message) => SignInState(
        failure: error,
        failureMessage: message,
        attempts: s.attempts + 1,
        obscurePassword: state.obscurePassword,
      ),
    };
  }

  Future<void> requestPasswordReset(String email) async {
    if (state.busy) return;
    final s = state;

    if (!looksLikeEmail(email)) {
      state = SignInState(
        resetNeedsEmail: true,
        attempts: s.attempts,
        obscurePassword: s.obscurePassword,
      );
      return;
    }

    state = SignInState(
      busy: true,
      attempts: s.attempts,
      obscurePassword: s.obscurePassword,
    );
    final result = await _auth.sendPasswordReset(email);
    state = switch (result) {
      AuthOk() => SignInState(
        resetSentTo: email.trim(),
        attempts: s.attempts,
        obscurePassword: state.obscurePassword,
      ),
      AuthFailed(:final error, :final message) => SignInState(
        failure: error,
        failureMessage: message,
        attempts: s.attempts,
        obscurePassword: state.obscurePassword,
      ),
    };
  }

  void togglePasswordVisibility() {
    final s = state;
    state = SignInState(
      busy: s.busy,
      emailInvalid: s.emailInvalid,
      failure: s.failure,
      failureMessage: s.failureMessage,
      attempts: s.attempts,
      obscurePassword: !s.obscurePassword,
      resetSentTo: s.resetSentTo,
      resetNeedsEmail: s.resetNeedsEmail,
    );
  }
}

final signInControllerProvider =
    NotifierProvider.autoDispose<SignInController, SignInState>(SignInController.new);
