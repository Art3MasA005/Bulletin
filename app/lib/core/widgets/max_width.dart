/// A width cap that also holds when Flutter measures in advance.
///
/// `ConstrainedBox(maxWidth: …)` caps layout, but its intrinsic-height
/// answer measures the child at the full incoming width. Text that wraps to
/// three lines at 210 px then reports two, and any scroll view that sizes
/// itself from intrinsics (`SliverFillRemaining(hasScrollBody: false)`)
/// comes out short and overflows. This widget caps both. Its child sits at
/// the start edge, as a CSS `max-width` block does.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class MaxWidth extends SingleChildRenderObjectWidget {
  const MaxWidth({required this.maxWidth, required super.child, super.key});

  final double maxWidth;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMaxWidth(maxWidth, Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMaxWidth)
      ..maxWidth = maxWidth
      ..textDirection = Directionality.of(context);
  }
}

class _RenderMaxWidth extends RenderShiftedBox {
  _RenderMaxWidth(this._maxWidth, this._textDirection) : super(null);

  double _maxWidth;
  set maxWidth(double value) {
    if (value == _maxWidth) return;
    _maxWidth = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  double _cap(double width) => math.min(width, _maxWidth);

  @override
  double computeMinIntrinsicHeight(double width) =>
      child?.getMinIntrinsicHeight(_cap(width)) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      child?.getMaxIntrinsicHeight(_cap(width)) ?? 0;

  @override
  double computeMinIntrinsicWidth(double height) =>
      _cap(child?.getMinIntrinsicWidth(height) ?? 0);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _cap(child?.getMaxIntrinsicWidth(height) ?? 0);

  BoxConstraints _childConstraints(BoxConstraints constraints) => BoxConstraints(
    maxWidth: _cap(constraints.maxWidth),
    maxHeight: constraints.maxHeight,
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final childSize = child?.getDryLayout(_childConstraints(constraints)) ?? Size.zero;
    return constraints.constrain(Size(constraints.maxWidth, childSize.height));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(
      Size(
        constraints.hasBoundedWidth ? constraints.maxWidth : child.size.width,
        child.size.height,
      ),
    );
    final dx = _textDirection == TextDirection.rtl ? size.width - child.size.width : 0.0;
    (child.parentData! as BoxParentData).offset = Offset(dx, 0);
  }
}
