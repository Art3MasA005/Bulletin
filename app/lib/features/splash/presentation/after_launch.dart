/// Holds a screen's entry animation until the splash has started to leave.
///
/// The app is built beneath the splash (see [LaunchGate]), so without this a
/// screen's fade-ups would play out unseen behind the panda and the user
/// would arrive at a screen that is already still.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/launch_phase.dart';
import 'launch_controller.dart';

class AfterLaunch extends ConsumerWidget {
  const AfterLaunch({
    required this.child,
    this.placeholder = const SizedBox.shrink(),
    super.key,
  });

  final Widget child;

  /// What stands in while the splash covers the screen.
  final Widget placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launched = ref.watch(launchPhaseProvider) != LaunchPhase.splash;
    return launched ? child : placeholder;
  }
}
