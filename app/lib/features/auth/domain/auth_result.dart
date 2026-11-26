/// What an auth call can come back with, in the app's own terms.
///
/// Supabase reports failures as exceptions carrying string codes; the screens
/// should never see either. The repository maps them onto [AuthError] once,
/// so "wrong password" is a type the sign-in screen can switch on rather than
/// a string it has to recognise (CLAUDE.md: no throwing across layers).
library;

enum AuthError {
  /// Email and password do not match. The sign-in screen shows this on the
  /// password field, not as a generic error: it is the user's to fix.
  invalidCredentials,

  /// The account exists but its email link has not been opened yet.
  emailNotConfirmed,

  /// Sign-up with an email that already has an account.
  alreadyRegistered,

  /// The server rejected the password as too weak.
  weakPassword,

  /// Too many emails or attempts in a short time.
  rateLimited,

  /// No connection.
  offline,

  /// Anything else. The server's own message, if it gave one, travels with it.
  unknown,
}

sealed class AuthResult<T> {
  const AuthResult();
}

final class AuthOk<T> extends AuthResult<T> {
  const AuthOk(this.value);
  final T value;
}

final class AuthFailed<T> extends AuthResult<T> {
  const AuthFailed(this.error, {this.message});
  final AuthError error;

  /// Supabase writes its messages for people; shown only for [AuthError.unknown].
  final String? message;
}

/// What a successful sign-up leads to.
enum SignUpOutcome {
  /// The project auto-confirms: there is a session and the router moves on.
  signedIn,

  /// The project requires email confirmation (ours does): an account and NO
  /// session. Without handling this the button looks dead (TASKS.md, Phase 3).
  confirmationSent,
}
