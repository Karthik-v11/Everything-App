import 'package:drift/drift.dart';
import 'package:everything_app/data/database/app_database.dart';

/// [SearchRow] is one raw hit from the FTS index, before it is mapped to a
/// [SearchResult] in the service layer.
class SearchRow {
  const SearchRow({
    required this.itemId,
    required this.module,
    required this.title,
    required this.snippet,
  });

  final String itemId;
  final String module;
  final String title;

  /// A short excerpt of the matching body text, or empty for a title-only hit
  /// (the watchlist and the vault index no body — Requirement 9.5).
  final String snippet;
}

/// [SearchDao] queries the `search_index` FTS5 table behind Global Search
/// (Requirement 17).
///
/// It is a plain class over [AppDatabase] rather than a `@DriftAccessor`: the FTS
/// virtual table and its triggers are created by raw SQL in [AppDatabase] (drift
/// does not model FTS5), so there is no generated table to bind an accessor to.
///
/// The query orders by `bm25`, weighting a title hit far above a body hit, and is
/// the only thing on the < 300 ms read path Requirement 24.2 bounds.
class SearchDao {
  const SearchDao(this.db);

  final AppDatabase db;

  /// [search] returns the best [limit] matches for [match], an already-sanitised
  /// FTS5 MATCH expression (see `SearchService`).
  ///
  /// [item_id] and [module] are stored `UNINDEXED`, so each hit maps straight
  /// back to its row and its module. `snippet` is drawn from the body column
  /// (index 3), empty when a module indexes no body.
  Future<List<SearchRow>> search(String match, {int limit = 50}) async {
    final rows = await db.customSelect(
      'SELECT item_id, module, title, '
      "snippet(search_index, 3, '', '', '…', 8) AS snippet "
      'FROM search_index '
      'WHERE search_index MATCH ?1 '
      // Weights: item_id 0, module 0, title 10, body 1. Lower bm25 ranks higher,
      // so a title match sorts above a body match for the same term.
      'ORDER BY bm25(search_index, 0.0, 0.0, 10.0, 1.0) '
      'LIMIT ?2',
      variables: [Variable<String>(match), Variable<int>(limit)],
    ).get();

    return rows
        .map(
          (row) => SearchRow(
            itemId: row.read<String>('item_id'),
            module: row.read<String>('module'),
            title: row.read<String>('title'),
            snippet: row.read<String>('snippet'),
          ),
        )
        .toList();
  }
}
