/// The Welcome hero's drifting clouds (prototype `ab.welcome`), as data.
library;

import 'package:flutter/widgets.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/drifting_clouds.dart';

const welcomeClouds = CloudScene(
  clouds: [
    DriftCloud(
      shape: CloudShape.wide,
      rect: Rect.fromLTWH(40, 36, 170, 51),
      opacity: 0.55,
      top: BulletinColors.cloudFarTop,
      bottom: BulletinColors.cloudFarBottom,
      from: -210,
      to: 350,
      pace: CloudPace.far,
    ),
    DriftCloud(
      shape: CloudShape.big,
      rect: Rect.fromLTWH(150, 64, 250, 100),
      opacity: 1,
      top: BulletinColors.cloudNearTop,
      bottom: BulletinColors.cloudNearBottom,
      from: -400,
      to: 240,
      pace: CloudPace.near,
    ),
    DriftCloud(
      shape: CloudShape.big,
      rect: Rect.fromLTWH(-50, 150, 210, 84),
      opacity: 0.9,
      top: BulletinColors.cloudMidTop,
      bottom: BulletinColors.cloudMidBottom,
      from: -160,
      to: 440,
      pace: CloudPace.mid,
    ),
    DriftCloud(
      shape: CloudShape.small,
      rect: Rect.fromLTWH(250, 226, 120, 60),
      opacity: 0.8,
      top: BulletinColors.cloudNearTop,
      bottom: BulletinColors.cloudSmallBottom,
      from: -370,
      to: 140,
      pace: CloudPace.small,
    ),
  ],
);
