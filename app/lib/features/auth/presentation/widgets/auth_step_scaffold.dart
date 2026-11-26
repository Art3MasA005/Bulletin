/// The layout of the auth step that sits on the canvas (check email): back
/// button, title and subtitle, the step's content, then a footer pinned to
/// the bottom when there is room and scrolled to when there is not
/// (prototype `ab.check`: padding 60/24/28, gap 14).
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../l10n/app_localizations.dart';

class AuthStepScaffold extends StatelessWidget {
  const AuthStepScaffold({
    required this.onBack,
    required this.title,
    required this.children,
    this.subtitle,
    this.footer,
    super.key,
  });

  final VoidCallback onBack;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Pinned under a flexible gap, like the prototype's `flex: 1` spacer.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final top = MediaQuery.viewPaddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, top + 12, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 14,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: BackSquareButton(
                      onPressed: onBack,
                      semanticLabel: l.backLabel,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 6,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: BulletinText.resolve(BulletinText.stepTitle, title),
                          ),
                        ),
                        if (subtitle case final text?)
                          Text(
                            text,
                            style: BulletinText.resolve(BulletinText.stepSubtitle, text),
                          ),
                      ],
                    ),
                  ),
                  ...children,
                  if (footer case final pinned?) ...[const Spacer(), pinned],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
