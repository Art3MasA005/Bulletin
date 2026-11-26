/// Joining an institution, behind an interface so the Join screen can be
/// tested without a network. The API client already returns a sealed
/// [Result]; this narrows its failures to the ones the screen tells apart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/net/result.dart';
import '../../../core/providers.dart';
import '../domain/join.dart';

abstract interface class JoinRepository {
  Future<JoinResult> join(String inviteCode, {String? displayName});
}

class ApiJoinRepository implements JoinRepository {
  const ApiJoinRepository(this._ref);

  final Ref _ref;

  @override
  Future<JoinResult> join(String inviteCode, {String? displayName}) async {
    final result = await _ref
        .read(apiClientProvider)
        .joinInstitution(normalizeInviteCode(inviteCode), displayName: displayName);

    return switch (result) {
      Ok(:final value) => Joined(value),
      Failure(:final kind, :final message) => JoinFailed(switch (kind) {
        FailureKind.notFound => JoinError.codeNotFound,
        FailureKind.conflict => JoinError.alreadyMember,
        FailureKind.offline => JoinError.offline,
        _ => JoinError.other,
      }, message: message),
    };
  }
}

final joinRepositoryProvider = Provider<JoinRepository>(ApiJoinRepository.new);
