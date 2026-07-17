import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:flutter/material.dart';

/// [MediaType] is what a watchlist entry is (Requirement 8.1).
///
/// [countsChapters] is the difference that matters: a manga or a book is measured
/// in chapters and everything else in episodes, so the entry knows which of its two
/// totals it is actually about rather than the UI guessing.
enum MediaType {
  movie,
  tvShow,
  anime,
  manga,
  book,
  game;

  String get label => switch (this) {
        MediaType.movie => 'Movie',
        MediaType.tvShow => 'TV Show',
        MediaType.anime => 'Anime',
        MediaType.manga => 'Manga',
        MediaType.book => 'Book',
        MediaType.game => 'Game',
      };

  IconData get icon => switch (this) {
        MediaType.movie => Icons.movie_outlined,
        MediaType.tvShow => Icons.tv_rounded,
        MediaType.anime => Icons.animation_rounded,
        MediaType.manga => Icons.menu_book_rounded,
        MediaType.book => Icons.auto_stories_outlined,
        MediaType.game => Icons.sports_esports_outlined,
      };

  /// [countsChapters] is true for the two page-counted types.
  bool get countsChapters => this == MediaType.manga || this == MediaType.book;

  /// [unit] is what one step of progress is called.
  String get unit => switch (this) {
        MediaType.manga || MediaType.book => 'chapter',
        MediaType.game => 'hour',
        _ => 'episode',
      };

  /// [hasProgress] is whether progress is a meaningful idea for this type. A movie
  /// is watched or it is not; there is no episode 3 of it.
  bool get hasProgress => this != MediaType.movie;

  static MediaType fromName(String? name) => MediaType.values.firstWhere(
        (value) => value.name == name,
        orElse: () => MediaType.movie,
      );
}

/// [WatchStatus] is where the user is with an entry (Requirement 8.1).
enum WatchStatus {
  wishlist,
  watching,
  completed,
  dropped;

  String get label => switch (this) {
        WatchStatus.wishlist => 'Wishlist',
        WatchStatus.watching => 'Watching',
        WatchStatus.completed => 'Completed',
        WatchStatus.dropped => 'Dropped',
      };

  static WatchStatus fromName(String? name) => WatchStatus.values.firstWhere(
        (value) => value.name == name,
        orElse: () => WatchStatus.wishlist,
      );
}

/// [WatchlistItem] is one thing being tracked (Requirement 8).
///
/// Property 16's two invariants are enforced in the model, by [withProgress] and
/// [withStatus], not at the call sites: progress cannot exceed a defined total,
/// and a Completed entry always carries a [completedAt] — by whichever route it
/// reached Completed.
class WatchlistItem extends Equatable {
  const WatchlistItem({
    required this.id,
    required this.title,
    required this.mediaType,
    required this.createdAt,
    this.status = WatchStatus.wishlist,
    this.rating,
    this.currentProgress,
    this.totalEpisodes,
    this.totalChapters,
    this.completedAt,
  });

  final String id;
  final String title;
  final MediaType mediaType;
  final WatchStatus status;

  /// 0–10, or null when unrated.
  final double? rating;

  final int? currentProgress;
  final int? totalEpisodes;
  final int? totalChapters;
  final DateTime? completedAt;
  final DateTime createdAt;

  /// [total] is the total this entry is actually measured against — chapters for a
  /// manga or a book, episodes for everything else — or null when the user has not
  /// said how long it is.
  int? get total => mediaType.countsChapters ? totalChapters : totalEpisodes;

  bool get isCompleted => status == WatchStatus.completed;

  /// [progressFraction] is 0–1 for the progress bar, or null when there is nothing
  /// to measure against.
  double? get progressFraction {
    final target = total;
    if (target == null || target <= 0) return null;
    return ((currentProgress ?? 0) / target).clamp(0.0, 1.0);
  }

  /// [progressLabel] is "5/12 episodes", or just "5 episodes" when the total is
  /// unknown, or null when progress means nothing for this type.
  String? get progressLabel {
    if (!mediaType.hasProgress) return null;

    final current = currentProgress;
    final target = total;
    if (current == null && target == null) return null;

    final unit = mediaType.unit;
    final plural = (current ?? 0) == 1 ? unit : '${unit}s';

    return target == null
        ? '${current ?? 0} $plural'
        : '${current ?? 0}/$target $plural';
  }

