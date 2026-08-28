/// Bulletin — ask your institution's documents, in English or Bangla.
///
/// The root does three things and nothing else: initialise Supabase, wrap the
/// app in the ambient gradient, and route on auth state. Screens do the rest.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/providers.dart';
import 'core/theme/theme.dart';
import 'features/auth/presentation/sign_in_screen.dart';
import 'features/chat/presentation/chat_screen.dart';
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

  runApp(const ProviderScope(child: BulletinApp()));
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
      // The gradient sits above the Navigator so it never rebuilds on a route
      // change and never scrolls (DESIGN §3).
      builder: (context, child) => AmbientBackground(child: child ?? const SizedBox()),
      home: const _Root(),
    );
  }
}

/// Decides which screen the app opens on.
///
/// Three states, and the middle one is easy to forget: signed out, signed in
/// but not a member of any institution (PRD §4 — members join by invite code),
/// and signed in with a membership.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppConfig.isConfigured) return const _NotConfigured();

    final signedIn = ref.watch(isSignedInProvider);
    if (!signedIn) return const SignInScreen();

    final membership = ref.watch(membershipProvider);
    return membership.when(
      loading: () => const _Loading(),
      error: (_, __) => const JoinScreen(),
      data: (value) => value == null ? const JoinScreen() : const ChatScreen(),
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
