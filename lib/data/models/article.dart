import 'package:equatable/equatable.dart';

/// [NewsCategory] is one tab of the Dashboard's news section (Requirement 3.9).
///
/// [query] is what the News_Service is asked for. NewsAPI's top-headlines
/// endpoint has no "world" category and forbids mixing `sources` with
/// `country`/`category`, so World is expressed as a set of international sources
/// while every other tab is a category of the local feed. All is that same feed
/// with no category at all, which is what makes it a mix rather than a repeat of
/// India's general bucket.
enum NewsCategory {
  all('All', {'country': 'in'}),
  india('India', {'country': 'in', 'category': 'general'}),
  world('World', {'sources': 'bbc-news,al-jazeera-english,associated-press'}),
  technology('Technology', {'country': 'in', 'category': 'technology'}),
  business('Business', {'country': 'in', 'category': 'business'}),
  sports('Sports', {'country': 'in', 'category': 'sports'});

  const NewsCategory(this.label, this.query);

  final String label;
  final Map<String, String> query;

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
