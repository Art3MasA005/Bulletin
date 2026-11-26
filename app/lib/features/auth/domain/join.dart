/// Joining an institution: invite codes as the backend reads them
/// (`api/institutions.py`: trimmed, upper-cased, 4 to 32 characters), and the
/// outcomes the Join screen tells apart.
library;

import 'package:flutter/foundation.dart';

import '../../../core/net/api_client.dart' show Membership;

/// The backend's bounds (`JoinInstitution.invite_code`).
const minInviteCodeLength = 4;
const maxInviteCodeLength = 32;

/// What the server will compare: surrounding space dropped, upper case.
String normalizeInviteCode(String raw) => raw.trim().toUpperCase();

/// Whether a code is worth sending at all. Shorter than the server accepts
/// fails the same way a wrong code does, without a round trip.
bool isPlausibleInviteCode(String raw) {
  final code = normalizeInviteCode(raw);
  return code.length >= minInviteCodeLength && code.length <= maxInviteCodeLength;
}

/// Why joining failed, in the terms the Join screen renders.
enum JoinError {
  /// No institution has this code. The server words a typo and an unknown
  /// code identically on purpose (the code is a secret), and so do we.
  codeNotFound,

  /// The account is already a member somewhere (409).
  alreadyMember,

  /// The request never reached the server.
  offline,

  /// Anything else: 5xx, an unreadable response.
  other,
}

@immutable
sealed class JoinResult {
  const JoinResult();
}

final class Joined extends JoinResult {
  const Joined(this.membership);
  final Membership membership;
}

final class JoinFailed extends JoinResult {
  const JoinFailed(this.error, {this.message});
  final JoinError error;

  /// The server's own sentence, when it sent one.
  final String? message;
}
