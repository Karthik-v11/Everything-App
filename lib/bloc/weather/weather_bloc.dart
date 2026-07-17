import 'dart:async';

import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/models/weather.dart';
import 'package:everything_app/data/repositories/weather_repository.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'weather_event.dart';
part 'weather_state.dart';

/// [WeatherBloc] owns the Dashboard's weather (Requirements 3.2, 3.3, 3.11).
///
/// The hydrated state *is* the offline cache (Requirement 3.11) — there is no
/// separate cache layer. A failed fetch never clears what is on screen: the
/// stale reading stays and [WeatherState.isStale] goes true past
/// [kStaleCacheThreshold].
///
/// The city lives here rather than in [SettingsBloc] so a rehydrated bloc can
/// fetch on launch without waiting to be told where it is. The app asks for no
/// location permission.
class WeatherBloc extends HydratedBloc<WeatherEvent, WeatherState> {
  WeatherBloc({required this.repository}) : super(const WeatherState()) {
    on<FetchWeatherEvent>(_onFetchWeatherEvent);
    on<ChangeWeatherCityEvent>(_onChangeWeatherCityEvent);
  }

  final WeatherRepository repository;

  FutureOr<void> _onFetchWeatherEvent(
    FetchWeatherEvent event,
    Emitter<WeatherState> emit,
  ) async {
    // No city set yet is not an error state — the pill invites them to set it.
    if (state.city.isBlank) return;

    emit(state.copyWith(isLoading: true, error: '', message: ''));

    try {
      // Fired together so opening the detail screen never waits on the forecast.
      final responses = await Future.wait([
        repository.current(city: state.city),
        repository.forecast(city: state.city),
      ]);

      final current = responses.first;
      final forecast = responses.last;

      if (!current.success) {
        // Requirement 3.11: surface the error only when there is no cached
        // reading to fall back on.
        emit(
          state.copyWith(
            isLoading: false,
            error: state.hasData ? '' : current.message,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          isLoading: false,
          weather: current.data! as Weather,
          // A failed forecast keeps the last one rather than emptying the screen.
          forecast: forecast.success
              ? forecast.data! as List<DailyForecast>
              : state.forecast,
          fetchedAt: DateTime.now(),
          error: '',
        ),
      );
    } on Exception {
      emit(
        state.copyWith(
          isLoading: false,
          error: state.hasData ? '' : 'Could not load the weather.',
        ),
      );
    }
  }

  FutureOr<void> _onChangeWeatherCityEvent(
    ChangeWeatherCityEvent event,
    Emitter<WeatherState> emit,
  ) {
    final city = event.city.trim();
    if (city.isEmpty || city == state.city) return null;

    // Drop the old city's reading so it is never shown under the new city's name.
    emit(
      state.copyWith(
        city: city,
        clearWeather: true,
        forecast: const [],
        clearFetchedAt: true,
        error: '',
      ),
    );

    add(const FetchWeatherEvent());
  }

  @override
  WeatherState? fromJson(Map<String, dynamic> json) =>
      WeatherState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(WeatherState state) => state.toJson();
}
