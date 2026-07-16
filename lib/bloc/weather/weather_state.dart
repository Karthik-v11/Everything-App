part of 'weather_bloc.dart';

/// [WeatherState] is the weather the app last knew, and when it knew it.
///
/// Every field here is persisted, which is what makes this state the offline
/// cache (Requirement 3.11) rather than something that merely reads one.
class WeatherState extends Equatable {
  const WeatherState({
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.city = '',
    this.weather,
    this.forecast = const <DailyForecast>[],
    this.fetchedAt,
  });

  final bool isLoading;
  final String error;
  final String message;

  /// The place the weather is about. Empty until the user names it.
  final String city;

  final Weather? weather;
  final List<DailyForecast> forecast;

  /// When the reading in this state arrived — not when it was *observed*, which
  /// is [Weather.observedAt]. Staleness is about the app's knowledge, not the
  /// weather station's.
  final DateTime? fetchedAt;

  bool get hasCity => city.isNotBlank;

  bool get hasData => weather != null;

  /// [isStale] is true when the cached reading is older than
  /// [kStaleCacheThreshold] — the one condition under which the Dashboard tells
  /// the user it is showing saved data. Anything fresher is shown without comment.
  bool get isStale {
    final at = fetchedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) > kStaleCacheThreshold;
  }

  /// [age] is how long ago the reading arrived, in the words the banner uses.
  String get age {
    final at = fetchedAt;
    if (at == null) return '';

    final elapsed = DateTime.now().difference(at);
    if (elapsed.inDays > 0) return '${elapsed.inDays}d ago';
    if (elapsed.inHours > 0) return '${elapsed.inHours}h ago';
    if (elapsed.inMinutes > 0) return '${elapsed.inMinutes}m ago';
    return 'just now';
  }

  WeatherState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    String? city,
    Weather? weather,
    bool clearWeather = false,
    List<DailyForecast>? forecast,
    DateTime? fetchedAt,
    bool clearFetchedAt = false,
  }) =>
      WeatherState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        city: city ?? this.city,
        weather: clearWeather ? null : (weather ?? this.weather),
        forecast: forecast ?? this.forecast,
        fetchedAt: clearFetchedAt ? null : (fetchedAt ?? this.fetchedAt),
      );

  factory WeatherState.fromJson(Map<String, dynamic> json) => WeatherState(
        city: json['HydratedCity']?.toString() ?? '',
        weather: json['HydratedWeather'] == null
            ? null
            : Weather.fromJson(
                json['HydratedWeather'] as Map<String, dynamic>,
              ),
        forecast: [
          for (final day in json['HydratedForecast'] as List? ?? const [])
            if (day is Map<String, dynamic>) DailyForecast.fromJson(day),
        ],
        fetchedAt: DateTime.tryParse('${json['HydratedFetchedAt']}'),
      );

  Map<String, dynamic> toJson() => {
        'HydratedCity': city,
        'HydratedWeather': weather?.toJson(),
        'HydratedForecast': [
          for (final day in forecast) day.toJson(),
        ],
        'HydratedFetchedAt': fetchedAt?.toIso8601String(),
      };

  @override
  List<Object?> get props => [
        isLoading,
        error,
        message,
        city,
        weather,
        forecast,
        fetchedAt,
      ];
}
