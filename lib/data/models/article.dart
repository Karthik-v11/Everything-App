import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/constants.dart';

/// [NewsCategory] is one tab of the Dashboard's news section (Requirement 3.9).
///
/// Every tab names **sources**, not a country. NewsAPI still documents
/// `country=in` on `/top-headlines` and still answers 200 for it — with
/// `totalResults: 0`. That is why World was the only tab with headlines in it:
/// World already named sources, and the other five were asking for a country
/// feed that has nothing behind it.
///
/// `sources` cannot be combined with `country` or `category` — NewsAPI rejects
/// that with `parametersIncompatible` — so a tab is now exactly the publishers
/// listed here.
///
/// **A source id that returns articles is not a source id that works.** NewsAPI
/// keeps serving frozen caches for publishers it has stopped ingesting, with a
/// perfectly healthy `status: ok`: `the-hindu` last published into it in July
/// 2021, `espn-cric-info` in April 2020, `techcrunch` in May 2024. Nothing in a
/// response says so. Anything added to [sourceIds] has to be checked for
/// *freshness*, not for a non-zero count — see the note on [india].
enum NewsCategory {
  /// Deliberately spans the other tabs' territory — wire, tech, business, sport —
  /// rather than being a sixth general feed, so the default tab is a mix.
  all('All', sourceIds: [
    'associated-press',
    'bbc-news',
    'the-verge',
    'bloomberg',
    'bbc-sport',
  ]),

  /// The one tab that cannot be sources: NewsAPI has **no live Indian
  /// publisher**. `the-hindu` and `the-times-of-india` are frozen in 2021, and
  /// every `google-news-*` feed returns articles whose title is the literal
  /// string "Google News". `/everything` indexes far more publishers than the ~78
  /// `sources` accepts, and reaches the Indian press through the search index
  /// instead.
  india('India', query: 'India'),

  world('World', sourceIds: [
    'bbc-news',
    'al-jazeera-english',
    'associated-press',
  ]),

  technology('Technology', sourceIds: ['the-verge', 'wired', 'techradar']),

  business('Business', sourceIds: [
    'bloomberg',
    'the-wall-street-journal',
    'financial-post',
  ]),

  sports('Sports', sourceIds: [
    'bbc-sport',
    'espn',
    'fox-sports',
    'the-sport-bible',
  ]);

  const NewsCategory(this.label, {this.sourceIds = const [], this.query = ''});

  final String label;

  /// NewsAPI source ids, as listed by `/v2/sources`. Empty for a [query] tab.
  /// The API caps the list at 20; none of these come close.
  final List<String> sourceIds;

  /// A `/everything` search term. Empty for a [sourceIds] tab.
  final String query;

  /// Which endpoint answers this tab. `/everything` has no `sources`-free
  /// equivalent of a headline feed and `/top-headlines` cannot search, so the
  /// two tab kinds are two endpoints rather than one with an extra parameter.
  String get path => query.isEmpty ? kTopHeadlinesPath : kEverythingPath;

  /// The tab's parameters, minus the key and page size the service adds.
  ///
  /// `/everything` defaults to relevance, which on a standing query means the
  /// same articles stay on top for days — `publishedAt` is what makes the tab a
  /// news feed rather than a search result. `language` is there because the query
  /// is a plain word that matches in every language NewsAPI indexes.
  Map<String, String> get parameters => query.isEmpty
      ? {'sources': sourceIds.join(',')}
      : {'q': query, 'language': 'en', 'sortBy': 'publishedAt'};

  static NewsCategory fromName(String? name) => NewsCategory.values.firstWhere(
        (value) => value.name == name,
        orElse: () => NewsCategory.all,
      );
}

/// [Article] is one headline (Requirement 3.9).
class Article extends Equatable {
  const Article({
    required this.title,
    required this.url,
    required this.source,
    this.imageUrl,
    this.publishedAt,
  });

  final String title;
  final String url;
  final String source;
  final String? imageUrl;
  final DateTime? publishedAt;

  /// [isRenderable] rejects the two things NewsAPI returns that cannot be shown:
  /// an article with nothing to open, and one whose publisher has pulled it —
  /// which arrives with every field literally set to `[Removed]`.
  bool get isRenderable => url.isNotEmpty && title.isNotEmpty && title != '[Removed]';

  factory Article.fromJson(Map<String, dynamic> json) {
    final source = json['source'] as Map<String, dynamic>? ?? const {};

    return Article(
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      source: source['name']?.toString() ?? '',
      imageUrl: json['urlToImage']?.toString(),
      publishedAt: DateTime.tryParse('${json['publishedAt']}'),
    );
  }

  /// [toJson] is the API's own shape, so that a hydrated article and a fetched
  /// one are read by the same code.
  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'source': {'name': source},
        'urlToImage': imageUrl,
        'publishedAt': publishedAt?.toIso8601String(),
      };

  Article copyWith({
    String? title,
    String? url,
    String? source,
    String? imageUrl,
    DateTime? publishedAt,
  }) =>
      Article(
        title: title ?? this.title,
        url: url ?? this.url,
        source: source ?? this.source,
        imageUrl: imageUrl ?? this.imageUrl,
        publishedAt: publishedAt ?? this.publishedAt,
      );

  @override
  List<Object?> get props => [title, url, source, imageUrl, publishedAt];
}