  /// [withProgress] moves progress to [value], holding both halves of Property 16.
  ///
  /// Progress is clamped to the total when one is defined, so no sequence of
  /// updates can store an entry as being on episode 14 of 12.
  ///
  /// Reaching the total completes the entry, so finishing the last episode and
  /// tapping Completed leave the same row behind. That path goes through
  /// [withStatus], so it stamps [completedAt] like every other one.
  WatchlistItem withProgress(int value) {
    final target = total;
    final clamped = target == null
        ? (value < 0 ? 0 : value)
        : value.clamp(0, target);

    final progressed = copyWith(currentProgress: clamped);

    if (target != null && clamped >= target && target > 0) {
      return progressed.withStatus(WatchStatus.completed);
    }

    // Backing progress off a completed entry means it is being watched again, and
    // an entry that is no longer complete must not keep a completion date.
    if (isCompleted) return progressed.withStatus(WatchStatus.watching);

    return progressed;
  }

  /// [withStatus] moves the entry to [value], holding the second half of Property
  /// 16: Completed always records when (Requirement 8.3), and nothing else ever
  /// carries a completion date.
  ///
  /// Completing an entry with a known total also fills its progress in. An entry
  /// marked finished while it says 3/12 is a row that contradicts itself.
  WatchlistItem withStatus(WatchStatus value) {
    if (value != WatchStatus.completed) {
      return copyWith(status: value, clearCompletedAt: true);
    }

    final target = total;

    return copyWith(
      status: WatchStatus.completed,
      // Re-completing an already-completed entry keeps its original date rather
      // than moving it to now.
      completedAt: completedAt ?? DateTime.now(),
      currentProgress: target ?? currentProgress,
    );
  }

  bool matches(String query) {
    if (query.isBlank) return true;
    return title.containsIgnoreCase(query) ||
        mediaType.label.containsIgnoreCase(query);
  }

  factory WatchlistItem.fromEntry(WatchlistItemEntry entry) => WatchlistItem(
        id: entry.id,
        title: entry.title,
        mediaType: MediaType.fromName(entry.mediaType),
        status: WatchStatus.fromName(entry.status),
        rating: entry.rating,
        currentProgress: entry.currentProgress,
        totalEpisodes: entry.totalEpisodes,
        totalChapters: entry.totalChapters,
        completedAt: entry.completedAt,
        createdAt: entry.createdAt,
      );

  WatchlistTableCompanion toCompanion() => WatchlistTableCompanion.insert(
        id: id,
        title: title,
        mediaType: mediaType.name,
        status: status.name,
        rating: Value(rating),
        currentProgress: Value(currentProgress),
        totalEpisodes: Value(totalEpisodes),
        totalChapters: Value(totalChapters),
        completedAt: Value(completedAt),
        createdAt: createdAt,
      );

  WatchlistItem copyWith({
    String? id,
    String? title,
    MediaType? mediaType,
    WatchStatus? status,
    double? rating,
    bool clearRating = false,
    int? currentProgress,
    bool clearCurrentProgress = false,
    int? totalEpisodes,
    bool clearTotalEpisodes = false,
    int? totalChapters,
    bool clearTotalChapters = false,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? createdAt,
  }) =>
      WatchlistItem(
        id: id ?? this.id,
        title: title ?? this.title,
        mediaType: mediaType ?? this.mediaType,
        status: status ?? this.status,
        rating: clearRating ? null : (rating ?? this.rating),
        currentProgress: clearCurrentProgress
            ? null
            : (currentProgress ?? this.currentProgress),
        totalEpisodes:
            clearTotalEpisodes ? null : (totalEpisodes ?? this.totalEpisodes),
        totalChapters:
            clearTotalChapters ? null : (totalChapters ?? this.totalChapters),
        completedAt:
            clearCompletedAt ? null : (completedAt ?? this.completedAt),
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  List<Object?> get props => [
        id,
        title,
        mediaType,
        status,
        rating,
        currentProgress,
        totalEpisodes,
        totalChapters,
        completedAt,
        createdAt,
      ];
}
