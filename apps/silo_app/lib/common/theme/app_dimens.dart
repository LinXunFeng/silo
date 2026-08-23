/// The spacing scale every gap in the app is drawn from.
///
/// One scale rather than ad-hoc numbers is what makes a screen read as
/// deliberate: gaps that differ by two pixels look like a mistake, gaps that
/// differ by a step look like a hierarchy.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii, from a control to a full pill.
class AppRadius {
  const AppRadius._();

  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double pill = 999;
}

/// Fixed sizes that recur across the window.
class AppSizes {
  const AppSizes._();

  static const double progressBarHeight = 5;

  /// The gutter a pulldown menu keeps for its tick mark.
  static const double menuMarkWidth = 12;

  static const double sidebarMinWidth = 232;
  static const double sidebarStartWidth = 248;

  /// Wide enough for a repository id, narrow enough that lines of metadata
  /// stay readable rather than stretching across a maximised window.
  static const double contentMaxWidth = 760;
}
