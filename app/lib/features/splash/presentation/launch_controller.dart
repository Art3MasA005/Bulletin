/// Launch state, in Riverpod (CLAUDE.md: Riverpod for all state).
///
/// Screens beneath the splash read [launchPhaseProvider] to hold their own
/// entry animation until the splash has left, rather than playing it unseen
/// behind the panda.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/providers.dart';
import '../domain/launch_phase.dart';
import '../domain/splash_timeline.dart';

class LaunchController extends Notifier<LaunchPhase> {
  @override
  LaunchPhase build() => LaunchPhase.splash;

  /// The splash has finished (auto-advance or a tap). Idempotent.
  void beginReveal() {
    if (state == LaunchPhase.splash) state = LaunchPhase.revealing;
  }

  /// The exit animation has finished; the splash leaves the tree.
  void complete() {
    if (state == LaunchPhase.revealing) state = LaunchPhase.done;
  }
}

final launchPhaseProvider = NotifierProvider<LaunchController, LaunchPhase>(
  LaunchController.new,
);

/// How long the splash holds before advancing on its own.
///
/// Read once, at launch: a session restored from storage means a returning
/// user, who gets the shorter splash. A build with no Supabase config has no
/// session to restore, and reading the client there would throw.
final splashAutoAdvanceProvider = Provider<Duration>((ref) {
  final returning = AppConfig.isConfigured && ref.read(isSignedInProvider);
  return returning ? SplashTimeline.autoAdvanceReturning : SplashTimeline.autoAdvance;
});
