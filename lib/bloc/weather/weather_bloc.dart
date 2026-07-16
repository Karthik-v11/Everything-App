import 'dart:async';

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
/// Style A, hydrated — and the hydration **is** the offline cache. The last
/// successful payload is written to storage as part of the state, so a launch
/// with no connection renders the weather it last knew before the first fetch is
/// even attempted, and there is no cache layer anywhere in the app to keep in
/// step with it (Requirement 3.11).
///
/// A failed fetch never clears what is on screen. Offline is the app's normal
/// condition, not an error: the stale reading stays, [WeatherState.isStale] goes
/// true past [kStaleCacheThreshold], and the Dashboard says so quietly rather
/// than throwing the last known weather away and showing nothing.
///
/// The city is the bloc's own state rather than a setting pushed in from
/// [SettingsBloc]: it is the one input a fetch needs, so keeping it here is what
/// lets a rehydrated bloc fetch on launch without waiting to be told where it is.
/// The app asks for no location permission — the user names their city once, and
/// any screen can change it by dispatching [ChangeWeatherCityEvent].
///
/// Events:
/// 1) [FetchWeatherEvent] — refresh the current city. Fired at launch and on pull.
/// 2) [ChangeWeatherCityEvent] — set the city, then refresh it.
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
    // Nothing to fetch until the user has said where they are. This is not an
    // error state: the pill invites them to set it.
    if (state.city.isBlank) return;

    emit(state.copyWith(isLoading: true, error: '', message: ''));

    try {
      // Two calls, one screen: the pill needs the current conditions and the
      // detail screen needs the forecast, and firing them together means opening
      // the detail screen never waits on a request that could have been in flight
      // already.
      final responses = await Future.wait([
        repository.current(city: state.city),
        repository.forecast(city: state.city),
      ]);

      final current = responses.first;
      final forecast = responses.last;

      if (!current.success) {
        // Requirement 3.11: the cache is the answer when the network is not, and
        // it is delivered without an error the user can do nothing about. Only a
        // failure with nothing behind it is worth saying out loud.
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
          // A forecast that failed while the current conditions succeeded leaves
          // the last one standing rather than emptying the detail screen.
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

    // The old city's reading is dropped rather than left on screen under the new
    // city's name — a temperature that belongs to somewhere else is worse than no
    // temperature at all.
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
