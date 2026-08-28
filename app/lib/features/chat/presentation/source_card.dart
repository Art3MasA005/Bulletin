/// The Source Card. DESIGN §4 — the signature element.
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │ ▏ Exam Routine, Spring 2026        [EN] │
/// │ ▏ Page 3                                │
/// │ ▏                                       │
/// │ ▏ "Final examinations commence on..."   │
/// │ ▏                                       │
/// │ ▏ Open page 3  ›                        │
/// └─────────────────────────────────────────┘
/// ```
///
/// Three decisions carry the whole component:
///
/// 1. **The left rule takes the SOURCE's language**, not the answer's. A
///    Bangla notice answering an English question shows a `bn-marker` rule.
///    That mismatch is the product's central claim made visible.
///
/// 2. **The snippet renders in its original language, always.** Translating it
///    would remove the reader's ability to check the claim, which is the only
///    thing a citation is for.
///
/// 3. **Opaque `paper`, never frosted.** Evidence should feel solid — and a
///    `BackdropFilter` here would sit inside a scrolling list, which is the
///    exact thing CLAUDE.md #11 forbids.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/citation.dart';

class SourceCard extends StatelessWidget {
  const SourceCard({required this.citation, this.onOpen, super.key});

  final Citation citation;
  final void Function(Citation citation)? onOpen;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final rule = citation.isBangla ? BulletinColors.bnMarker : BulletinColors.enMarker;
    final title = citation.title ?? citation.section ?? l.appTitle;

    return Semantics(
      button: onOpen != null,
      label: '$title, ${l.pageLabel(citation.pageNo)}',
      child: Material(
        // Opaque, not frosted (DESIGN §4).
        color: BulletinColors.paper,
        borderRadius: Radii.cardAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen == null ? null : () => onOpen!(citation),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Sizes.minTouchTarget),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The 3px rule, full height of the card.
                  Container(width: Sizes.sourceRule, color: rule),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.md,
                        Space.md,
                        Space.md,
                        Space.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: BulletinText.resolve(
                                    BulletinText.sourceTitle,
                                    title,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: Space.sm),
                              _LanguageBadge(lang: citation.lang, color: rule),
                            ],
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            l.pageLabel(citation.pageNo),
                            // Page numbers are data, so they are mono
                            // (DESIGN §3).
                            style: BulletinText.courseCode.copyWith(
                              fontSize: 12,
                              color: BulletinColors.inkMuted,
                            ),
                          ),
                          if (citation.snippet.isNotEmpty) ...[
                            const SizedBox(height: Space.sm),
                            Text(
                              citation.snippet,
                              // Resolved per string: this is the one place a
                              // Bangla source shows through in an English UI.
                              style: BulletinText.resolve(
                                BulletinText.sourceSnippet,
                                citation.snippet,
                              ),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (onOpen != null) ...[
                            const SizedBox(height: Space.sm),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    l.openPage(citation.pageNo),
                                    style: BulletinText.sourceTitle.copyWith(
                                      color: BulletinColors.accent,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: BulletinColors.accent,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `[EN]` / `[BN]`, in the same colour as the rule.
class _LanguageBadge extends StatelessWidget {
  const _LanguageBadge({required this.lang, required this.color});

  final String lang;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: Radii.chipAll,
      ),
      child: Text(
        lang.toUpperCase(),
        style: BulletinText.meta.copyWith(color: color, fontFamily: Fonts.mono),
      ),
    );
  }
}

/// The source list under an answer: two cards, then a count (DESIGN §4).
///
/// The cap is not decoration. Five cards under every answer would make the
/// evidence feel like noise, and the third source is almost always weaker than
/// the first two — the reranker put it third for a reason.
class SourceList extends StatefulWidget {
  const SourceList({required this.citations, this.onOpen, super.key});

  final List<Citation> citations;
  final void Function(Citation citation)? onOpen;

  @override
  State<SourceList> createState() => _SourceListState();
}

class _SourceListState extends State<SourceList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.citations.isEmpty) return const SizedBox.shrink();

    final l = L.of(context);
    final hidden = widget.citations.length - Sizes.visibleSourceCards;
    final visible = _expanded || hidden <= 0
        ? widget.citations
        : widget.citations.take(Sizes.visibleSourceCards).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final citation in visible) ...[
          SourceCard(citation: citation, onOpen: widget.onOpen),
          const SizedBox(height: Space.sm),
        ],
        if (hidden > 0 && !_expanded)
          TextButton(
            onPressed: () => setState(() => _expanded = true),
            child: Text(l.moreSources(hidden)),
          ),
      ],
    );
  }
}
