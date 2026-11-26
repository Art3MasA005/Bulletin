/// Join form state. The text lives in the screen's controllers; this holds
/// what the form has learned about it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../data/auth_repository.dart';
import '../../data/join_repository.dart';
import '../../domain/join.dart';

@immutable
class JoinState {
  const JoinState({this.busy = false, this.failure, this.failureMessage});

  final bool busy;
  final JoinError? failure;
  final String? failureMessage;

  /// Shown on the code field itself; every other failure gets a box.
  bool get codeRejected => failure == JoinError.codeNotFound;
}

class JoinController extends AutoDisposeNotifier<JoinState> {
  @override
  JoinState build() => const JoinState();

  Future<void> submit({required String code, required String displayName}) async {
    if (state.busy) return;

    // Too short or too long for the server to accept: the same answer a
    // wrong code gets, without the round trip.
    if (!isPlausibleInviteCode(code)) {
      state = const JoinState(failure: JoinError.codeNotFound);
      return;
    }

    state = const JoinState(busy: true);
    // Left empty, the name from sign-up stands in, as the helper promises.
    final typed = displayName.trim();
    final name = typed.isEmpty ? ref.read(authRepositoryProvider).fullName : typed;
    final result = await ref.read(joinRepositoryProvider).join(code, displayName: name);

    switch (result) {
      case Joined():
        state = const JoinState();
        // Re-resolving membership is what moves the router on to Home.
        ref.invalidate(membershipProvider);
      case JoinFailed(:final error, :final message):
        state = JoinState(failure: error, failureMessage: message);
    }
  }

  /// Editing the code takes its error away, as the prototype does.
  void codeEdited() {
    if (state.codeRejected) state = const JoinState();
  }

  Future<void> signOut() => ref.read(authRepositoryProvider).signOut();
}

final joinControllerProvider = NotifierProvider.autoDispose<JoinController, JoinState>(
  JoinController.new,
);
