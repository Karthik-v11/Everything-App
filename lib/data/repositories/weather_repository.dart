import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/services/weather_service.dart';

/// [WeatherRepository] defines the contract for weather data.
abstract class WeatherRepository {
  /// [current] is the conditions now, for [city].
  Future<JsonResponse> current({required String city});

  /// [forecast] is the coming days for [city], one entry per day.
  Future<JsonResponse> forecast({required String city});
}

class WeatherRepositoryImpl implements WeatherRepository {
  const WeatherRepositoryImpl({required this.weatherService});

  final WeatherService weatherService;

  @override
  Future<JsonResponse> current({required String city}) =>
      weatherService.current(city: city);

  @override
  Future<JsonResponse> forecast({required String city}) =>
      weatherService.forecast(city: city);
}
