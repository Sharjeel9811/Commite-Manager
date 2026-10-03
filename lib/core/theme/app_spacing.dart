/// Layout tokens shared by every screen and widget.
///
/// Using a 4pt scale means spacing is consistent everywhere and a redesign is a
/// one-line change rather than an audit of every widget.
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Standard horizontal page padding.
  static const double page = 16;
}

/// Corner radii, aligned to the Material 3 shape scale.
class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}
