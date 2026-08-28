/// The provider graph. CLAUDE.md: Riverpod for all state.
///
/// Three things live here because every feature needs them and none of them
/// belongs to one feature: the Supabase session, the API client built from it,
/// and the caller's membership as the backend resolves it.
///
/// Note what `membershipProvider` is NOT: it does not read the role from the
/// token. The backend reads it from `profiles` on every request (see
/// backend/app/api/auth.py), and the app asks the backend. A client that
/// decided its own role would show a student the publish button and then get a
/// 403 — or worse, be trusted.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'net/api_client.dart';
import 'net/result.dart';

/// The Supabase client. Overridden in tests with a fake.
final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Auth state as a stream, so sign-in and token refresh both flow through one
/// place and every screen reacts to a sign-out without being told.
final authStateProvider = StreamProvider<AuthState?>((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});

/// The current session, or null. Reads the client directly rather than the
/// stream so a first frame does not have to wait for an event.
final sessionProvider = Provider<Session?>((ref) {
  // Watching the stream keeps this in step with sign-in and sign-out.
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentSession;
});

final isSignedInProvider = Provider<bool>((ref) => ref.watch(sessionProvider) != null);

/// One API client for the app. The token is read per request, not captured,
/// because Supabase refreshes it in the background.
final apiClientProvider = Provider<ApiClient>((ref) {
  final supabase = ref.watch(supabaseProvider);
  return ApiClient(token: () => supabase.auth.currentSession?.accessToken);
});

/// Who the caller is, from the backend. Null while signed out.
///
/// A [Failure] with [FailureKind.unauthenticated] here means "signed in, but
/// has not joined an institution yet" — which is the join screen, not an
/// error. The router treats it that way.
final membershipProvider = FutureProvider<Membership?>((ref) async {
  if (!ref.watch(isSignedInProvider)) return null;
  final result = await ref.watch(apiClientProvider).me();
  return switch (result) {
    Ok(:final value) => value,
    Failure() => null,
  };
});

/// The interface language, independent of the query language.
///
/// PRD §3: the app is bilingual, and a student may run the interface in Bangla
/// while asking in English, or the reverse. Defaults to the device locale.
final localeProvider = StateProvider<Locale?>((ref) => null);
