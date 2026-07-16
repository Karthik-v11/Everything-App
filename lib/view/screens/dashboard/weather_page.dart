import 'package:everything_app/bloc/weather/weather_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/weather.dart';
import 'package:everything_app/view/screens/dashboard/city_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [WeatherPage] is the detailed weather screen behind the Dashboard pill
/// (Requirement 3.3): the conditions now, and the days to come.
///
/// It reads the same [WeatherBloc] the pill does and asks for nothing of its own.
/// The forecast was fetched alongside the current conditions, so opening this
/// screen shows a five-day outlook without a request or a spinner.
class WeatherPage extends StatelessWidget {
  const WeatherPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather'),
        actions: [
          IconButton(
            onPressed: () => showCitySheet(context),
            icon: const Icon(Icons.edit_location_alt_outlined),
            tooltip: 'Change city',
          ),
        ],
      ),
      body: BlocBuilder<WeatherBloc, WeatherState>(
        builder: (context, state) {
          final weather = state.weather;

          if (weather == null) {
            return _Empty(
              message: state.hasCity
                  ? (state.error.isEmpty
                      ? 'Loading the weather…'
                      : state.error)
                  : 'Set your city to see the weather.',
              isLoading: state.isLoading,
            );
          }

          return RefreshIndicator(
            onRefresh: () async =>
                context.read<WeatherBloc>().add(const FetchWeatherEvent()),
            child: ListView(
              padding: responsivePadding(context).copyWith(top: 8, bottom: 24),
              children: [
                _Current(weather: weather, isStale: state.isStale, age: state.age),
                const Gap(24),
                if (state.forecast.isNotEmpty) ...[
                  Text('Next days', style: context.texts.labelMedium),
                  const Gap(8),
                  for (final day in state.forecast)
                    _ForecastRow(forecast: day),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// [_Current] is the headline: the temperature, what it feels like, and the two
/// figures that change how a day is dressed for.
class _Current extends StatelessWidget {
  const _Current({
    required this.weather,
    required this.isStale,
    required this.age,
  });

  final Weather weather;
  final bool isStale;
  final String age;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(weather.condition.icon, size: 56, color: colors.primary),
            const Gap(16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(weather.temperature, style: texts.displayMedium),
                  Text(
                    weather.description.capitalized,
                    style: texts.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Gap(8),
        Text(
          weather.city,
          style: texts.titleMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        if (isStale) ...[
          const Gap(4),
          Text(
            'Saved reading, $age',
            style: texts.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
        const Gap(20),
        Row(
          children: [
            _Metric(
              icon: Icons.thermostat_rounded,
              label: 'Feels like',
              value: weather.feelsLike,
            ),
            _Metric(
              icon: Icons.water_drop_outlined,
              label: 'Humidity',
              value: '${weather.humidity}%',
            ),
            _Metric(
              icon: Icons.air_rounded,
              label: 'Wind',
              value: weather.windSpeed,
            ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: colors.onSurfaceVariant),
          const Gap(6),
          Text(value, style: context.texts.titleMedium),
          Text(
            label,
            style: context.texts.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ForecastRow extends StatelessWidget {
  const _ForecastRow({required this.forecast});

  final DailyForecast forecast;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              forecast.date.relativeLabel,
              style: context.texts.bodyMedium,
            ),
          ),
          Icon(forecast.condition.icon, size: 20, color: colors.primary),
          const Spacer(),
          Text(
            forecast.low,
            style: context.texts.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const Gap(12),
          Text(forecast.high, style: context.texts.titleMedium),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message, required this.isLoading});

  final String message;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());

    return Center(
      child: Padding(
        padding: responsivePadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const Gap(12),
            FilledButton.tonal(
              onPressed: () => showCitySheet(context),
              child: const Text('Set city'),
            ),
          ],
        ),
      ),
    );
  }
}
