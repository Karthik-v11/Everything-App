part of 'theme_bloc.dart';

/// [ThemeState] holds the user's three theme preferences (Requirement 20).
///
/// [variant] is the selected theme; [AppThemeVariant.system] defers to the
/// device.
/// [accentValue] is the accent colour as a 32-bit ARGB int — stored as an int
/// rather than a [Color] so it round-trips cleanly through JSON.
/// [fontSize] is the global text scale.
///
/// The app is dark-first, so the defaults are dark + amber + medium.
class ThemeState extends Equatable {
  const ThemeState({
    this.variant = AppThemeVariant.dark,
    this.accentValue = _defaultAccent,
    this.fontSize = FontSize.medium,
  });

  static const int _defaultAccent = 0xFFFFB300; // AppColors.amber

  final AppThemeVariant variant;
  final int accentValue;
  final FontSize fontSize;

  /// [accent] is [accentValue] as a usable [Color].
  Color get accent => Color(accentValue);

  /// [themeData] is the [ThemeData] for these preferences.
  ///
  /// [platformBrightness] is only used when [variant] is
  /// [AppThemeVariant.system].
  ThemeData themeData(Brightness platformBrightness) => AppTheme.build(
        variant: variant,
        accent: accent,
        fontSize: fontSize,
        platformBrightness: platformBrightness,
      );

  ThemeState copyWith({
    AppThemeVariant? variant,
    int? accentValue,
    FontSize? fontSize,
  }) =>
      ThemeState(
        variant: variant ?? this.variant,
        accentValue: accentValue ?? this.accentValue,
        fontSize: fontSize ?? this.fontSize,
      );

  /// [fromJson] restores the preferences after a restart. Every field falls back
  /// to its default, so a corrupt or partial payload degrades to the dark theme
  /// rather than crashing the app on launch.
  factory ThemeState.fromJson(Map<String, dynamic> json) => ThemeState(
        variant: AppThemeVariant.values.firstWhere(
          (e) => e.name == json['HydratedVariant'],
          orElse: () => AppThemeVariant.dark,
        ),
        accentValue:
            int.tryParse('${json['HydratedAccent']}') ?? _defaultAccent,
        fontSize: FontSize.values.firstWhere(
          (e) => e.name == json['HydratedFontSize'],
          orElse: () => FontSize.medium,
        ),
      );

  Map<String, dynamic> toJson() => {
        'HydratedVariant': variant.name,
        'HydratedAccent': accentValue,
        'HydratedFontSize': fontSize.name,
      };

  @override
  List<Object> get props => [variant, accentValue, fontSize];
}
