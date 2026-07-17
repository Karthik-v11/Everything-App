part of 'theme_bloc.dart';

/// [ThemeState] holds the user's three theme preferences (Requirement 20).
///
/// [accentValue] is a 32-bit ARGB int rather than a [Color] so it round-trips
/// cleanly through JSON. The app is dark-first, hence the dark + red + medium
/// defaults.
class ThemeState extends Equatable {
  const ThemeState({
    this.variant = AppThemeVariant.dark,
    this.accentValue = _defaultAccent,
    this.fontSize = FontSize.medium,
  });

  static const int _defaultAccent = 0xFFE8453C; // AppColors.red

  final AppThemeVariant variant;
  final int accentValue;
  final FontSize fontSize;

  Color get accent => Color(accentValue);

  /// [platformBrightness] is used only when [variant] is [AppThemeVariant.system].
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

  /// Every field falls back to its default, so a corrupt or partial payload
  /// degrades to the dark theme rather than crashing on launch.
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
