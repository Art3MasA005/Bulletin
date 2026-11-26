/// Every auth call the app makes, behind one interface.
///
/// The screens depend on [AuthRepository], never on Supabase, so their tests
/// run against a fake and the Supabase error codes are translated in exactly
/// one place ([SupabaseAuthRepository._map]).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import '../domain/auth_result.dart';

abstract interface class AuthRepository {
  Future<AuthResult<void>> signIn({required String email, required String password});

  Future<AuthResult<SignUpOutcome>> signUp({
    required String name,
    required String email,
    required String password,
  });

  Future<AuthResult<void>> sendPasswordReset(String email);

  Future<AuthResult<void>> resendConfirmation(String email);

  /// Ends the session; the router returns to the signed-out flow.
  Future<AuthResult<void>> signOut();

  /// The name given at sign-up (`full_name` in the user's metadata), if any.
  String? get fullName;
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseProvider).auth),
);

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._auth);

  final GoTrueClient _auth;

  @override
  Future<AuthResult<void>> signIn({required String email, required String password}) {
    return _guard(() async {
      await _auth.signInWithPassword(email: email.trim(), password: password);
      // The router watches the session; there is nothing to return.
    });
  }

  @override
  Future<AuthResult<SignUpOutcome>> signUp({
    required String name,
    required String email,
    required String password,
  }) {
    return _guard(() async {
      final response = await _auth.signUp(
        email: email.trim(),
        password: password,
        // Carried in the user's metadata so the join step can offer it as
        // the display name instead of asking twice.
        data: {if (name.trim().isNotEmpty) 'full_name': name.trim()},
      );
      return response.session == null
          ? SignUpOutcome.confirmationSent
          : SignUpOutcome.signedIn;
    });
  }

  @override
  Future<AuthResult<void>> sendPasswordReset(String email) {
    return _guard(() => _auth.resetPasswordForEmail(email.trim()));
  }

  @override
  Future<AuthResult<void>> resendConfirmation(String email) {
    return _guard(() async {
      await _auth.resend(type: OtpType.signup, email: email.trim());
    });
  }

  @override
  Future<AuthResult<void>> signOut() => _guard(_auth.signOut);

  @override
  String? get fullName {
    final name = _auth.currentUser?.userMetadata?['full_name'];
    return name is String && name.trim().isNotEmpty ? name.trim() : null;
  }

  Future<AuthResult<T>> _guard<T>(Future<T> Function() call) async {
    try {
      return AuthOk(await call());
    } on AuthException catch (error) {
      return AuthFailed(_map(error), message: error.message);
    } on SocketException {
      return const AuthFailed(AuthError.offline);
    } on TimeoutException {
      return const AuthFailed(AuthError.offline);
    }
  }

  /// Supabase's error codes (gotrue `ErrorCode`), onto the app's.
  static AuthError _map(AuthException error) {
    if (error is AuthRetryableFetchException) return AuthError.offline;
    if (error is AuthWeakPasswordException) return AuthError.weakPassword;
    return switch (error.code) {
      'invalid_credentials' => AuthError.invalidCredentials,
      'email_not_confirmed' => AuthError.emailNotConfirmed,
      'user_already_exists' || 'email_exists' => AuthError.alreadyRegistered,
      'weak_password' => AuthError.weakPassword,
      'over_email_send_rate_limit' ||
      'over_request_rate_limit' ||
      'over_sms_send_rate_limit' => AuthError.rateLimited,
      _ => error.statusCode == '429' ? AuthError.rateLimited : AuthError.unknown,
    };
  }
}
