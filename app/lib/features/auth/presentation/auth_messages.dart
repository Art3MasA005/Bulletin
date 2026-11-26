/// [AuthError] as words, in the user's language. The one place an auth
/// failure becomes text.
library;

import '../../../l10n/app_localizations.dart';
import '../domain/auth_result.dart';

String authErrorText(L l, AuthError error, {String? serverMessage}) => switch (error) {
  AuthError.invalidCredentials => l.authWrongPassword,
  AuthError.emailNotConfirmed => l.authErrorNotConfirmed,
  AuthError.alreadyRegistered => l.authErrorAlreadyRegistered,
  AuthError.weakPassword => l.authErrorWeakPassword,
  AuthError.rateLimited => l.authErrorRateLimited,
  AuthError.offline => l.errorOffline,
  // Supabase writes its messages for people; better than a generic line.
  AuthError.unknown => serverMessage ?? l.errorGeneric,
};
