import 'package:everything_app/bloc/weather/weather_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [showCitySheet] asks where the user is (Requirement 3.2).
///
/// The app requests no location permission. The Weather_Service needs a place,
/// and a permission prompt on first launch — for a feature that is one pill on
/// one screen — buys a coordinate the user could have typed in five seconds.
/// They name their city once and it is remembered.
Future<void> showCitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BlocProvider.value(
      value: context.read<WeatherBloc>(),
      child: const CitySheet(),
    ),
  );
}

class CitySheet extends StatefulWidget {
  const CitySheet({super.key});

  @override
  State<CitySheet> createState() => _CitySheetState();
}

class _CitySheetState extends State<CitySheet> {
  late final TextEditingController _city;

  @override
  void initState() {
    super.initState();
    _city = TextEditingController(text: context.read<WeatherBloc>().state.city);
  }

  @override
  void dispose() {
    _city.dispose();
    super.dispose();
  }

  void _submit() {
    final city = _city.text.trim();
    if (city.isEmpty) return;

    context.read<WeatherBloc>().add(ChangeWeatherCityEvent(city: city));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Your city', style: context.texts.titleMedium),
            const Gap(12),
            TextField(
              controller: _city,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'Bengaluru',
                // Two cities can share a name, and the Weather_Service resolves
                // the ambiguity in favour of whichever it likes — the country
                // code is how a user in Springfield says which one.
                helperText: 'Add a country code if the name is ambiguous: Paris,FR',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const Gap(16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
