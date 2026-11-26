/// Which part of the app is showing, decided from auth and membership alone.
///
/// Three settled states, and the middle one is easy to forget: signed out,
/// signed in but not a member of any institution (PRD §4 — members join by
/// invite code), and signed in with a membership. Plus the moment in
/// between, while membership is still being asked for.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../net/api_client.dart' show Membership;

enum AppPhase {
  /// Signed out: welcome, sign in, create account, check email.
  auth,

  /// Signed in, membership not known yet.
  loading,

  /// Signed in, not a member: the invite code.
  join,

  /// A member: Home and the chat.
  main,
}

AppPhase appPhaseFor({
  required bool signedIn,
  required AsyncValue<Membership?> membership,
}) {
  if (!signedIn) return AppPhase.auth;
  return membership.when(
    loading: () => AppPhase.loading,
    // Unknown membership sends the user to Join, which explains itself and
    // offers Sign out, rather than to a Home that cannot answer.
    error: (_, _) => AppPhase.join,
    data: (value) => value == null ? AppPhase.join : AppPhase.main,
  );
}
