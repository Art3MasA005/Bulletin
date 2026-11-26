/// The check-email step: a resend button with a cooldown.
///
/// The cooldown starts as soon as the step opens, because a link was sent a
/// moment ago, and Supabase rate-limits confirmation emails anyway: a
/// "Resend" enabled immediately would mostly produce rate-limit errors.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_repository.dart';
import '../../domain/auth_result.dart';

const resendCooldown = Duration(seconds: 60);

@immutable
class CheckEmailState {
  const CheckEmailState({
    required this.secondsLeft,
    this.sending = false,
    this.resent = false,
    this.failure,
    this.failureMessage,
  });

  final int secondsLeft;
  final bool sending;

  /// A resend succeeded at least once.
  final bool resent;
  final AuthError? failure;
  final String? failureMessage;

  bool get canResend => secondsLeft == 0 && !sending;
}

class CheckEmailController extends AutoDisposeNotifier<CheckEmailState> {
  Timer? _ticker;

  @override
  CheckEmailState build() {
    ref.onDispose(() => _ticker?.cancel());
    _startCooldown();
    return CheckEmailState(secondsLeft: resendCooldown.inSeconds);
  }

  void _startCooldown() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = state.secondsLeft - 1;
      state = CheckEmailState(
        secondsLeft: left < 0 ? 0 : left,
        resent: state.resent,
        failure: state.failure,
        failureMessage: state.failureMessage,
      );
      if (left <= 0) timer.cancel();
    });
  }

  Future<void> resend(String email) async {
    if (!state.canResend) return;
    final resent = state.resent;
    state = CheckEmailState(secondsLeft: 0, sending: true, resent: resent);
    final result = await ref.read(authRepositoryProvider).resendConfirmation(email);
    switch (result) {
      case AuthOk():
        state = CheckEmailState(secondsLeft: resendCooldown.inSeconds, resent: true);
        _startCooldown();
      case AuthFailed(:final error, :final message):
        state = CheckEmailState(
          secondsLeft: 0,
          resent: resent,
          failure: error,
          failureMessage: message,
        );
    }
  }
}

final checkEmailControllerProvider =
    NotifierProvider.autoDispose<CheckEmailController, CheckEmailState>(
      CheckEmailController.new,
    );
