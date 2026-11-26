/// The few choices the app remembers between launches: the interface
/// language and the picked model.
///
/// `shared_preferences` rather than the Drift database: two short strings
/// need no schema or migration. The instance is loaded once in `main` and
/// handed in through [sharedPreferencesProvider]; where it is absent (widget
/// tests, a failed load) the choices still work for the session and are
/// simply not remembered.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

abstract final class PrefKeys {
  static const locale = 'interface_locale';
  static const model = 'picked_model';
}

/// The interface language, independent of the query language.
///
/// PRD §3: the app is bilingual, and a student may run the interface in Bangla
/// while asking in English, or the reverse. Null follows the device.
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() {
    final code = ref.watch(sharedPreferencesProvider)?.getString(PrefKeys.locale);
    return code == null ? null : Locale(code);
  }

  void set(Locale locale) {
    state = locale;
    ref.read(sharedPreferencesProvider)?.setString(PrefKeys.locale, locale.languageCode);
  }
}

final localeProvider = NotifierProvider<LocaleController, Locale?>(LocaleController.new);
