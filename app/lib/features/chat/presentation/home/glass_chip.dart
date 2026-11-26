/// A suggestion on Home (prototype `home.chips`): 48 px crystal glass pill,
/// a 32 px peach circle with the icon in brand, the label 14/500 on one line.
///
/// No BackdropFilter: the chips scroll, and a blur inside a scrolling list
/// is exactly what CLAUDE.md #11 forbids. The glass reads from its fill,
/// border and light alone.
library;

import 'package:flutter/material.dart';

import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/crystal_glass.dart';
import '../../../../core/widgets/line_icons.dart';

class GlassChip extends StatelessWidget {
  const GlassChip({
    required this.label,
    required this.glyph,
    required this.onTap,
    super.key,
  });

  final String label;
  final LineGlyph glyph;
  final VoidCallback onTap;

  static const _radius = BorderRadius.all(Radius.circular(24));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PressScale.button(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: CrystalGlass(
            borderRadius: _radius,
            blur: false,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Sizes.minTouchTarget),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.sm,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: BulletinColors.peach,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: LineIcon(
                        glyph,
                        color: BulletinColors.brandStrong,
                        size: 16,
                        strokeWidth: 1.9,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      style: BulletinText.resolve(BulletinText.chipLabel, label),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
