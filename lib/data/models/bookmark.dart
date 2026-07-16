import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:flutter/material.dart';

/// [BookmarkSource] is where a bookmark came from (Requirement 6.2).
///
/// It is derived from the URL rather than chosen by the user: nobody wants to be
/// asked what kind of link they just pasted when the link says so itself.
enum BookmarkSource {
  website,
  article,
  youtube,
  github,
  reddit,
  social;

  String get label => switch (this) {
        BookmarkSource.website => 'Website',
        BookmarkSource.article => 'Article',
        BookmarkSource.youtube => 'YouTube',
        BookmarkSource.github => 'GitHub',
        BookmarkSource.reddit => 'Reddit',
        BookmarkSource.social => 'Social',
      };

  IconData get icon => switch (this) {
        BookmarkSource.website => Icons.language_rounded,
        BookmarkSource.article => Icons.article_outlined,
        BookmarkSource.youtube => Icons.play_circle_outline_rounded,
        BookmarkSource.github => Icons.code_rounded,
        BookmarkSource.reddit => Icons.forum_outlined,
        BookmarkSource.social => Icons.tag_rounded,
      };

  static BookmarkSource fromName(String? name) =>
      BookmarkSource.values.firstWhere(
        (value) => value.name == name,
        orElse: () => BookmarkSource.website,
      );
}

/// [Bookmark] is a saved link (Requirement 6).
class Bookmark extends Equatable {
  const Bookmark({
    required this.id,
    required this.url,
    required this.title,
    required this.savedAt,
    this.thumbnailUrl,
    this.sourceType = BookmarkSource.website,
    this.tags = const <String>[],
    this.folderId,
  });

  final String id;
  final String url;
  final String title;
  final String? thumbnailUrl;
  final BookmarkSource sourceType;
  final List<String> tags;
  final String? folderId;
  final DateTime savedAt;

  /// [host] is what the card shows under the title — the shortest honest answer
  /// to "where does this go".
  String get host => UrlMetadata.hostOf(url) ?? url;

  /// [matches] is the in-memory search predicate: title, URL, tags
  /// (Requirement 6.3).
  bool matches(String query) {
    if (query.isBlank) return true;
    return title.containsIgnoreCase(query) ||
        url.containsIgnoreCase(query) ||
        tags.any((tag) => tag.containsIgnoreCase(query));
  }

  factory Bookmark.fromEntry(BookmarkEntry entry) => Bookmark(
        id: entry.id,
        url: entry.url,
        title: entry.title,
        thumbnailUrl: entry.thumbnailUrl,
        sourceType: BookmarkSource.fromName(entry.sourceType),
        tags: _decodeTags(entry.tagsJson),
        folderId: entry.folderId,
        savedAt: entry.savedAt,
      );

  BookmarksTableCompanion toCompanion() => BookmarksTableCompanion.insert(
        id: id,
        url: url,
        title: title,
        thumbnailUrl: Value(thumbnailUrl),
        sourceType: sourceType.name,
        tagsJson: Value(jsonEncode(tags)),
        folderId: Value(folderId),
        savedAt: savedAt,
      );

  Bookmark copyWith({
    String? id,
    String? url,
    String? title,
    String? thumbnailUrl,
    bool clearThumbnailUrl = false,
    BookmarkSource? sourceType,
    List<String>? tags,
    String? folderId,
    bool clearFolderId = false,
    DateTime? savedAt,
  }) =>
      Bookmark(
        id: id ?? this.id,
        url: url ?? this.url,
        title: title ?? this.title,
        thumbnailUrl:
            clearThumbnailUrl ? null : (thumbnailUrl ?? this.thumbnailUrl),
        sourceType: sourceType ?? this.sourceType,
        tags: tags ?? this.tags,
        folderId: clearFolderId ? null : (folderId ?? this.folderId),
        savedAt: savedAt ?? this.savedAt,
      );

  static List<String> _decodeTags(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.cast<String>() : const [];
    } on FormatException {
      // A corrupt blob must not take the whole bookmark list down with it.
      return const [];
    }
  }

  @override
  List<Object?> get props => [
        id,
        url,
        title,
        thumbnailUrl,
        sourceType,
        tags,
        folderId,
        savedAt,
      ];
}

/// [UrlMetadata] is everything about a link that can be known **without asking the
/// network** — its source type, a readable title, and for the sites whose
/// thumbnail URLs are a function of the link itself, a thumbnail.
///
/// This exists because the app is offline-first and a bookmark save must never
/// wait on, or fail because of, a page fetch. The save is made from this
/// immediately; `MetadataService` then enriches the row in the background if the
/// device happens to have a connection. A user on a plane gets a bookmark with a
/// sensible title and the right icon, not a spinner and then an error.
class UrlMetadata extends Equatable {
  const UrlMetadata({
    required this.title,
    required this.source,
    this.thumbnailUrl,
  });

  final String title;
  final BookmarkSource source;
  final String? thumbnailUrl;

