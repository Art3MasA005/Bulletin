/// Who Home greets, and by what name (prototype `home.greet`: the display
/// name, else the first word of the full name).
library;

/// The name to greet with: the display name chosen at join, else the first
/// word of the name given at sign-up, else none.
String? greetingName({String? displayName, String? fullName}) {
  final chosen = displayName?.trim();
  if (chosen != null && chosen.isNotEmpty) return chosen;
  final full = fullName?.trim();
  if (full == null || full.isEmpty) return null;
  return full.split(RegExp(r'\s+')).first;
}
