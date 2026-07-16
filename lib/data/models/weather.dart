import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// [WeatherCondition] is the weather in one word, and the icon that draws it.
///
/// It is derived from the OpenWeatherMap icon code rather than from the
/// condition text: the code is a closed set of nine states, and the text is a
/// free-form English string that changes with the API's locale.
enum WeatherCondition {
  clear(Icons.wb_sunny_rounded),
  fewClouds(Icons.wb_cloudy_outlined),
  clouds(Icons.cloud_rounded),
  rain(Icons.water_drop_rounded),
  showers(Icons.grain_rounded),
  thunderstorm(Icons.thunderstorm_rounded),
  snow(Icons.ac_unit_rounded),
  mist(Icons.foggy),
  unknown(Icons.thermostat_rounded);

  const WeatherCondition(this.icon);

  final IconData icon;

  /// [fromIconCode] maps an OpenWeatherMap icon code (`01d`, `10n`) onto a
  /// condition. The trailing `d`/`n` is the day/night variant and is dropped —
  /// the app draws one icon per condition.
  static WeatherCondition fromIconCode(String? code) {
    if (code == null || code.length < 2) return WeatherCondition.unknown;

    return switch (code.substring(0, 2)) {
      '01' => WeatherCondition.clear,
      '02' => WeatherCondition.fewClouds,
      '03' || '04' => WeatherCondition.clouds,
      '09' => WeatherCondition.showers,
      '10' => WeatherCondition.rain,
      '11' => WeatherCondition.thunderstorm,
      '13' => WeatherCondition.snow,
      '50' => WeatherCondition.mist,
      _ => WeatherCondition.unknown,
    };
  }
}

/// [Weather] is the current conditions for one place (Requirement 3.2).
///
/// Temperatures are Celsius: the service asks the API for metric units, so no
/// conversion happens anywhere in the app.
class Weather extends Equatable {
  const Weather({
    required this.city,
    required this.temperatureC,
    required this.feelsLikeC,
    required this.iconCode,
    required this.description,
    required this.humidity,
    required this.windSpeedMs,
    required this.observedAt,
  });

  final String city;
  final double temperatureC;
  final double feelsLikeC;

  /// The raw OpenWeatherMap icon code. Stored rather than the resolved
  /// [WeatherCondition] so that a cached payload survives a change to the
  /// mapping.
  final String iconCode;

  final String description;
  final int humidity;
  final double windSpeedMs;
  final DateTime observedAt;

  WeatherCondition get condition => WeatherCondition.fromIconCode(iconCode);

  /// [temperature] is the figure on the pill: `27°`.
  String get temperature => '${temperatureC.round()}°';

  String get feelsLike => '${feelsLikeC.round()}°';

  /// [windSpeed] is metres per second rendered as km/h, which is how wind is
  /// read everywhere the app is used.
  String get windSpeed => '${(windSpeedMs * 3.6).round()} km/h';

  factory Weather.fromJson(Map<String, dynamic> json) {
    final main = json['main'] as Map<String, dynamic>? ?? const {};
    final wind = json['wind'] as Map<String, dynamic>? ?? const {};

    // `weather` is a list, and OpenWeatherMap documents the first entry as the
    // primary condition.
    final conditions = json['weather'] as List?;
    final condition = conditions == null || conditions.isEmpty
        ? const <String, dynamic>{}
        : conditions.first as Map<String, dynamic>;

    return Weather(
      city: json['name']?.toString() ?? '',
      temperatureC: num.tryParse('${main['temp']}')?.toDouble() ?? 0,
      feelsLikeC: num.tryParse('${main['feels_like']}')?.toDouble() ?? 0,
      iconCode: condition['icon']?.toString() ?? '',
      description: condition['description']?.toString() ?? '',
      humidity: int.tryParse('${main['humidity']}') ?? 0,
      windSpeedMs: num.tryParse('${wind['speed']}')?.toDouble() ?? 0,
      observedAt: _timestamp(json['dt']),
    );
  }

  /// [toJson] is the shape [Weather.fromJson] reads, not the API's — this is what
  /// [WeatherBloc] hydrates, and a payload written by one build has to be
  /// readable by the next.
  Map<String, dynamic> toJson() => {
        'name': city,
        'main': {
          'temp': temperatureC,
          'feels_like': feelsLikeC,
          'humidity': humidity,
        },
        'weather': [
          {'icon': iconCode, 'description': description},
        ],
        'wind': {'speed': windSpeedMs},
        'dt': observedAt.millisecondsSinceEpoch ~/ 1000,
      };

