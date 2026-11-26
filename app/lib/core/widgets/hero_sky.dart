/// The hero sky: the splash's static clouds, arc and sparkles. The Welcome
/// hero shares the arc and sparkles but has drifting clouds instead
/// (CHANGES.md), so those two are exported on their own as [heroSkyDetails].
/// Pure data, in the prototype's 390-wide design frame; [BrandSky] paints it.
library;

import 'package:flutter/widgets.dart';

import 'brand_sky.dart';

const heroSky = SkyScene(
  clouds: [
    // Upper right: the prototype's 250x110 box at (150, 64).
    SkyCloud(
      base: Rect.fromLTRB(150, 118, 400, 174),
      puffs: [(Offset(220, 110), 42), (Offset(282, 104), 40), (Offset(341, 125), 33)],
    ),
    // Left, bleeding off the edge: 210x96 at (-50, 150).
    SkyCloud(
      base: Rect.fromLTRB(-50, 196, 160, 246),
      puffs: [(Offset(32, 188), 38), (Offset(85, 201), 31)],
    ),
  ],
  arcs: _arcs,
  sparkles: _sparkles,
);

/// The hero without its clouds.
const heroSkyDetails = SkyScene(arcs: _arcs, sparkles: _sparkles);

// M-10 40 Q195 120 400 30, drawn at y = 300.
const _arcs = <SkyArc>[(Offset(-10, 340), Offset(195, 420), Offset(400, 330))];

const _sparkles = <SkySparkle>[
  (Offset(36, 96), 14),
  (Offset(210, 206), 22),
  (Offset(40, 262), 16),
  (Offset(318, 290), 12),
  (Offset(336, 190), 10),
];
