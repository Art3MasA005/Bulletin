/// Where the app is in its launch. Handoff README §6 (`phase`).
enum LaunchPhase {
  /// The splash is on screen and covers everything.
  splash,

  /// The splash is leaving and the app beneath is fading in. Both are
  /// painted; only the app accepts input.
  revealing,

  /// The splash is gone from the tree.
  done,
}
