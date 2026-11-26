/// The caller's own profile: renaming, for Settings.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/net/api_client.dart';
import '../../../core/net/result.dart';
import '../../../core/providers.dart';

abstract interface class ProfileRepository {
  /// Blank clears the display name; the app then greets by the sign-up name.
  Future<Result<Membership>> rename(String displayName);
}

class ApiProfileRepository implements ProfileRepository {
  const ApiProfileRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<Membership>> rename(String displayName) =>
      _api.updateDisplayName(displayName.trim());
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ApiProfileRepository(ref.watch(apiClientProvider)),
);
