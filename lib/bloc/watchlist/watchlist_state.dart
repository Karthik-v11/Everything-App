part of 'watchlist_bloc.dart';

/// [WatchlistState] holds everything the Watchlist screen renders.
class WatchlistState extends Equatable {
  const WatchlistState({
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.items = const <WatchlistItem>[],
    this.mediaType,
    this.status,
    this.query = '',
  });

  final bool isLoading;
  final String error;
  final String message;
  final List<WatchlistItem> items;

  final MediaType? mediaType;
  final WatchStatus? status;
  final String query;

  /// The list under the active filters and query, ordered watching → wishlist →
  /// completed → dropped, then newest first.
  List<WatchlistItem> get visibleItems {
    final matched = [
      for (final item in items)
        if (_matches(item)) item,
    ];

    matched.sort((a, b) {
      final rank = _rank(a.status).compareTo(_rank(b.status));
      if (rank != 0) return rank;
      return b.createdAt.compareTo(a.createdAt);
    });

    return matched;
  }

  static int _rank(WatchStatus status) => switch (status) {
        WatchStatus.watching => 0,
        WatchStatus.wishlist => 1,
        WatchStatus.completed => 2,
        WatchStatus.dropped => 3,
      };

  bool _matches(WatchlistItem item) {
    if (mediaType != null && item.mediaType != mediaType) return false;
    if (status != null && item.status != status) return false;
    if (query.isNotBlank && !item.matches(query)) return false;
    return true;
  }

  bool get isFiltered =>
      mediaType != null || status != null || query.isNotBlank;

  /// The number on a status chip. Counts within the media-type filter but ignores
  /// the status filter, so chips keep their counts once one is selected.
  int countOfStatus(WatchStatus value) {
    var count = 0;
    for (final item in items) {
      if (item.status != value) continue;
      if (mediaType != null && item.mediaType != mediaType) continue;
      if (query.isNotBlank && !item.matches(query)) continue;
      count++;
    }
    return count;
  }

  /// Only the types the user actually has entries in get a chip.
  List<MediaType> get mediaTypes {
    final present = <MediaType>{for (final item in items) item.mediaType};

    return [
      for (final value in MediaType.values)
        if (present.contains(value)) value,
    ];
  }

  WatchlistState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    List<WatchlistItem>? items,
    MediaType? mediaType,
    bool clearMediaType = false,
    WatchStatus? status,
    bool clearStatus = false,
    String? query,
  }) =>
      WatchlistState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        items: items ?? this.items,
        mediaType: clearMediaType ? null : (mediaType ?? this.mediaType),
        status: clearStatus ? null : (status ?? this.status),
        query: query ?? this.query,
      );

  @override
  List<Object?> get props => [
        isLoading,
        error,
        message,
        items,
        mediaType,
        status,
        query,
      ];
}
