part of 'theme_bloc.dart';

/// [ThemeEvent] is the base class for every theme preference change.
abstract class ThemeEvent extends Equatable {
  const ThemeEvent();

  @override
  List<Object> get props => [];
}

/// [ChangeThemeVariantEvent] switches between dark, light, AMOLED and system.
/// [variant] is the newly selected theme.
class ChangeThemeVariantEvent extends ThemeEvent {
  const ChangeThemeVariantEvent({required this.variant});

  final AppThemeVariant variant;

  @override
  List<Object> get props => [variant];
}

/// [ChangeAccentColorEvent] sets the accent used across the app.
/// [accent] may be one of [AppColors.accents] or a user-defined custom colour.
class ChangeAccentColorEvent extends ThemeEvent {
  const ChangeAccentColorEvent({required this.accent});

  final Color accent;

  @override
  List<Object> get props => [accent];
}

/// [ChangeFontSizeEvent] sets the global text scale.
/// [fontSize] is the newly selected size.
class ChangeFontSizeEvent extends ThemeEvent {
  const ChangeFontSizeEvent({required this.fontSize});

  final FontSize fontSize;

  @override
  List<Object> get props => [fontSize];
}
