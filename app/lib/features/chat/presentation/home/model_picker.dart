/// The model picker: the top bar's left pill and the menu it opens
/// (handoff README, "Model picker"; prototype `md`).
///
/// Two pills, one menu. Before the first question (Home) the pill is the
/// model's tinted sparkle and its name; in a thread it is the logo avatar,
/// "Bulletin" and the model on a second line. Either opens the same 300 px
/// menu 8 px below it: an "AI model" overline and a row per offered model,
/// the picked one tinted peach with an orange check.
///
/// The pill is one of the screen's two BackdropFilters (the composer is the
/// other). The menu's fill is .84–.94 white, so it is drawn without one: a
/// third blur would break CLAUDE.md #11 for no visible difference.
///
/// When the server offers no models (none configured, or `/models` failed)
/// the pill is the plain logo + "Bulletin" with nothing to tap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/bulletin_logo.dart';
import '../../../../core/widgets/crystal_glass.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/model_picker.dart';
import '../../domain/model_choice.dart';

/// The tile colours for a model, by its maker (README §1 "Model tints").
({Color tint, Color ink}) modelTint(ModelChoice model) => switch (model.maker
    .toLowerCase()) {
  'anthropic' => (
    tint: BulletinColors.modelAnthropicTint,
    ink: BulletinColors.modelAnthropicInk,
  ),
  'openai' => (tint: BulletinColors.modelOpenAiTint, ink: BulletinColors.modelOpenAiInk),
  'google' => (tint: BulletinColors.modelGoogleTint, ink: BulletinColors.modelGoogleInk),
  _ => (tint: BulletinColors.modelOtherTint, ink: BulletinColors.modelOtherInk),
};

/// The line under a model's name.
String modelDescription(L l, ModelChoice model) {
  if (model.isDefault) return l.modelDefault(model.maker);
  return switch (model.cost) {
    ModelCost.low => l.modelLowCost(model.maker),
    ModelCost.high => l.modelHighCost(model.maker),
  };
}

class ModelPicker extends ConsumerStatefulWidget {
  const ModelPicker({required this.inThread, super.key});

  /// False on Home (sparkle + model name); true in a thread (logo,
  /// "Bulletin", model underneath).
  final bool inThread;