  Weather copyWith({
    String? city,
    double? temperatureC,
    double? feelsLikeC,
    String? iconCode,
    String? description,
    int? humidity,
    double? windSpeedMs,
    DateTime? observedAt,
  }) =>
      Weather(
        city: city ?? this.city,
        temperatureC: temperatureC ?? this.temperatureC,
        feelsLikeC: feelsLikeC ?? this.feelsLikeC,
        iconCode: iconCode ?? this.iconCode,
        description: description ?? this.description,
        humidity: humidity ?? this.humidity,
        windSpeedMs: windSpeedMs ?? this.windSpeedMs,
        observedAt: observedAt ?? this.observedAt,
      );

  @override
  List<Object?> get props => [
        city,
        temperatureC,
        feelsLikeC,
        iconCode,
        description,
        humidity,
        windSpeedMs,
        observedAt,
      ];
}

/// [DailyForecast] is one day of the detailed weather screen (Requirement 3.3).
///
/// OpenWeatherMap's free forecast is a flat list of three-hourly readings, not a
/// list of days. [DailyForecast.fromForecastJson] is what turns the one into the
/// other, and it is the only place that knows the difference.
class DailyForecast extends Equatable {
  const DailyForecast({
    required this.date,
    required this.minC,
    required this.maxC,
    required this.iconCode,
  });

  final DateTime date;
  final double minC;
  final double maxC;
  final String iconCode;

  WeatherCondition get condition => WeatherCondition.fromIconCode(iconCode);

  String get high => '${maxC.round()}°';

  String get low => '${minC.round()}°';

  factory DailyForecast.fromJson(Map<String, dynamic> json) => DailyForecast(
        date: DateTime.tryParse('${json['date']}') ?? DateTime.now(),
        minC: num.tryParse('${json['min']}')?.toDouble() ?? 0,
        maxC: num.tryParse('${json['max']}')?.toDouble() ?? 0,
        iconCode: json['icon']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'min': minC,
        'max': maxC,
        'icon': iconCode,
      };

  /// [fromForecastJson] collapses the API's three-hourly list into one entry per
  /// day.
  ///
  /// The day's icon is taken from the reading nearest midday rather than the
  /// first of the day: the first is usually 03:00, and a clear night would draw a
  /// sun-free day as clear when it rained from dawn.
  static List<DailyForecast> fromForecastJson(Map<String, dynamic> json) {
    final readings = json['list'] as List? ?? const [];

    final byDay = <DateTime, List<Map<String, dynamic>>>{};

    for (final reading in readings) {
      if (reading is! Map<String, dynamic>) continue;

      final at = _timestamp(reading['dt']);
      final day = DateTime(at.year, at.month, at.day);

      byDay.putIfAbsent(day, () => []).add(reading);
    }

    final days = byDay.keys.toList()..sort();

    return [
      for (final day in days)
        if (_dayForecast(day, byDay[day]!) case final DailyForecast forecast)
          forecast,
    ];
  }

  static DailyForecast _dayForecast(
    DateTime day,
    List<Map<String, dynamic>> readings,
  ) {
    var min = double.infinity;
    var max = double.negativeInfinity;

    Map<String, dynamic>? middaySoFar;
    var middayGap = Duration(days: 1);

    for (final reading in readings) {
      final main = reading['main'] as Map<String, dynamic>? ?? const {};

      final low = num.tryParse('${main['temp_min']}')?.toDouble();
      final high = num.tryParse('${main['temp_max']}')?.toDouble();

      if (low != null && low < min) min = low;
      if (high != null && high > max) max = high;

      final at = _timestamp(reading['dt']);
      final gap = at.difference(DateTime(day.year, day.month, day.day, 12)).abs();
      if (gap < middayGap) {
        middayGap = gap;
        middaySoFar = reading;
      }
    }

    final conditions = middaySoFar?['weather'] as List?;
    final condition = conditions == null || conditions.isEmpty
        ? const <String, dynamic>{}
        : conditions.first as Map<String, dynamic>;

    return DailyForecast(
      date: day,
      minC: min.isFinite ? min : 0,
      maxC: max.isFinite ? max : 0,
      iconCode: condition['icon']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [date, minC, maxC, iconCode];
}

/// [_timestamp] reads OpenWeatherMap's seconds-since-epoch field.
DateTime _timestamp(Object? value) {
  final seconds = int.tryParse('$value');
  if (seconds == null) return DateTime.now();
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}
