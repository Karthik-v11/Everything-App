import 'package:flutter/material.dart';

/// [FontSize] is the user-selectable text scale (Requirement 20.3).
enum FontSize {
  small(0.9),
  medium(1),
  large(1.15);

  const FontSize(this.scale);

  final double scale;
}

/// [AppTextStyles] builds the app's [TextTheme].
///
/// The typography follows the reference UI, and it is **two families, not
/// three**:
/// - **Outfit** for everything that is words — headings and body alike.
/// - **Monospace** for labels, dates and amounts ("Tasks", "03", "₹15000").
///
/// Outfit is a geometric sans and cannot carry a heading by contrast of family
/// the way the serif it replaces did, so the heading slots buy that contrast
/// with weight and tighter tracking instead (see [heading]). The mono/words
/// split is what the reference UI is actually doing, and it survives.
///
/// Widgets must read styles via `Theme.of(context).textTheme.*` and never
/// construct a [TextStyle] from scratch.
///
/// Neither bundled family carries `₹` (U+20B9), so the platform's own font
/// supplies it and the symbol renders a shade off the digits beside it. Accepted
/// deliberately: it is one glyph, it has always been the case in the mono slots,
/// and the alternative is bundling a third family to draw it. A golden has no
/// platform fallback to reach for, so `₹` records as a tofu box there — the
/// boxes in `test/view/goldens/` are that, not a broken layout.
///
/// DO NOT MODIFY.
class AppTextStyles {
  const AppTextStyles._();

  static const String monoFamily = 'JetBrainsMono';
  static const String sansFamily = 'Outfit';

  /// [heading] is [sans] at the weight and tracking that make a heading read as
  /// one without a second family to lean on.
  static TextStyle heading({
    double size = 24,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: sansFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: -0.4,
      );

  /// [mono] is the label / numeric family.
  static TextStyle mono({
    double size = 13,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double letterSpacing = 0.4,
  }) =>
      TextStyle(
        fontFamily: monoFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  /// [sans] is the body family.
  static TextStyle sans({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: sansFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
      );

  /// [textTheme] maps the two families onto Material 3's slots.
  ///
  /// - `display*` / `headline*` → Outfit, heavy and tight ([heading])
  /// - `title*` / `body*` → Outfit
  /// - `label*` → mono
  ///
  /// [scale] applies the user's [FontSize] preference to every slot at once.
  static TextTheme textTheme({
    required Color primary,
    required Color secondary,
    required double scale,
  }) =>
      TextTheme(
        displayLarge: AppTextStyles.heading(size: 32 * scale, color: primary),
        displayMedium: AppTextStyles.heading(size: 28 * scale, color: primary),
        displaySmall: AppTextStyles.heading(size: 24 * scale, color: primary),
        headlineLarge: AppTextStyles.heading(size: 24 * scale, color: primary),
        headlineMedium: AppTextStyles.heading(size: 21 * scale, color: primary),
        headlineSmall: AppTextStyles.heading(size: 18 * scale, color: primary),
        titleLarge: AppTextStyles.sans(
          size: 17 * scale,
          weight: FontWeight.w600,
          color: primary,
        ),
        titleMedium: AppTextStyles.sans(
          size: 15 * scale,
          weight: FontWeight.w600,
          color: primary,
        ),
        titleSmall: AppTextStyles.sans(
          size: 13 * scale,
          weight: FontWeight.w600,
          color: primary,
        ),
        bodyLarge: AppTextStyles.sans(size: 15 * scale, color: primary),
        bodyMedium: AppTextStyles.sans(size: 14 * scale, color: primary),
        bodySmall: AppTextStyles.sans(size: 12 * scale, color: secondary),
        labelLarge: AppTextStyles.mono(size: 14 * scale, color: primary),
        labelMedium: AppTextStyles.mono(size: 12 * scale, color: secondary),
        labelSmall: AppTextStyles.mono(size: 11 * scale, color: secondary),
      );
}
