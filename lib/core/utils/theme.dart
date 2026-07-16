import 'package:everything_app/core/utils/app_colors.dart';
import 'package:everything_app/core/utils/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// [AppThemeVariant] is the user-selectable theme (Requirement 20.1).
///
/// [system] resolves to [dark] or [light] using the device brightness.
enum AppThemeVariant { dark, light, amoled, system }

/// [AppTheme] builds a Material 3 [ThemeData] from the user's theme settings.
///
/// It is a pure function of (variant, accent, fontSize) — calling [build] with
/// new settings and handing the result to [MaterialApp] is all that is needed to
/// re-theme the app, with no restart (Requirement 20.4).
///
/// DO NOT MODIFY.
class AppTheme {
  const AppTheme._();

  /// [build] returns the [ThemeData] for the given settings.
  ///
  /// [platformBrightness] is only consulted when [variant] is
  /// [AppThemeVariant.system].
  static ThemeData build({
    required AppThemeVariant variant,
    required Color accent,
    required FontSize fontSize,
    Brightness platformBrightness = Brightness.dark,
  }) {
    final resolved = _resolve(variant, platformBrightness);
    final isDark = resolved != AppThemeVariant.light;

    final background = switch (resolved) {
      AppThemeVariant.amoled => AppColors.amoledBackground,
      AppThemeVariant.light => AppColors.lightBackground,
      _ => AppColors.darkBackground,
    };
    final surface = switch (resolved) {
      AppThemeVariant.amoled => AppColors.amoledSurface,
      AppThemeVariant.light => AppColors.lightSurface,
      _ => AppColors.darkSurface,
    };
    final divider = switch (resolved) {
      AppThemeVariant.amoled => AppColors.amoledDivider,
      AppThemeVariant.light => AppColors.lightDivider,
      _ => AppColors.darkDivider,
    };

    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    // The accent is a strong amber/red; black foreground reads better on it than
    // white at every accent in the palette.
    const onAccent = Color(0xFF141414);

    final colorScheme = ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: surface,
      onPrimaryContainer: textPrimary,
      secondary: textSecondary,
      onSecondary: background,
      error: AppColors.error,
      onError: Colors.white,
      surface: background,
      onSurface: textPrimary,
      surfaceContainer: surface,
      surfaceContainerHigh:
          isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurface,
      onSurfaceVariant: textSecondary,
      outline: divider,
      outlineVariant: divider,
    );

    final textTheme = AppTextStyles.textTheme(
      primary: textPrimary,
      secondary: textSecondary,
      scale: fontSize.scale,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      dividerColor: divider,
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        shape: const CircleBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.darkSurfaceHigh : textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isDark ? textPrimary : AppColors.lightBackground,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        side: BorderSide(color: divider),
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: textSecondary, width: 1.6),
        shape: const CircleBorder(),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(onAccent),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: divider,
        circularTrackColor: divider,
      ),
    );
  }

  static AppThemeVariant _resolve(
    AppThemeVariant variant,
    Brightness platformBrightness,
  ) =>
      variant == AppThemeVariant.system
          ? (platformBrightness == Brightness.dark
              ? AppThemeVariant.dark
              : AppThemeVariant.light)
          : variant;
}
