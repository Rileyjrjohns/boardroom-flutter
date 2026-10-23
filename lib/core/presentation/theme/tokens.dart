import 'dart:ui';

// Design tokens. This is the only place where raw colours are written. Light
// theme only, like the React Native app (it locks the light appearance).

/// The colours of the app.
abstract final class AppColors {
  /// The background of the screens.
  static const Color background = Color(0xFFFFFFFF);

  /// The background of cards, bars and read-only fields.
  static const Color surface = Color(0xFFF4F5F7);

  /// The hairline between rows and around cards.
  static const Color border = Color(0xFFD6D9DF);

  /// The edge of what the user operates; at least 3:1 against the background
  /// (WCAG 1.4.11), which [border] does not reach.
  static const Color interactiveBorder = Color(0xFF767676);

  /// The main text.
  static const Color textPrimary = Color(0xFF111111);

  /// The secondary text.
  static const Color textSecondary = Color(0xFF555555);

  /// The main action.
  static const Color primary = Color(0xFF1B4F8F);

  /// The text on [primary].
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Errors and destructive actions.
  static const Color danger = Color(0xFFA3001D);

  /// The background of banners.
  static const Color warningBackground = Color(0xFFFFF3CD);

  /// The text of banners.
  static const Color warningText = Color(0xFF5B4200);

  /// The neutral badge.
  static const Color neutralBadgeBackground = Color(0xFFE6E8EC);

  /// The text of the neutral badge.
  static const Color neutralBadgeText = Color(0xFF2E3138);

  /// The positive badge.
  static const Color positiveBadgeBackground = Color(0xFFDFF3E4);

  /// The text of the positive badge.
  static const Color positiveBadgeText = Color(0xFF14532B);

  /// The confidential badge.
  static const Color confidentialBadgeBackground = Color(0xFFFDE2E5);

  /// The text of the confidential badge.
  static const Color confidentialBadgeText = Color(0xFF7A1424);

  /// The text of the watermark: dark, made faint by [Watermark.opacity].
  static const Color watermarkText = Color(0xFF1F2933);

  /// Behind the page of a document.
  static const Color documentBackdrop = Color(0xFFE4E7EC);
}

/// The spacing scale, in logical pixels.
abstract final class AppSpacing {
  /// 4.
  static const double xs = 4;

  /// 8.
  static const double sm = 8;

  /// 12.
  static const double md = 12;

  /// 16.
  static const double lg = 16;

  /// 24.
  static const double xl = 24;
}

/// The font sizes.
abstract final class AppFontSizes {
  /// Captions and banners.
  static const double caption = 13;

  /// Body text.
  static const double body = 16;

  /// Sub titles.
  static const double subtitle = 18;

  /// Titles.
  static const double title = 24;
}

/// The corner radii.
abstract final class AppRadii {
  /// Small.
  static const double sm = 6;

  /// Medium.
  static const double md = 12;

  /// A pill.
  static const double pill = 999;
}

/// Sizes of things the user touches and lays out.
abstract final class AppSizes {
  /// The smallest size of anything that can be tapped.
  static const double touchTargetMin = 44;

  /// The width of a hairline.
  static const double hairline = 1;

  /// The widest a form gets, so that it stays readable on a tablet.
  static const double formMaxWidth = 480;

  /// The widest a dialog gets.
  static const double dialogMaxWidth = 420;
}

/// Opacities.
abstract final class AppOpacity {
  /// How faded a pressed element is.
  static const double pressed = 0.6;

  /// How faded a control that cannot be used is.
  static const double disabled = 0.4;

  /// How much of the screen shows through behind a dialog.
  static const double dimmed = 0.55;
}

/// The watermark drawn over a document (docs/spec/screens.md "Watermark").
abstract final class Watermark {
  /// How much of the page shows through.
  static const double opacity = 0.16;

  /// The slope of the lines of text, in degrees: negative rises to the right.
  static const double angleDegrees = -30;

  /// The width of a tile.
  static const double tileWidth = 240;

  /// The height of a tile.
  static const double tileHeight = 96;

  /// The font size.
  static const double fontSize = 13;
}
