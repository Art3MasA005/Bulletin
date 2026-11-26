/// The layout Sign in and Sign up share (handoff README §2.3, CHANGES.md):
/// an orange header (drifting clouds, twinkling sparkles, glass back button,
/// title, subtitle) and a white sheet with 32 px top corners rising over it,
/// with the small panda gripping the sheet's top edge.
///
/// Motion (README §5): the sheet rises 14 px over 520 ms after 40, the title
/// block 450 ms after 80. Nothing plays while the splash still covers the
/// screen.
library;

import 'package:flutter/material.dart';

import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/drifting_clouds.dart';
import '../../../../core/widgets/max_width.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../splash/presentation/after_launch.dart';
import 'auth_header_clouds.dart';
import 'sheet_panda.dart';

class AuthSheetScaffold extends StatelessWidget {
  const AuthSheetScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
    this.onBack,
    super.key,
  });

  /// Null hides the back button.
  final VoidCallback? onBack;
  final String title;
  final String subtitle;

  /// The sheet's content, top to bottom, 16 apart. A [Spacer] pushes what
  /// follows it to the bottom when there is room.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BulletinColors.brand,
      // One scroll view for header and sheet: at normal sizes the sheet fills
      // the screen below a 262 px header exactly as in the prototype; with
      // large text the header grows and the whole screen scrolls, rather than
      // the header clipping its own title.
      body: AfterLaunch(
        child: CustomScrollView(
          slivers: [
            // Header and sheet in ONE sliver, sheet second. A viewport paints
            // earlier slivers on top of later ones, so as two slivers the
            // header's drifting clouds passed over the panda that peeks up
            // out of the sheet. In a Column the sheet paints last, panda
            // included, as in the prototype.
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(onBack: onBack, title: title, subtitle: subtitle),
                  Expanded(
                    child: FadeUp(
                      offset: 14,
                      duration: const Duration(milliseconds: 520),
                      delay: const Duration(milliseconds: 40),
                      child: _Sheet(children: children),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack, required this.title, required this.subtitle});

  final VoidCallback? onBack;
  final String title;
  final String subtitle;

  /// The prototype's header is 262 tall with content starting at 56, under
  /// a 48 px status bar. On a device the inset varies, so the content keeps
  /// its 8 px clearance below the real status bar instead.
  static const _height = 262.0;
  static const _contentTop = 56.0;
  static const _pandaClearance = 96.0;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final top = MediaQuery.viewPaddingOf(context).top;
    final contentTop = top + 8 > _contentTop ? top + 8 : _contentTop;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: _height - _contentTop + contentTop),
      child: Stack(
        children: [
          // Clipped to the header, as the prototype's `overflow: hidden`.
          const Positioned.fill(child: ClipRect(child: DriftingClouds(authHeaderClouds))),
          Padding(
            // The bottom keeps a grown header's text clear of the panda,
            // which peeks [_pandaClearance] px above the sheet.
            padding: EdgeInsets.fromLTRB(24, contentTop, 24, _pandaClearance),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 22,
              children: [
                if (onBack case final back?)
                  BackSquareButton(
                    onPressed: back,
                    semanticLabel: l.backLabel,
                    onBrand: true,
                  ),
                FadeUp(
                  offset: 14,
                  duration: const Duration(milliseconds: 450),
                  delay: const Duration(milliseconds: 80),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 6,
                    children: [
                      // One line in the prototype; it fits at normal sizes in
                      // both languages and wraps rather than clips when large.
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: BulletinText.resolve(BulletinText.authTitle, title),
                        ),
                      ),
                      MaxWidth(
                        maxWidth: 210,
                        child: Text(
                          subtitle,
                          style: BulletinText.resolve(
                            BulletinText.authSubtitle,
                            subtitle,
                          ),
                        ),
                      ),
                    ],
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

class _Sheet extends StatelessWidget {
  const _Sheet({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Not scrollable itself: the screen's one scroll view moves header and
    // sheet together, so there is never a scroll inside a scroll.
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            color: BulletinColors.white,
            borderRadius: BrandRadii.authCard,
            boxShadow: BrandLifts.authCard,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.lg,
                children: children,
              ),
            ),
          ),
        ),
        // On the sheet's top edge, right 18: the head is clipped at the
        // edge, the gripping paw hangs over it.
        const Positioned(right: 18, top: -80, child: IgnorePointer(child: SheetPanda())),
      ],
    );
  }
}

/// "New to Bulletin? Create account" / "Already have an account? Sign in".
class AuthSwitchLine extends StatelessWidget {
  const AuthSwitchLine({
    required this.question,
    required this.action,
    required this.onTap,
    super.key,
  });

  final String question;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text(question, style: BulletinText.resolve(BulletinText.footer, question)),
        TextLink(
          label: action,
          onPressed: onTap,
          style: BulletinText.footer.copyWith(
            color: BulletinColors.brandText,
            fontWeight: FontWeight.w600,
            fontVariations: Weights.semiBold,
          ),
        ),
      ],
    );
  }
}
