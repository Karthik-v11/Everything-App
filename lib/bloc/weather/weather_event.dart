part of 'weather_bloc.dart';

/// [WeatherEvent] is the base class for every weather event.
abstract class WeatherEvent extends Equatable {
  const WeatherEvent();

  @override
  List<Object?> get props => [];
}

/// [FetchWeatherEvent] refreshes the current city. No-ops while no city is set,
/// so it is always safe to fire.
class FetchWeatherEvent extends WeatherEvent {
  const FetchWeatherEvent();
}

/// [ChangeWeatherCityEvent] sets the city, then fetches it. [city] must be a
/// name the weather API can resolve — `Bengaluru`, or `Springfield,US` where the
/// name alone is ambiguous.
class ChangeWeatherCityEvent extends WeatherEvent {
  const ChangeWeatherCityEvent({required this.city});

  final String city;

  @override
  List<Object?> get props => [city];
}
