/// Saving the display name from Settings.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/net/result.dart';
import '../../../core/providers.dart';
import '../data/profile_repository.dart';

enum NameSave { idle, saving, saved, failed }

class DisplayNameController extends AutoDisposeNotifier<NameSave> {
  @override
  NameSave build() => NameSave.idle;

  /// Saves [name] if it differs from [current]. On success the membership is
  /// refreshed, so Home greets by the new name.
  Future<void> save(String name, {required String? current}) async {
    final next = name.trim();
    if (next == (current ?? '').trim() || state == NameSave.saving) return;
    state = NameSave.saving;
    final result = await ref.read(profileRepositoryProvider).rename(next);
    switch (result) {
      case Ok():
        ref.invalidate(membershipProvider);
        state = NameSave.saved;
      case Failure():
        state = NameSave.failed;
    }
  }

  /// The field changed again: "Saved" no longer describes it.
  void edited() {
    if (state != NameSave.saving) state = NameSave.idle;
  }
}

final displayNameControllerProvider =
    NotifierProvider.autoDispose<DisplayNameController, NameSave>(
      DisplayNameController.new,
    );
