/// Welcome (handoff README §2.2; prototype `ab.welcome`): the first thing a
/// signed-out person sees after the splash.
///
/// A 480 px orange hero with 40 px bottom corners (four drifting clouds,
/// the splash's arc and sparkles, and the whole panda swaying at y 262;
/// handoff CHANGES.md for the clouds), then on white the
/// title, the subtitle and one "Log in" button pinned to the bottom.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/brand_sky.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/drifting_clouds.dart';
import '../../../../core/widgets/hero_sky.dart';
import '../../../../core/widgets/max_width.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../splash/presentation/after_launch.dart';
import 'welcome_clouds.dart';
import 'welcome_panda.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({required this.onLogIn, super.key});

  final VoidCallback onLogIn;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: BulletinColors.white,
      // One scroll view: at normal sizes everything fits and the button sits
      // at the bottom; with large text the page scrolls instead of clipping.
      body: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(pandaLabel: l.pandaWavingLabel),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 28, 24, math.max(36, bottom + 16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            l.welcomeTitle,
                            style: BulletinText.resolve(
                              BulletinText.welcomeTitle,
                              l.welcomeTitle,
                            ),
                          ),
                        ),
                        MaxWidth(
                          maxWidth: 300,
                          child: Text(
                            l.welcomeSubtitle,
                            style: BulletinText.resolve(
                              BulletinText.welcomeSubtitle,
                              l.welcomeSubtitle,
                            ),
                          ),
                        ),
                        const Spacer(),
                        PrimaryButton(
                          label: l.welcomeLogIn,
                          onPressed: onLogIn,
                          size: ButtonSize.regular,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.pandaLabel});

  final String pandaLabel;

  /// The prototype's hero, in its 844-tall frame. On a shorter screen it
  /// gives up height (down to [_minHeight]) before the text below has to
  /// scroll.
  static const _height = 480.0;
  static const _minHeight = 380.0;
  static const _frameHeight = 844.0;

  /// The panda's top at y 262 leaves 28 px under its 190 px height; it keeps
  /// that gap to the hero's bottom edge when the hero shrinks.
  static const _pandaBottom = 28.0;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).height;
    final height = (_height - math.max(0, _frameHeight - screen)).clamp(
      _minHeight,
      _height,
    );

    return ClipRRect(
      borderRadius: BrandRadii.welcomeHero,
      child: ColoredBox(
        color: BulletinColors.brand,
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              // Clouds drift behind; the arc and sparkles stay put above them.
              const Positioned.fill(child: DriftingClouds(welcomeClouds)),
              const Positioned.fill(child: BrandSky(heroSkyDetails)),
              Positioned(
                left: 0,
                right: 0,
                bottom: _pandaBottom,
                child: Center(
                  // The peek plays once the splash has gone, not under it.
                  child: AfterLaunch(
                    placeholder: SizedBox.fromSize(size: WelcomePanda.size),
                    child: WelcomePanda(semanticLabel: pandaLabel),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
