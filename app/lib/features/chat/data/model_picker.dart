/// Which models are offered, and which one the user picked.
///
/// The pick is remembered between launches (`core/prefs`). A remembered key
/// the server no longer offers falls back to the default ([currentModel]).

library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/net/result.dart';
import '../../../core/prefs/preferences.dart';
import '../../../core/providers.dart';
import '../domain/model_choice.dart';

/// The server's allow-list. Empty on any failure: the picker hides and every
/// question goes to the default, which is what a missing list means anyway.
final modelChoicesProvider = FutureProvider<List<ModelChoice>>((ref) async {
  final result = await ref.watch(apiClientProvider).models();
  return switch (result) {
    Ok(:final value) => [for (final m in value) ModelChoice.fromJson(m)],
    Failure() => const [],
  };
});

class PickedModel extends Notifier<String?> {
  @override
  String? build() => ref.watch(sharedPreferencesProvider)?.getString(PrefKeys.model);

  void pick(String key) {
    state = key;
    ref.read(sharedPreferencesProvider)?.setString(PrefKeys.model, key);
  }
}

final pickedModelProvider = NotifierProvider<PickedModel, String?>(PickedModel.new);

/// The model the next question goes to; null hides the picker.
final currentModelProvider = Provider<ModelChoice?>((ref) {
  final offered = ref.watch(modelChoicesProvider).valueOrNull ?? const [];
  return currentModel(offered, ref.watch(pickedModelProvider));
});
