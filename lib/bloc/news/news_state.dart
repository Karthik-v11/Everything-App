part of 'news_bloc.dart';

/// [NewsState] is the headlines the app last knew, per category, and when.
///
/// [articles] and [fetchedAt] are keyed by category and persisted together: a
/// cached list without the time it arrived cannot be told from a fresh one, and
/// would never be refreshed.
class NewsState extends Equatable {
  const NewsState({
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.category = NewsCategory.all,
    this.articles = const <NewsCategory, List<Article>>{},
    this.fetchedAt = const <NewsCategory, DateTime>{},
  });

  final bool isLoading;
  final String error;
  final String message;

  /// The open tab.
  final NewsCategory category;

  final Map<NewsCategory, List<Article>> articles;
  final Map<NewsCategory, DateTime> fetchedAt;

  /// [visibleArticles] is what the open tab shows.
  List<Article> get visibleArticles => articles[category] ?? const [];

  bool hasArticles(NewsCategory category) =>
      (articles[category] ?? const []).isNotEmpty;

  /// [isStale] is true when a category has never been fetched or was fetched
  /// longer ago than [kStaleCacheThreshold]. It decides both whether a tab
  /// re-fetches and whether the Dashboard admits to showing saved data.
  bool isStale(NewsCategory category) {
    final at = fetchedAt[category];
    if (at == null) return true;
    return DateTime.now().difference(at) > kStaleCacheThreshold;
  }

  /// [isCurrentStale] is [isStale] for the open tab, but only once there is
  /// something cached to *be* stale — an empty tab is not stale, it is empty, and
  /// a banner over nothing explains nothing.
  bool get isCurrentStale => hasArticles(category) && isStale(category);

  NewsState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    NewsCategory? category,
    Map<NewsCategory, List<Article>>? articles,
    Map<NewsCategory, DateTime>? fetchedAt,
  }) =>
      NewsState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        category: category ?? this.category,
        articles: articles ?? this.articles,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );

  /// [fromJson] restores the cached headlines. The open tab is not restored: the
  /// Dashboard opens on All, which is what a user coming back to it expects.
  factory NewsState.fromJson(Map<String, dynamic> json) {
    final cached = json['HydratedArticles'] as Map<String, dynamic>? ?? const {};
    final times = json['HydratedFetchedAt'] as Map<String, dynamic>? ?? const {};

    return NewsState(
      articles: {
        for (final entry in cached.entries)
          NewsCategory.fromName(entry.key): [
            for (final article in entry.value as List? ?? const [])
              if (article is Map<String, dynamic>) Article.fromJson(article),
          ],
      },
      fetchedAt: {
        for (final entry in times.entries)
          if (DateTime.tryParse('${entry.value}') case final DateTime at)
            NewsCategory.fromName(entry.key): at,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'HydratedArticles': {
          for (final entry in articles.entries)
            entry.key.name: [
              for (final article in entry.value) article.toJson(),
            ],
        },
        'HydratedFetchedAt': {
          for (final entry in fetchedAt.entries)
            entry.key.name: entry.value.toIso8601String(),
        },
      };

  @override
  List<Object?> get props => [
        isLoading,
        error,
        message,
        category,
        articles,
        fetchedAt,
      ];
}
