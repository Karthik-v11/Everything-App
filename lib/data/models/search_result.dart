import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// [SearchModule] is one of the eight modules Global Search spans
/// (Requirement 17.1).
///
/// The stored `name` (matched by [fromName]) is the discriminator written into
/// the FTS index by the triggers in `AppDatabase`, so these names must stay in
/// step with `AppDatabase._searchSources`.
enum SearchModule {
  tasks('tasks', 'Tasks', Icons.check_circle_outline_rounded),
  transactions('transactions', 'Finance', Icons.account_balance_wallet_outlined),
  bookmarks('bookmarks', 'Bookmarks', Icons.bookmark_outline_rounded),
  toBuy('to_buy', 'To Buy', Icons.shopping_bag_outlined),
  watchlist('watchlist', 'Watchlist', Icons.play_circle_outline_rounded),
  vault('vault', 'Vault', Icons.lock_outline_rounded),
  projects('projects', 'Projects', Icons.folder_outlined),
  documents('documents', 'Documents', Icons.description_outlined);

  const SearchModule(this.id, this.label, this.icon);

  /// The value stored in the index's `module` column.
  final String id;

  /// The section heading a group of results wears.
  final String label;

  final IconData icon;

  static SearchModule? fromName(String? id) {
    for (final module in SearchModule.values) {
      if (module.id == id) return module;
    }
    return null;
  }
}

/// [SearchResult] is one hit rendered on the search screen (Requirement 17.2).
///
/// It carries only what a result row shows and what tapping it needs — the
/// owning [module] and the [id] to open. The full model is fetched by the
/// destination screen, not here: a search list holding decrypted vault items or
/// full document bodies would defeat the point of both.
class SearchResult extends Equatable {
  const SearchResult({
    required this.module,
    required this.id,
    required this.title,
    this.subtitle = '',
  });

  final SearchModule module;
  final String id;
  final String title;

  /// A short excerpt of the matching body text, empty for a title-only hit. The
  /// vault never has one — its contents are encrypted and unindexed
  /// (Requirement 9.5).
  final String subtitle;

  @override
  List<Object?> get props => [module, id, title, subtitle];
}
