/// Bulletin — ask your institution's documents, in English or Bangla.
///
/// The root does four things and nothing else: initialise Supabase, wrap the
/// app in the ambient background, put the splash above it, and route on auth
/// state. Screens do the rest.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/prefs/preferences.dart';
import 'core/providers.dart';
import 'core/routing/app_phase.dart';
import 'core/routing/phase_switcher.dart';
import 'core/theme/theme.dart';
import 'features/auth/presentation/auth_flow.dart';
import 'features/auth/presentation/join/join_screen.dart';
import 'features/chat/presentation/chat_screen.dart';
import 'features/splash/presentation/launch_gate.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      // The publishable (formerly anon) key, never the secret key
      // (CLAUDE.md #1). Safe in the client under row-level security.
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }

  // A preferences store that fails to load costs only the remembered
  // language and model, not the launch.
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } on Exception {
    prefs = null;
  }

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const BulletinApp(),
    ),
  );
}

class BulletinApp extends ConsumerWidget {
  const BulletinApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'Bulletin',
      debugShowCheckedModeBanner: false,
      theme: buildBulletinTheme(),
      locale: locale,
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L.supportedLocales,
      // The background sits above the Navigator so it never rebuilds on a
      // route change and never scrolls (DESIGN §3). The splash sits above
      // both, so the app is built and restoring its session while the splash
      // plays.
      builder: (context, child) =>
          AmbientBackground(child: LaunchGate(child: child ?? const SizedBox())),
      home: const _Root(),
    );
  }
}

/// Decides which screen shows ([appPhaseFor]) and hands over between them
/// ([PhaseSwitcher]: into Home, the old layer fades and scales away on top).
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppConfig.isConfigured) return const _NotConfigured();

    final phase = appPhaseFor(
      signedIn: ref.watch(isSignedInProvider),
      membership: ref.watch(membershipProvider),
    );
    return PhaseSwitcher(
      phase: phase,
      child: switch (phase) {
        AppPhase.auth => const AuthFlow(),
        AppPhase.loading => const _Loading(),
        AppPhase.join => const JoinScreen(),
        AppPhase.main => const ChatScreen(),
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(child: CircularProgressIndicator(color: BulletinColors.accent)),
    );
  }
}

/// Shown when the build has no Supabase credentials. A blank screen here would
/// look like a crash; this says exactly what is missing.
class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Not configured', style: BulletinText.screenTitle),
              const SizedBox(height: Space.md),
              Text(
                'Run with --dart-define=BULLETIN_SUPABASE_URL=... and '
                '--dart-define=BULLETIN_SUPABASE_ANON_KEY=...',
                style: BulletinText.messageBody.copyWith(color: BulletinColors.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
