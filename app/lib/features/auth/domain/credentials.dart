/// Client-side checks on what the user typed. They exist to fail fast and
/// explain; the server still decides.
library;

/// The prototype's rule: something, an @, something, a dot, something.
final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool looksLikeEmail(String value) => _email.hasMatch(value.trim());

/// The handoff asks for at least 8 characters (stricter than Supabase's 6).
const minPasswordLength = 8;
