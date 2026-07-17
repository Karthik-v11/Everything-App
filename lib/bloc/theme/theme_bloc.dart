import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/app_colors.dart';
import 'package:everything_app/core/utils/app_text_styles.dart';
import 'package:everything_app/core/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'theme_event.dart';
part 'theme_state.dart';

/// [ThemeBloc] owns the user's theme preferences (Requirement 20).
///
/// No repository: the state is the data and [HydratedBloc] persists it, so a
/// service and DAO would add no behaviour.
class ThemeBloc extends HydratedBloc<ThemeEvent, ThemeState> {
  ThemeBloc() : super(const ThemeState()) {
    on<ChangeThemeVariantEvent>(_onChangeThemeVariantEvent);
    on<ChangeAccentColorEvent>(_onChangeAccentColorEvent);
    on<ChangeFontSizeEvent>(_onChangeFontSizeEvent);
  }

  FutureOr<void> _onChangeThemeVariantEvent(
    ChangeThemeVariantEvent event,
    Emitter<ThemeState> emit,
  ) {
    emit(state.copyWith(variant: event.variant));
  }

  FutureOr<void> _onChangeAccentColorEvent(
    ChangeAccentColorEvent event,
    Emitter<ThemeState> emit,
  ) {
    emit(state.copyWith(accentValue: event.accent.toARGB32()));
  }

  FutureOr<void> _onChangeFontSizeEvent(
    ChangeFontSizeEvent event,
    Emitter<ThemeState> emit,
  ) {
    emit(state.copyWith(fontSize: event.fontSize));
  }

  @override
  ThemeState? fromJson(Map<String, dynamic> json) => ThemeState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(ThemeState state) => state.toJson();
}
