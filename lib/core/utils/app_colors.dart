import 'package:flutter/material.dart';

/// [AppColors] holds every raw colour value used by the app.
///
/// Nothing outside of [AppTheme] should read from this class directly — widgets
/// must go through `Theme.of(context).colorScheme` so that theme switching and
/// custom accent colours keep working.
///
/// DO NOT MODIFY.
class AppColors {
  const AppColors._();

  // Dark (default) surfaces — sampled from the reference UI.
  static const Color darkBackground = Color(0xFF0F0F0F);
  static const Color darkSurface = Color(0xFF1C1C1C);
  static const Color darkSurfaceHigh = Color(0xFF262626);
  static const Color darkDivider = Color(0xFF2A2A2A);

  // AMOLED — true black, cards lifted just enough to be visible.
  static const Color amoledBackground = Color(0xFF000000);
  static const Color amoledSurface = Color(0xFF121212);
  static const Color amoledDivider = Color(0xFF1F1F1F);

  // Light surfaces.
  static const Color lightBackground = Color(0xFFF7F6F3);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightDivider = Color(0xFFE3E1DC);

  // Text.
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF8E8E8E);
  static const Color darkTextTertiary = Color(0xFF5C5C5C);
  static const Color lightTextPrimary = Color(0xFF151515);
  static const Color lightTextSecondary = Color(0xFF5F5F5F);
  static const Color lightTextTertiary = Color(0xFF9A9A9A);

  // Accents — selectable in Settings (Requirement 20.2).
  static const Color amber = Color(0xFFFFB300);
  static const Color blue = Color(0xFF2C6BED);
  static const Color green = Color(0xFF2FA84F);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color red = Color(0xFFE8453C);
  static const Color orange = Color(0xFFF5622D);
  static const Color rose = Color(0xFFF43F5E);
  static const Color pink = Color(0xFFEC4899);
  static const Color indigo = Color(0xFF6366F1);
  static const Color cyan = Color(0xFF06B6D4);
  static const Color teal = Color(0xFF14B8A6);
  static const Color lime = Color(0xFF84CC16);
  static const Color slate = Color(0xFF64748B);

  /// [accents] is the palette shown in the theme picker, ordered around the
  /// colour wheel so the grid reads as a spectrum rather than a bag of swatches.
  /// [slate] closes it: it is the one neutral, for a UI that wants no hue at all.
  static const Map<String, Color> accents = <String, Color>{
    'Red': red,
    'Rose': rose,
    'Pink': pink,
    'Orange': orange,
    'Amber': amber,
    'Lime': lime,
    'Green': green,
    'Teal': teal,
    'Cyan': cyan,
    'Blue': blue,
    'Indigo': indigo,
    'Purple': purple,
    'Slate': slate,
  };

  // Semantic.
  static const Color error = Color(0xFFE5484D);
  static const Color success = Color(0xFF2FA84F);
  static const Color warning = Color(0xFFF5A524);
  static const Color overdue = Color(0xFFE5533D);
  static const Color category = Color(0xFF6366F1);

  // Task priority (Requirement 4.4) — low, medium, high, critical.
  static const Color priorityLow = Color(0xFF4FC3C7);
  static const Color priorityMedium = Color(0xFFFFB300);
  static const Color priorityHigh = Color(0xFFF5622D);
  static const Color priorityCritical = Color(0xFFE8453C);

  /// [chartPalette] is the fixed ordering used by every finance chart so that a
  /// category keeps the same colour across the pie, the trend line and the bars.
  static const List<Color> chartPalette = <Color>[
    Color(0xFFE8453C),
    Color(0xFFF5C518),
    Color(0xFFF5622D),
    Color(0xFF2C6BED),
    Color(0xFF4FC3C7),
    Color(0xFF8B5CF6),
    Color(0xFF2FA84F),
    Color(0xFFEC4899),
  ];
}