  @override
  ConsumerState<ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends ConsumerState<ModelPicker>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  /// Open/close. A local animation, so plain State (CLAUDE.md, Dart).
  late final AnimationController _menu = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 160),
  )..addStatusListener(_onStatus);

  static const _gap = 8.0;

  /// The menu's top edge on screen, measured from the pill when it opens,
  /// so the menu can scroll instead of running off the bottom.
  double _menuTop = 0;

  bool get _open =>
      _menu.status == AnimationStatus.forward ||
      _menu.status == AnimationStatus.completed;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) _portal.hide();
    setState(() {}); // the chevron and aria-expanded follow the menu
  }

  void _toggle() => _open ? _close() : _show();

  void _show() {
    final reduce = reduceMotionOf(context);
    _menu
      ..duration = reduce ? MotionDurations.reduced : const Duration(milliseconds: 240)
      ..reverseDuration = reduce
          ? MotionDurations.reduced
          : const Duration(milliseconds: 160);
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      _menuTop = box.localToGlobal(Offset(0, box.size.height)).dy + _gap;
    }
    _portal.show();
    _menu.forward();
  }

  void _close() {
    if (_open) _menu.reverse();
  }

  void _pick(ModelChoice model) {
    ref.read(pickedModelProvider.notifier).pick(model.key);
    _close();
  }

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final current = ref.watch(currentModelProvider);
    final offered = ref.watch(modelChoicesProvider).valueOrNull ?? const <ModelChoice>[];

    final pill = widget.inThread
        ? _ThreadPill(model: current, open: _open)
        : _HomePill(model: current, open: _open);

    if (current == null) return pill;

    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => _MenuLayer(
          animation: _menu,
          reduce: reduceMotionOf(context),
          link: _link,
          gap: _gap,
          top: _menuTop,
          offered: offered,
          current: current,
          onPick: _pick,
          onDismiss: _close,
        ),
        child: CompositedTransformTarget(
          link: _link,
          child: Semantics(
            button: true,
            expanded: _open,
            label: l.modelPillLabel(current.name),
            excludeSemantics: true,
            child: PressScale.button(
              child: GestureDetector(
                onTap: _toggle,
                behavior: HitTestBehavior.opaque,
                child: pill,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── pills ────────────────────────────────────────────────────────────────────

class _Chevron extends StatelessWidget {
  const _Chevron({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: open ? 0.5 : 0,
      duration: reduceMotionOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: MotionCurves.out,
      child: LineIcon(
        LineIcons.chevronDown,
        color: BulletinColors.muted,
        size: 14,
        strokeWidth: 2.2,
      ),
    );
  }
}

/// Home: a 34 px circle in the model's tint with its sparkle, the model's
/// name 14/600, the chevron. Without a model: the logo and "Bulletin".
class _HomePill extends StatelessWidget {
  const _HomePill({required this.model, required this.open});

  final ModelChoice? model;
  final bool open;

  static const _radius = BorderRadius.all(Radius.circular(24));

  @override
  Widget build(BuildContext context) {
    final model = this.model;
    final name = model?.name ?? L.of(context).appTitle;
    final Widget badge;
    if (model == null) {
      badge = Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          color: BulletinColors.brand,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const BulletinMark(size: 29),
      );
    } else {
      final tint = modelTint(model);
      badge = Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: tint.tint, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: LineIcon(LineIcons.sparkle, color: tint.ink, size: 14, filled: true),
      );
    }

    return CrystalGlass(
      borderRadius: _radius,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.minTouchTarget),
        child: Padding(
          padding: EdgeInsets.fromLTRB(6, 0, model == null ? 16 : 14, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              badge,
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BulletinText.resolve(BulletinText.pillLabel, name),
                ),
              ),
              if (model != null) _Chevron(open: open),
            ],
          ),
        ),
      ),
    );
  }
}

/// In a thread: the 40 px logo avatar, "Bulletin" over the model's name,
/// the chevron.
class _ThreadPill extends StatelessWidget {
  const _ThreadPill({required this.model, required this.open});

  final ModelChoice? model;
  final bool open;

  static const _radius = BorderRadius.all(Radius.circular(28));

  @override
  Widget build(BuildContext context) {
    final title = L.of(context).appTitle;
    final model = this.model;
    return CrystalGlass(
      borderRadius: _radius,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: BulletinColors.brand,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const BulletinMark(size: 34),
            ),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: BulletinText.resolve(BulletinText.pillTitle, title)),
                  if (model != null)
                    Text(
                      model.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BulletinText.resolve(BulletinText.pillCaption, model.name),
                    ),
                ],
              ),
            ),
            if (model != null) _Chevron(open: open),
          ],
        ),
      ),
    );
  }
}

// ── menu ─────────────────────────────────────────────────────────────────────

/// The scrim and the menu, in the overlay, following the pill.
///
/// In: fade + translateY −6 + scale .96 → 1 from the top-left, 240 ms `out`.
/// Out: to −4 and .97, 160 ms `exit`. The scrim fades with it. Reduced
/// motion: opacity only, 150 ms.
class _MenuLayer extends StatelessWidget {
  const _MenuLayer({
    required this.animation,
    required this.reduce,
    required this.link,
    required this.gap,
    required this.top,
    required this.offered,
    required this.current,
    required this.onPick,
    required this.onDismiss,
  });

  final AnimationController animation;
  final bool reduce;
  final LayerLink link;
  final double gap;

  /// Where the menu starts on screen; it may grow to 16 px above the
  /// bottom inset and scrolls past that.
  final double top;
  final List<ModelChoice> offered;
  final ModelChoice current;
  final ValueChanged<ModelChoice> onPick;
  final VoidCallback onDismiss;

