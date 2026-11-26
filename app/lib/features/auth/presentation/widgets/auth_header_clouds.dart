/// The orange header's drifting clouds and twinkling sparkles, shared by
/// Sign in and Sign up (prototype `ab.signin`, `ab.create`: the same four
/// clouds and three sparkles), as data.
library;

import 'package:flutter/widgets.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/drifting_clouds.dart';

const authHeaderClouds = CloudScene(
  clouds: [
    DriftCloud(
      shape: CloudShape.wide,
      rect: Rect.fromLTWH(150, 14, 150, 45),
      opacity: 0.55,
      top: BulletinColors.cloudFarTop,
      bottom: BulletinColors.cloudFarBottom,
      from: -300,
      to: 240,
      pace: CloudPace.far,
    ),
    DriftCloud(
      shape: CloudShape.big,
      rect: Rect.fromLTWH(190, 40, 210, 84),
      opacity: 1,
      top: BulletinColors.cloudNearTop,
      bottom: BulletinColors.cloudNearBottom,
      from: -400,
      to: 200,
      pace: CloudPace.near,
    ),
    DriftCloud(
      shape: CloudShape.small,
      rect: Rect.fromLTWH(30, 148, 130, 65),
      opacity: 0.8,
      top: BulletinColors.cloudMidTop,
      bottom: BulletinColors.cloudMidBottom,
      from: -160,
      to: 360,
      pace: CloudPace.mid,
    ),
    DriftCloud(
      shape: CloudShape.wide,
      rect: Rect.fromLTWH(280, 196, 110, 33),
      opacity: 0.7,
      top: BulletinColors.cloudNearTop,
      bottom: BulletinColors.cloudSmallBottom,
      from: -390,
      to: 110,
      pace: CloudPace.small,
    ),
  ],
  // Prototype `si.tw1..3`.
  twinkles: [
    (origin: Offset(300, 150), side: 14, period: 4, headStart: 0),
    (origin: Offset(64, 26), side: 10, period: 5, headStart: 1.5),
    (origin: Offset(348, 104), side: 9, period: 3.6, headStart: 2.4),
  ],
);
