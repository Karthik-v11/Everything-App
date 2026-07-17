import 'package:dio/dio.dart';
import 'package:everything_app/core/exceptions/dio_exception.dart';
import 'package:everything_app/core/interceptors/x_client_interceptor.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/weather.dart';

/// [WeatherService] reads the Weather_Service (Requirement 3.2).
///
/// No auth interceptor: OpenWeatherMap authenticates with a query-string key,
/// not a bearer token.
class WeatherService {
  WeatherService({required this.dio}) {
    dio.options
      ..baseUrl = kWeatherURL
      ..connectTimeout = const Duration(seconds: 10)
      ..sendTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 10)
      ..responseType = ResponseType.json
      ..headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

    dio.interceptors.add(XClientInterceptor());
  }

  final Dio dio;

  /// [_query] is what every call sends. Metric units make Celsius the API's job
  /// rather than a conversion the app has to remember.
  Map<String, String> _query(String city) => <String, String>{
        'q': city,
        'appid': kWeatherAPIKey,
        'units': 'metric',
      };

  /// [current] is the conditions the Dashboard pill shows.
  Future<JsonResponse> current({required String city}) async {
    if (kWeatherAPIKey.isEmpty) return _missingKey;

    try {
      final response = await dio.get<Map<String, dynamic>>(
        kCurrentWeatherPath,
        queryParameters: _query(city),
      );

      if (response.statusCode == 200 && response.data != null) {
        return JsonResponse.success(
          message: 'Loaded successfully.',
          data: Weather.fromJson(response.data!),
        );
      }

      return JsonResponse.failure(
        statusCode: response.statusCode ?? 500,
        message: response.data?['message']?.toString() ??
            'Error: could not load the weather.',
      );
    } on DioException catch (error) {
      return JsonResponse.failure(
        statusCode: error.response?.statusCode ?? 500,
        message: DioExceptionOf.exceptionFromDioError(error).errorMessage,
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not load the weather.',
      );
    }
  }

  /// [forecast] is the five-day outlook behind the pill (Requirement 3.3),
  /// already collapsed from three-hourly readings into days.
  Future<JsonResponse> forecast({required String city}) async {
    if (kWeatherAPIKey.isEmpty) return _missingKey;

    try {
      final response = await dio.get<Map<String, dynamic>>(
        kForecastPath,
        queryParameters: _query(city),
      );

      if (response.statusCode == 200 && response.data != null) {
        return JsonResponse.success(
          message: 'Loaded successfully.',
          data: DailyForecast.fromForecastJson(response.data!),
        );
      }

      return JsonResponse.failure(
        statusCode: response.statusCode ?? 500,
        message: response.data?['message']?.toString() ??
            'Error: could not load the forecast.',
      );
    } on DioException catch (error) {
      return JsonResponse.failure(
        statusCode: error.response?.statusCode ?? 500,
        message: DioExceptionOf.exceptionFromDioError(error).errorMessage,
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not load the forecast.',
      );
    }
  }

  /// The app ships without API keys; a build with none is a working app minus its
  /// weather. Saying so beats a timeout the user cannot act on.
  JsonResponse get _missingKey => JsonResponse.failure(
        statusCode: 401,
        message: 'Error: add WEATHER_API_KEY to .env to see the weather.',
      );
}