  static const _width = 300.0;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 32).clamp(0.0, _width);
    final maxHeight =
        (screen.height - top - MediaQuery.viewPaddingOf(context).bottom - 16).clamp(
          Sizes.minTouchTarget * 2,
          double.infinity,
        );
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: FadeTransition(
              opacity: animation,
              child: const ColoredBox(color: BulletinColors.menuScrim),
            ),
          ),
        ),
        CompositedTransformFollower(
          link: link,
          targetAnchor: Alignment.bottomLeft,
          offset: Offset(0, gap),
          child: Align(
            alignment: Alignment.topLeft,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final closing = animation.status == AnimationStatus.reverse;
                final t = reduce
                    ? animation.value
                    : closing
                    ? MotionCurves.exit.flipped.transform(animation.value)
                    : MotionCurves.out.transform(animation.value);
                if (reduce) return Opacity(opacity: t, child: child);
                final lift = closing ? -4.0 : -6.0;
                final from = closing ? 0.97 : 0.96;
                return Opacity(
                  opacity: t.clamp(0, 1),
                  child: Transform.translate(
                    offset: Offset(0, lift * (1 - t)),
                    child: Transform.scale(
                      scale: from + (1 - from) * t,
                      alignment: const Alignment(-0.84, -1), // CSS origin 24px 0
                      child: child,
                    ),
                  ),
                );
              },
              child: ConstrainedBox(
                constraints: BoxConstraints.tightFor(
                  width: width,
                ).copyWith(maxHeight: maxHeight),
                child: _Menu(offered: offered, current: current, onPick: onPick),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.offered, required this.current, required this.onPick});

  final List<ModelChoice> offered;
  final ModelChoice current;
  final ValueChanged<ModelChoice> onPick;

  static const _radius = BorderRadius.all(Radius.circular(26));

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final title = l.modelMenuTitle;
    return Semantics(
      label: title,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: _radius,
          gradient: const LinearGradient(
            begin: Alignment(-0.34, -0.94),
            end: Alignment(0.34, 0.94),
            colors: [BulletinColors.menuFillTop, BulletinColors.menuFillBottom],
          ),
          border: Border.all(color: BulletinColors.glassBorder),
          boxShadow: BrandLifts.menu,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 2,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: ExcludeSemantics(
                  child: Text(
                    title.toUpperCase(),
                    style: BulletinText.resolve(BulletinText.menuOverline, title),
                  ),
                ),
              ),
              for (final model in offered)
                _Row(model: model, picked: model == current, onTap: () => onPick(model)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.model, required this.picked, required this.onTap});

  final ModelChoice model;
  final bool picked;
  final VoidCallback onTap;

  static const _radius = BorderRadius.all(Radius.circular(18));
  static const _tile = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    final tint = modelTint(model);
    final description = modelDescription(L.of(context), model);
    return Semantics(
      button: true,
      selected: picked,
      inMutuallyExclusiveGroup: true,
      label: '${model.name}, $description',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: MotionDurations.micro,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          decoration: BoxDecoration(
            borderRadius: _radius,
            color: picked
                ? BulletinColors.menuRowPicked
                : BulletinColors.menuRowPicked.withValues(alpha: 0),
          ),
          child: Row(
            spacing: 12,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: tint.tint, borderRadius: _tile),
                alignment: Alignment.center,
                child: LineIcon(
                  LineIcons.sparkle,
                  color: tint.ink,
                  size: 14,
                  filled: true,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    Text(
                      model.name,
                      style: BulletinText.resolve(BulletinText.menuRowTitle, model.name),
                    ),
                    Text(
                      description,
                      style: BulletinText.resolve(BulletinText.pillCaption, description),
                    ),
                  ],
                ),
              ),
              if (picked)
                LineIcon(
                  LineIcons.check,
                  color: BulletinColors.brandStrong,
                  size: 18,
                  strokeWidth: 2.4,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
