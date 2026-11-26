/// The sources under an answer (CHANGES.md, "Sources are collapsed by
/// default").
///
/// A "SOURCES" header, then one compact row per source: a number badge in the
/// source's language colour, a one-line title, a page pill and a chevron. A
/// tap opens the row in place (white, lifted, chevron turned 180 deg) to the
/// language tag, the snippet in its own language (5 lines at most) and an
/// orange "Open page" pill. One row is open at a time; two rows show and
/// "+ N more sources" reveals the rest.
///
/// Rows are opaque or white-tinted, never frosted: they sit in a scrolling
/// list, where a `BackdropFilter` is forbidden (CLAUDE.md #11).
library;

import 'package:flutter/material.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/citation.dart';

class SourceList extends StatefulWidget {
  const SourceList({
    required this.citations,
    this.onOpen,
    this.delay = Duration.zero,
    super.key,
  });

  final List<Citation> citations;

  /// Opens the source viewer at the cited page.
  final void Function(Citation citation)? onOpen;

  /// Where the stagger starts, so the rows come in after whatever is above.
  final Duration delay;

  @override
  State<SourceList> createState() => _SourceListState();
}

class _SourceListState extends State<SourceList> {
  int? _open;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final citations = widget.citations;
    if (citations.isEmpty) return const SizedBox.shrink();

    final l = L.of(context);
    final shown = _showAll
        ? citations
        : citations.take(Sizes.visibleSourceCards).toList(growable: false);
    final hidden = citations.length - shown.length;
    final header = BulletinText.resolve(BulletinText.sourcesHeader, l.sourcesHeader);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        Semantics(
          header: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              spacing: 6,
              children: [
                LineIcon(LineIcons.file, color: header.color!, size: 14, strokeWidth: 2),
                Text(l.sourcesHeader.toUpperCase(), style: header),
              ],
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            for (var i = 0; i < shown.length; i++)
              FadeUp(
                // Rows 0 and 1 stagger 40 ms apart; revealed ones start over.
                delay: widget.delay + Duration(milliseconds: 40 * (i < 2 ? i : i - 2)),
                duration: MotionDurations.section,
                child: _SourceRow(
                  number: i + 1,
                  citation: shown[i],
                  open: _open == i,
                  onToggle: () => setState(() => _open = _open == i ? null : i),
                  onOpenPage: widget.onOpen == null
                      ? null
                      : () => widget.onOpen!(shown[i]),
                ),
              ),
          ],
        ),
        if (hidden > 0) _MoreButton(count: hidden, onTap: () => setState(() => _showAll = true)),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.number,
    required this.citation,
    required this.open,
    required this.onToggle,
    this.onOpenPage,
  });

  final int number;
  final Citation citation;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback? onOpenPage;

  static const _radius = BorderRadius.all(Radius.circular(16));

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final title = citation.title ?? citation.section ?? l.appTitle;
    final rule = citation.isBangla ? BulletinColors.bnMarker : BulletinColors.enMarker;
    final tint = citation.isBangla ? BulletinColors.bnTint : BulletinColors.enTint;
    final page = l.pageLabel(citation.pageNo);
    final reduced = reduceMotionOf(context);
    final fade = reduced ? MotionDurations.reduced : MotionDurations.fade;

    return AnimatedContainer(
      duration: fade,
      curve: MotionCurves.out,
      decoration: BoxDecoration(
        color: open ? BulletinColors.white : BulletinColors.threadCard,
        borderRadius: _radius,
        // Collapsed rows are outlined; an open one is lifted instead.
        border: Border.all(color: open ? Colors.transparent : BulletinColors.hairline),
        boxShadow: open ? BrandLifts.sourceOpen : const [],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            label: l.sourceExpandLabel(title, page),
            excludeSemantics: true,
            child: InkWell(
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Sizes.minTouchTarget),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                  child: Row(
                    spacing: 10,
                    children: [
                      _NumberBadge(number: number, color: rule, tint: tint),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BulletinText.resolve(BulletinText.sourceTitle, title),
                        ),
                      ),
                      _Pill(label: page, color: BulletinColors.inkBody),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: reduced ? MotionDurations.reduced : MotionDurations.fade,
                        curve: MotionCurves.out,
                        child: LineIcon(
                          LineIcons.chevronDown,
                          color: BulletinColors.mutedIcon,
                          size: 16,
                          strokeWidth: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: fade,
            curve: MotionCurves.out,
            alignment: Alignment.topCenter,
            child: open
                ? _Opened(
                    citation: citation,
                    tint: tint,
                    rule: rule,
                    onOpenPage: onOpenPage,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.number, required this.color, required this.tint});

  final int number;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
      child: Text('$number', style: BulletinText.sourceMono.copyWith(color: color)),
    );
  }
}

/// A mono pill: the page, or the source's language.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.tint});

  final String label;
  final Color color;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: tint ?? BulletinColors.chipFillStrong,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Text(
        label,
        style: BulletinText.resolve(BulletinText.sourceMono, label).copyWith(color: color),
      ),
    );
  }
}

class _Opened extends StatelessWidget {
  const _Opened({
    required this.citation,
    required this.tint,
    required this.rule,
    this.onOpenPage,
  });

  final Citation citation;
  final Color tint;
  final Color rule;
  final VoidCallback? onOpenPage;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return FadeUp(
      duration: MotionDurations.toggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(42, 0, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.md,
          children: [
            _Pill(label: citation.lang.toUpperCase(), color: rule, tint: tint),
            if (citation.snippet.isNotEmpty)
              Text(
                citation.snippet,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                // The source's own language, untranslated: it is how a reader
                // checks the claim against the page.
                style: BulletinText.resolve(BulletinText.snippet, citation.snippet),
              ),
            if (onOpenPage != null)
              _OpenPageButton(label: l.openPage(citation.pageNo), onTap: onOpenPage!),
          ],
        ),
      ),
    );
  }
}

class _OpenPageButton extends StatefulWidget {
  const _OpenPageButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_OpenPageButton> createState() => _OpenPageButtonState();
}

class _OpenPageButtonState extends State<_OpenPageButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: MotionDurations.press,
          curve: MotionCurves.spring,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: BulletinColors.brandStrong,
              borderRadius: BorderRadius.all(Radius.circular(22)),
              boxShadow: BrandLifts.accentButtonSoft,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Flexible(
                  child: Text(
                    widget.label,
                    style: BulletinText.resolve(BulletinText.pillAction, widget.label),
                  ),
                ),
                LineIcon(
                  LineIcons.arrowUpRight,
                  color: BulletinColors.white,
                  size: 16,
                  strokeWidth: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = L.of(context).moreSources(count);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                LineIcon(
                  LineIcons.plus,
                  color: BulletinColors.brandText,
                  size: 16,
                  strokeWidth: 2.2,
                ),
                Flexible(
                  child: Text(label, style: BulletinText.resolve(BulletinText.moreSources, label)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
