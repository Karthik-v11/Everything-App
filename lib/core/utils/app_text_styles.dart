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
/// The typography follows the reference UI:
/// - **Serif** for headings ("Good Morning, Karthik!", "Today").
/// - **Monospace** for labels, dates and amounts ("Tasks", "03", "₹15000").
/// - **Sans** for body copy.
///
/// Widgets must read styles via `Theme.of(context).textTheme.*` and never
/// construct a [TextStyle] from scratch.
///
/// DO NOT MODIFY.
class AppTextStyles {
  const AppTextStyles._();

  static const String serifFamily = 'NotoSerif';
  static const String monoFamily = 'JetBrainsMono';
  static const String sansFamily = 'Inter';

  /// [serif] is the heading family.
  static TextStyle serif({
    double size = 24,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: serifFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
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

  /// [textTheme] maps the three families onto Material 3's slots.
  ///
  /// - `display*` / `headline*` → serif
  /// - `title*` / `body*` → sans
  /// - `label*` → mono
  ///
  /// [scale] applies the user's [FontSize] preference to every slot at once.
  static TextTheme textTheme({
    required Color primary,
    required Color secondary,
    required double scale,
  }) =>
      TextTheme(
        displayLarge: AppTextStyles.serif(size: 32 * scale, color: primary),
        displayMedium: AppTextStyles.serif(size: 28 * scale, color: primary),
        displaySmall: AppTextStyles.serif(size: 24 * scale, color: primary),
        headlineLarge: AppTextStyles.serif(size: 24 * scale, color: primary),
        headlineMedium: AppTextStyles.serif(size: 21 * scale, color: primary),
        headlineSmall: AppTextStyles.serif(size: 18 * scale, color: primary),
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
