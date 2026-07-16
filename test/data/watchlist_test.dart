import 'package:everything_app/data/models/watchlist_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feature: everything-app, Property 16: Watchlist Progress Monotonicity.
///
/// *For any* watchlist entry with a defined total, the stored progress after an
/// update never exceeds the total, and a status set to Completed always records a
/// non-null completedAt.
///
/// The property is tested against [WatchlistItem.withProgress] and
/// [WatchlistItem.withStatus] rather than against the bloc, because those two
/// methods are where the rule actually lives — every writer in the app routes
/// through them, so a property that holds here holds for the stepper on the card,
/// the field in the sheet, and the AI parser that does not exist yet.
void main() {
  WatchlistItem entry({
    MediaType mediaType = MediaType.tvShow,
    WatchStatus status = WatchStatus.watching,
    int? progress,
    int? totalEpisodes,
    int? totalChapters,
    DateTime? completedAt,
  }) =>
      WatchlistItem(
        id: 'w1',
        title: 'Severance',
        mediaType: mediaType,
        status: status,
        currentProgress: progress,
        totalEpisodes: totalEpisodes,
        totalChapters: totalChapters,
        completedAt: completedAt,
        createdAt: DateTime(2026, 1, 1),
      );

  group('Property 16: progress never exceeds a defined total', () {
    test('an update past the total is clamped to it', () {
      final updated = entry(totalEpisodes: 9, progress: 3).withProgress(14);

      expect(updated.currentProgress, 9);
    });

    test('the clamp holds for every value, over the whole range', () {
      // The property is "for any update", so it is asserted over a range rather
      // than at one convenient point. A clamp that was off by one at the boundary
      // would pass a single-value test.
      const total = 12;

      for (var value = -5; value <= 40; value++) {
        final updated = entry(totalEpisodes: total, progress: 0)
            .withProgress(value);

        expect(
          updated.currentProgress,
          inInclusiveRange(0, total),
          reason: 'progress $value must land inside 0..$total',
        );
      }
    });

    test('a manga is measured against its chapters, not its episodes', () {
      // The entry carries both totals; which one bounds it is a fact about its
      // media type. Clamping against the wrong one would let a manga run to
      // whatever the episode count happened to be.
      final updated = entry(
        mediaType: MediaType.manga,
        totalChapters: 20,
        totalEpisodes: 200,
        progress: 5,
      ).withProgress(50);

      expect(updated.currentProgress, 20);
    });

    test('progress is unbounded above when no total is known', () {
      final updated = entry(progress: 40).withProgress(41);

      // Nothing to clamp against — an ongoing series with no announced episode
      // count must not be capped at an arbitrary number.
      expect(updated.currentProgress, 41);
      expect(updated.isCompleted, isFalse);
    });

    test('progress never goes below zero', () {
      final updated = entry(totalEpisodes: 9, progress: 2).withProgress(-3);

      expect(updated.currentProgress, 0);
    });
  });

  group('Property 16: Completed always records a date', () {
    test('setting the status to Completed stamps completedAt', () {
      final updated = entry().withStatus(WatchStatus.completed);

      expect(updated.completedAt, isNotNull);
      expect(updated.status, WatchStatus.completed);
    });

    test('reaching the total completes the entry and stamps it', () {
      // The other route to Completed, and the one that is easy to get wrong: the
      // user never touched the status, they just watched the last episode.
      final updated = entry(totalEpisodes: 9, progress: 8).withProgress(9);

      expect(updated.status, WatchStatus.completed);
      expect(updated.completedAt, isNotNull);
    });

    test('every status other than Completed carries no date', () {
      for (final status in WatchStatus.values) {
        final updated = entry(
          status: WatchStatus.completed,
          completedAt: DateTime(2026, 2, 2),
        ).withStatus(status);

        expect(
          updated.completedAt != null,
          status == WatchStatus.completed,
          reason: '$status must ${status == WatchStatus.completed ? '' : 'not '}'
              'carry a completion date',
        );
      }
    });

    test('re-completing an entry keeps its original date', () {
      final original = DateTime(2026, 2, 2);

      final updated = entry(
        status: WatchStatus.completed,
        completedAt: original,
      ).withStatus(WatchStatus.completed);

      // Otherwise every edit to a finished entry would quietly move the day the
      // user finished it to today.
      expect(updated.completedAt, original);
    });

    test('completing an entry fills in its progress', () {
      final updated =
          entry(totalEpisodes: 9, progress: 3).withStatus(WatchStatus.completed);

      // An entry marked finished while it still says 3/9 is a row that contradicts
      // itself.
      expect(updated.currentProgress, 9);
    });

    test('backing progress off a completed entry drops its date', () {
      final completed = entry(totalEpisodes: 9, progress: 9)
          .withStatus(WatchStatus.completed);

      final reopened = completed.withProgress(4);

      expect(reopened.status, WatchStatus.watching);
      expect(reopened.completedAt, isNull);
      expect(reopened.currentProgress, 4);
    });
  });

  group('the total a type is measured against', () {
    test('a movie has no progress to track', () {
      expect(MediaType.movie.hasProgress, isFalse);
    });

    test('books and manga count chapters; everything else counts episodes', () {
      for (final type in MediaType.values) {
        final countsChapters =
            type == MediaType.manga || type == MediaType.book;

        expect(type.countsChapters, countsChapters, reason: type.name);
      }
    });

    test('progressFraction stays inside 0..1 even against a stale total', () {
      // A total lowered below the progress already made — the one way a stored row
      // can be out of range without any writer having misbehaved. The bar must not
      // overflow while the service is clamping the row back.
      final item = entry(totalEpisodes: 5, progress: 40);

      expect(item.progressFraction, 1.0);
    });
  });
}
