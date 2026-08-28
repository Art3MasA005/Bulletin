/// The sealed result type every network call returns. CLAUDE.md:
/// "Network calls return a sealed result type. No throwing across layers."
///
/// A thrown exception crossing a layer boundary is how a 429 becomes a red
/// error screen instead of "you have reached today's limit". The failure cases
/// here are the ones the UI must treat differently, and nothing else: each one
/// exists because a screen renders it its own way.
library;

sealed class Result<T> {
  const Result();

  /// The value, or null when this is a failure. Useful at call sites that
  /// genuinely have a fallback; prefer a `switch` everywhere else.
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Failure<T>() => null,
  };

  bool get isOk => this is Ok<T>;
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

/// Why a call failed, in the terms the UI needs.
enum FailureKind {
  /// No network, or the request never reached the server.
  offline,

  /// 401. The session is gone; the app returns to sign-in.
  unauthenticated,

  /// 403. Signed in, but not allowed -- a student trying to publish.
  forbidden,

  /// 404.
  notFound,

  /// 409. The attachment is not confirmed yet, or a document has no file.
  conflict,

  /// 413 or a client-side size check.
  tooLarge,

  /// 429. Carries [Failure.message] from the server, which names the limit.
  quota,

  /// 5xx, or a response we could not parse.
  server,
}

final class Failure<T> extends Result<T> {
  const Failure(this.kind, {this.message, this.statusCode});

  final FailureKind kind;

  /// The server's own wording when it had any. Backend messages are written
  /// for users (PRD, DESIGN §9), so showing them beats inventing a new
  /// sentence -- except for [FailureKind.offline] and [FailureKind.server],
  /// where the text is technical and l10n copy is used instead.
  final String? message;

  final int? statusCode;

  /// Re-type a failure when a call chain changes its value type.
  Failure<R> cast<R>() => Failure<R>(kind, message: message, statusCode: statusCode);

  static FailureKind kindFor(int status) => switch (status) {
    401 => FailureKind.unauthenticated,
    403 => FailureKind.forbidden,
    404 => FailureKind.notFound,
    409 => FailureKind.conflict,
    413 => FailureKind.tooLarge,
    429 => FailureKind.quota,
    _ => FailureKind.server,
  };
}
