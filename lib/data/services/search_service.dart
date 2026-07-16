import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/daos/search_dao.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/search_result.dart';

/// [SearchService] runs a Global Search query against the FTS index
/// (Requirements 17, 24.2).
///
/// Its one job past delegating to [SearchDao] is turning a user's raw text into
/// a safe FTS5 MATCH expression. Raw input cannot go straight into `MATCH`: `"`,
/// `*`, `:`, `(`, `-` and `NEAR`/`OR`/`AND` all carry meaning there, so an
/// unescaped query is at best a syntax error and at worst a query that means
/// something the user did not type.
class SearchService {
  const SearchService({required this.dao});

  final SearchDao dao;

  /// Everything that is not a letter, digit or whitespace — the characters that
  /// carry syntax in an FTS5 query. Stripping them mirrors the `unicode61`
  /// tokenizer the index is built with, so the query tokenises the same way the
  /// content did.
  static final RegExp _nonToken = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
  static final RegExp _whitespace = RegExp(r'\s+');

  /// [toMatchQuery] converts raw text to a prefix-matching FTS5 expression, or
  /// null when nothing searchable remains.
  ///
  /// Each token becomes a prefix term (`pay*`), so results appear as the user
  /// types rather than only on a whole word; tokens are ANDed, FTS5's default, so
  /// "pay rent" narrows rather than widens. Lower-casing also neutralises the
  /// `AND`/`OR`/`NOT`/`NEAR` keywords, which are operators only in upper case.
  static String? toMatchQuery(String raw) {
    final tokens = raw
        .toLowerCase()
        .replaceAll(_nonToken, ' ')
        .split(_whitespace)
        .where((token) => token.isNotEmpty);

    if (tokens.isEmpty) return null;

    return tokens.map((token) => '$token*').join(' ');
  }

  /// [search] returns the matching results, most relevant first.
  ///
  /// A blank or all-punctuation query is not an error — it is an empty result,
  /// which is what the screen shows before the user has typed anything real.
  Future<JsonResponse> search(String query, {int limit = 50}) async {
    if (query.isBlank) {
      return JsonResponse.success(
        message: 'Type to search.',
        data: const <SearchResult>[],
      );
    }

    final match = toMatchQuery(query);
    if (match == null) {
      return JsonResponse.success(
        message: 'Type to search.',
        data: const <SearchResult>[],
      );
    }

    try {
      final rows = await dao.search(match, limit: limit);

      final results = <SearchResult>[
        for (final row in rows)
          if (SearchModule.fromName(row.module) case final module?)
            SearchResult(
              module: module,
              id: row.itemId,
              title: row.title,
              subtitle: row.snippet.trim(),
            ),
      ];

      return JsonResponse.success(
        message: '${results.length} results.',
        data: results,
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not run that search.',
      );
    }
  }
}
