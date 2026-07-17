import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/data/models/weather.dart';

/// [BriefingFacts] is everything the daily briefing is allowed to know
/// (design.md §5.3).
///
/// Mutable, not `Equatable`, outbound-only — it goes to the prompt and to the
/// fallback, and nothing ever parses one back (CLAUDE.md §8).
///
/// The absences are the design: no vault content, no account balance, no
/// transaction. The briefing speaks about the day, and money reaching a prompt is
/// one injection away from leaking.
class BriefingFacts {
  BriefingFacts({
    required this.now,
    this.city,
    this.weather,
    this.taskCount = 0,
    this.overdueCount = 0,
    this.taskTitles = const <String>[],
    this.headlines = const <String>[],
  });

  DateTime now;
  String? city;
  Weather? weather;
  int taskCount;
  int overdueCount;

  /// Capped by the prompt at [AiPrompt.maxBriefingTasks].
  List<String> taskTitles;

  /// Capped by the prompt at [AiPrompt.maxBriefingHeadlines].
  List<String> headlines;

  /// [season] is derived rather than stored — it is a pure function of [now], so
  /// storing it would only create a way for the two to disagree.
  Season get season => Helpers.seasonOf(now);

  /// [greeting] is the salutation the briefing opens with, and the bucket the
  /// bloc regenerates on (design.md §5.4, rule 3).
  String get greeting => Helpers.greeting(at: now);

  Map<String, dynamic> toJson() => {
        'now': now.toIso8601String(),
        'season': season.name,
        'city': city,
        'weather': weather?.toJson(),
        'taskCount': taskCount,
        'overdueCount': overdueCount,
        'taskTitles': taskTitles,
        'headlines': headlines,
      };

  BriefingFacts copyWith({
    DateTime? now,
    String? city,
    Weather? weather,
    int? taskCount,
    int? overdueCount,
    List<String>? taskTitles,
    List<String>? headlines,
  }) =>
      BriefingFacts(
        now: now ?? this.now,
        city: city ?? this.city,
        weather: weather ?? this.weather,
        taskCount: taskCount ?? this.taskCount,
        overdueCount: overdueCount ?? this.overdueCount,
        taskTitles: taskTitles ?? this.taskTitles,
        headlines: headlines ?? this.headlines,
      );
}
