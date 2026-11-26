/// Client configuration. PRD §6.
///
/// **The client holds the Supabase anon key and nothing else** (CLAUDE.md #1).
/// No OpenRouter key, no service key, no database URL: an APK is unzippable in
/// minutes, and everything institutional goes through the backend, which
/// applies the audience filter inside the retrieval query.
///
/// Values come from `--dart-define` so a build can point at a different
/// backend without a code change:
///
///     flutter run \
///       --dart-define=BULLETIN_API_URL=http://192.168.0.5:8000 \
///       --dart-define=BULLETIN_SUPABASE_URL=https://<ref>.supabase.co \
///       --dart-define=BULLETIN_SUPABASE_ANON_KEY=sb_publishable_...
library;

import 'package:flutter/foundation.dart' show kDebugMode;

abstract final class AppConfig {
  /// The backend. `10.0.2.2` is the host machine as seen from the Android
  /// emulator; a physical device needs the laptop's LAN address.
  static const apiBaseUrl = String.fromEnvironment(
    'BULLETIN_API_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const supabaseUrl = String.fromEnvironment('BULLETIN_SUPABASE_URL');

  /// Safe in the client under row-level security (PRD §6). Never the service
  /// key -- that one bypasses RLS by design.
  static const supabaseAnonKey = String.fromEnvironment('BULLETIN_SUPABASE_ANON_KEY');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// A test account that pre-fills Sign in, for DEBUG builds only. Read it
  /// through [devAccount], never directly: that getter is what keeps the
  /// strings out of a release build.
  static const _devEmail = String.fromEnvironment('BULLETIN_DEV_EMAIL');
  static const _devPassword = String.fromEnvironment('BULLETIN_DEV_PASSWORD');

  /// The debug test account, or null. In release `kDebugMode` is the
  /// constant false, so the compiler drops both strings from the binary.
  static ({String email, String password})? get devAccount {
    if (!kDebugMode || _devEmail.isEmpty) return null;
    return (email: _devEmail, password: _devPassword);
  }

  /// Client-side limits, kept in step with the backend's (PRD §8.5, §10). They
  /// exist to fail fast and explain, not to enforce: the server decides.
  static const attachmentMaxMb = 10;
  static const uploadMaxMb = 20;

  /// Longest a single photo edge may be after downscaling. A 12 MP photo is
  /// 4 MB of detail the vision model does not use; 2000px keeps course codes
  /// legible and the upload small (DESIGN §6.4).
  static const imageMaxEdge = 2000;
  static const imageQuality = 85;
}
