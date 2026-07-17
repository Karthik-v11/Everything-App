import 'package:everything_app/data/entity/briefing_facts.dart';

/// [BriefingFallback] composes the briefing from counts alone, with no model
/// involved (design.md §5.5).
///
/// Not only the failure path: it is also the first-frame and offline content, so
/// the card never shows a spinner or an empty state.
///
/// Pure and domain-shaped, so it lives beside the prompt rather than in
/// `core/utils/`.
class BriefingFallback {
  const BriefingFallback._();

  /// [compose] is the deterministic briefing for [facts].
  static String compose(BriefingFacts facts) {
    final buffer = StringBuffer('${facts.greeting}.');

    if (facts.taskCount == 0) {
      buffer.write(' Nothing is due today.');
    } else {
      final things = facts.taskCount == 1 ? 'thing' : 'things';
      buffer.write(' You have ${facts.taskCount} $things planned today.');
    }

    if (facts.overdueCount > 0) {
      final one = facts.overdueCount == 1;
      buffer.write(
        ' ${facts.overdueCount} ${one ? 'is' : 'are'} overdue.',
      );
    }

    final weather = facts.weather;
    final city = facts.city ?? weather?.city;
    if (weather != null && city != null) {
      buffer.write(' $city is ${weather.temperature}C, ${weather.description}.');
    }

    return buffer.toString();
  }
}
