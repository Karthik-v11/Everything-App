import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/data/entity/ai_prompt.dart';
import 'package:everything_app/data/entity/briefing_facts.dart';
import 'package:everything_app/data/entity/briefing_fallback.dart';
import 'package:everything_app/data/models/weather.dart';
import 'package:flutter_test/flutter_test.dart';

/// The daily briefing's pure parts (design.md §5, §11).
///
/// Per CLAUDE.md §17 the default is no tests. What clears the bar here is the
/// prompt: it is the app's first **multi-source** prompt, and design.md §5.2
/// argues that a closed fact list is what keeps it grounded. That is only an
/// argument if it is asserted — so what is asserted is what the model is allowed
/// to see, and the caps on how much of it.
void main() {
  // A fixed anchor so every relative figure is deterministic: a Wednesday.
  final now = DateTime(2026, 7, 15, 9, 30);

  final weather = Weather(
    city: 'Bengaluru',
    temperatureC: 27.4,
    feelsLikeC: 29,
    iconCode: '01d',
    description: 'clear sky',
    humidity: 60,
    windSpeedMs: 3,
    observedAt: now,
  );

  BriefingFacts facts({
    int taskCount = 0,
    int overdueCount = 0,
    List<String> taskTitles = const [],
    List<String> headlines = const [],
    String? city,
    Weather? withWeather,
  }) =>
      BriefingFacts(
        now: now,
        city: city,
        weather: withWeather,
        taskCount: taskCount,
        overdueCount: overdueCount,
        taskTitles: taskTitles,
        headlines: headlines,
      );

  group('AiPrompt.briefing — what the model may see', () {
    test('an empty source omits its heading rather than emitting it empty', () {
      final prompt = AiPrompt.briefing(facts: facts());

      // "Tasks:" followed by nothing is an invitation to fill it in, and the one
      // thing this prompt must not do is invite.
      expect(prompt, isNot(contains('Tasks:')));
      expect(prompt, isNot(contains('Headlines:')));
      expect(prompt, isNot(contains('Weather:')));
      // The clock is the one source that is always present.
      expect(prompt, contains('Now:'));
    });

    test('each heading appears once its source has something to say', () {
      final prompt = AiPrompt.briefing(
        facts: facts(
          taskCount: 2,
          taskTitles: ['Buy groceries', 'Wash car'],
          headlines: ['Something happened'],
          city: 'Bengaluru',
          withWeather: weather,
        ),
      );

      expect(prompt, contains('Weather: Bengaluru, 27°C, clear sky.'));
      expect(prompt, contains('Tasks: 2 due today, 0 overdue.'));
      expect(prompt, contains('- Buy groceries'));
      expect(prompt, contains('Headlines:'));
      expect(prompt, contains('- Something happened'));
    });

    test('task titles are capped at maxBriefingTasks', () {
      final titles = [for (var i = 1; i <= 20; i++) 'Task $i'];

      final prompt = AiPrompt.briefing(
        facts: facts(taskCount: 20, taskTitles: titles),
      );

      expect(prompt, contains('- Task ${AiPrompt.maxBriefingTasks}'));
      expect(prompt, isNot(contains('- Task ${AiPrompt.maxBriefingTasks + 1}')));
      // The *count* is still honest even though the titles are capped: the
      // briefing may say "20 due today" while naming six of them.
      expect(prompt, contains('Tasks: 20 due today'));
    });

    test('headlines are capped at maxBriefingHeadlines', () {
      final headlines = [for (var i = 1; i <= 10; i++) 'Headline $i'];

      final prompt = AiPrompt.briefing(facts: facts(headlines: headlines));

      expect(prompt, contains('- Headline ${AiPrompt.maxBriefingHeadlines}'));
      expect(
        prompt,
        isNot(contains('- Headline ${AiPrompt.maxBriefingHeadlines + 1}')),
      );
    });

    test('no vault, finance or account figure can reach the prompt', () {
      // The guarantee is structural rather than filtered: BriefingFacts has no
      // field that could carry a secret or a balance, so the assertion is that
      // the whole fact surface is the day and nothing else.
      final prompt = AiPrompt.briefing(
        facts: facts(
          taskCount: 1,
          taskTitles: ['Buy groceries'],
          city: 'Bengaluru',
          withWeather: weather,
        ),
      );

      for (final forbidden in const [
        '₹',
        'balance',
        'budget',
        'spent',
        'password',
        'vault',
        'transaction',
      ]) {
        expect(
          prompt.toLowerCase(),
          isNot(contains(forbidden)),
          reason: '"$forbidden" reached the briefing prompt',
        );
      }
    });

    test('the system instruction forbids inventing every kind of fact', () {
      const instruction = AiPrompt.briefingSystemInstruction;

      expect(instruction, contains('ONLY the facts given to you'));
      expect(instruction, contains('Never invent'));
      // A proactive surface that volunteers opinions is a life coach, and only an
      // organiser was asked for.
      expect(instruction, contains('Do not give advice'));
    });
  });

  group('BriefingFallback.compose', () {
    test('composes the reference UI\'s own line from counts alone', () {
      final line = BriefingFallback.compose(facts(taskCount: 7));

      expect(line, startsWith('Good Morning.'));
      expect(line, contains('7 things planned today'));
    });

    test('a clean day says so rather than counting to zero', () {
      expect(
        BriefingFallback.compose(facts()),
        contains('Nothing is due today'),
      );
    });

    test('singulars read as English', () {
      final line = BriefingFallback.compose(
        facts(taskCount: 1, overdueCount: 1),
      );

      expect(line, contains('1 thing planned'));
      expect(line, contains('1 is overdue'));
    });

    test('overdue is mentioned only when there is some', () {
      expect(
        BriefingFallback.compose(facts(taskCount: 3)),
        isNot(contains('overdue')),
      );
      expect(
        BriefingFallback.compose(facts(taskCount: 3, overdueCount: 2)),
        contains('2 are overdue'),
      );
    });
  });

  group('Helpers.seasonOf — month boundaries', () {
    test('maps every month onto the India-first calendar', () {
      const expected = <int, Season>{
        1: Season.winter,
        2: Season.winter,
        3: Season.summer,
        4: Season.summer,
        5: Season.summer,
        6: Season.monsoon,
        7: Season.monsoon,
        8: Season.monsoon,
        9: Season.monsoon,
        10: Season.postMonsoon,
        11: Season.postMonsoon,
        12: Season.winter,
      };

      for (final entry in expected.entries) {
        expect(
          Helpers.seasonOf(DateTime(2026, entry.key, 15)),
          entry.value,
          reason: 'month ${entry.key}',
        );
      }
    });

    test('August is monsoon, not the Western summer', () {
      expect(Helpers.seasonOf(DateTime(2026, 8, 1)), Season.monsoon);
    });

    test('facts derive their season from their own clock', () {
      expect(facts().season, Season.monsoon);
    });
  });
}