  /// [read] derives what it can from [url] alone.
  factory UrlMetadata.read(String url) {
    final uri = _parse(url);
    final host = uri?.host.toLowerCase().replaceFirst('www.', '') ?? '';

    final source = _sourceOf(host, uri);

    return UrlMetadata(
      title: _titleOf(uri, host),
      source: source,
      thumbnailUrl: _thumbnailOf(source, uri),
    );
  }

  /// [hostOf] is the bare host of [url], or null when it does not parse.
  static String? hostOf(String url) {
    final host = _parse(url)?.host.toLowerCase().replaceFirst('www.', '');
    return host == null || host.isEmpty ? null : host;
  }

  /// [normalize] is what gets stored. A user pastes `github.com/flutter`, which is
  /// not a URL any browser will open until it has a scheme.
  static String normalize(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.contains('://')) return trimmed;
    return 'https://$trimmed';
  }

  /// [isValid] is whether [url] is something that can actually be opened. The form
  /// rejects anything else rather than saving a row whose only use is to fail.
  static bool isValid(String url) {
    final uri = _parse(url);
    return uri != null && uri.host.contains('.');
  }

  static Uri? _parse(String url) {
    final uri = Uri.tryParse(normalize(url));
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }

  static BookmarkSource _sourceOf(String host, Uri? uri) {
    if (host.contains('youtube.') || host == 'youtu.be') {
      return BookmarkSource.youtube;
    }
    if (host.contains('github.')) return BookmarkSource.github;
    if (host.contains('reddit.')) return BookmarkSource.reddit;

    const social = [
      'twitter.',
      'x.com',
      'instagram.',
      'facebook.',
      'linkedin.',
      'threads.',
      'mastodon.',
      'bsky.',
      'tiktok.',
    ];
    if (social.any(host.contains)) return BookmarkSource.social;

    const readers = [
      'medium.',
      'substack.',
      'dev.to',
      'hashnode.',
      'notion.',
      'wikipedia.',
    ];
    if (readers.any(host.contains)) return BookmarkSource.article;

    // A path with several segments is far more often a piece of writing than a
    // home page — enough to be worth saying so, and cheap to correct if wrong.
    final segments = uri?.pathSegments.where((s) => s.isNotEmpty) ?? const [];
    if (segments.length >= 2) return BookmarkSource.article;

    return BookmarkSource.website;
  }

  /// [_titleOf] is a placeholder title, used until a real one is known.
  ///
  /// The last path segment, tidied: `/blog/why-flutter-scales` reads as "Why
  /// Flutter Scales", which is almost always the page's actual title and is always
  /// better than the raw URL.
  static String _titleOf(Uri? uri, String host) {
    if (uri == null) return host.isEmpty ? 'Bookmark' : host;

    final segments = [
      for (final segment in uri.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    if (segments.isEmpty) return host;

    final last = segments.last
        .replaceAll(RegExp(r'\.(html?|php|aspx?)$'), '')
        .replaceAll(RegExp(r'[-_+]'), ' ')
        .trim();

    // An id, a hash or a slug of digits says nothing; the host says more.
    if (last.isEmpty || !RegExp('[a-zA-Z]').hasMatch(last)) return host;

    return last
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word.capitalized)
        .join(' ');
  }

  /// [_thumbnailOf] is the thumbnail for the two sites that publish one at a URL
  /// derived from the link, so it needs no fetch and works offline.
  static String? _thumbnailOf(BookmarkSource source, Uri? uri) {
    if (uri == null) return null;

    switch (source) {
      case BookmarkSource.youtube:
        final id = _youTubeId(uri);
        return id == null ? null : 'https://img.youtube.com/vi/$id/hqdefault.jpg';

      case BookmarkSource.github:
        final segments = [
          for (final segment in uri.pathSegments)
            if (segment.isNotEmpty) segment,
        ];
        if (segments.length < 2) return null;
        return 'https://opengraph.githubassets.com/1/'
            '${segments[0]}/${segments[1]}';

      case BookmarkSource.website:
      case BookmarkSource.article:
      case BookmarkSource.reddit:
      case BookmarkSource.social:
        return null;
    }
  }

  /// [_youTubeId] reads the video id out of either URL form YouTube hands out:
  /// `youtube.com/watch?v=ID` and the `youtu.be/ID` share link.
  static String? _youTubeId(Uri uri) {
    final fromQuery = uri.queryParameters['v'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;

    final segments = [
      for (final segment in uri.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    if (segments.isEmpty) return null;

    // `youtu.be/ID`, and `youtube.com/shorts/ID` / `/embed/ID`.
    if (uri.host.contains('youtu.be')) return segments.first;
    if (segments.length >= 2 &&
        (segments.first == 'shorts' || segments.first == 'embed')) {
      return segments[1];
    }

    return null;
  }

  @override
  List<Object?> get props => [title, source, thumbnailUrl];
}
