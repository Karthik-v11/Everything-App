import 'package:bloc_test/bloc_test.dart';
import 'package:everything_app/bloc/bookmarks/bookmarks_bloc.dart';
import 'package:everything_app/bloc/documents/documents_bloc.dart';
import 'package:everything_app/bloc/projects/projects_bloc.dart';
import 'package:everything_app/bloc/to_buy/to_buy_bloc.dart';
import 'package:everything_app/bloc/vault/vault_bloc.dart';
import 'package:everything_app/bloc/watchlist/watchlist_bloc.dart';
import 'package:everything_app/data/models/bookmark.dart';
import 'package:everything_app/data/models/document.dart';
import 'package:everything_app/data/models/project.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/data/models/to_buy_item.dart';
import 'package:everything_app/data/models/vault_item.dart';
import 'package:everything_app/data/models/watchlist_item.dart';
import 'package:everything_app/view/screens/library/library_page.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

/// The Library hub is assembled from six blocs that never talk to each other, and
/// every count on it is derived — bookmarks by list length, To Buys by what is
/// still unbought, the Watchlist by what is being watched *now* rather than ever.
/// Those derivations live in the tiles, so nothing but a rendered hub can catch a
/// tile that starts counting the wrong thing, or a sixth bloc's empty state
/// quietly swallowing the section under it.
///
/// This golden is the reference UI itself held still: the amber icon chips, the
/// count-leads-then-label tile, the vault's lock badge, and the project cards.
void main() {
  final createdAt = DateTime(2026, 1, 2, 10);

  final bookmarks = BookmarksState(
    bookmarks: [
      Bookmark(
        id: 'b1',
        url: 'https://dart.dev/effective-dart',
        title: 'Effective Dart',
        savedAt: createdAt,
        sourceType: BookmarkSource.article,
      ),
      Bookmark(
        id: 'b2',
        url: 'https://github.com/flutter/flutter',
        title: 'flutter/flutter',
        savedAt: createdAt,
        sourceType: BookmarkSource.github,
      ),
      Bookmark(
        id: 'b3',
        url: 'https://youtu.be/xyz',
        title: 'Impeller, explained',
        savedAt: createdAt,
        sourceType: BookmarkSource.youtube,
      ),
    ],
  );

  final toBuy = ToBuyState(
    items: [
      ToBuyItem(
        id: 't1',
        name: 'Coffee beans',
        createdAt: createdAt,
        estimatedPriceMinor: 90000,
        store: 'Blue Tokai',
        priority: TaskPriority.high,
      ),
      ToBuyItem(id: 't2', name: 'USB-C cable', createdAt: createdAt),
      // Purchased, so the tile's count must not include it.
      ToBuyItem(
        id: 't3',
        name: 'Notebook',
        createdAt: createdAt,
        isPurchased: true,
      ),
    ],
  );

  final watchlist = WatchlistState(
    items: [
      WatchlistItem(
        id: 'w1',
        title: 'Dune: Part Two',
        mediaType: MediaType.movie,
        createdAt: createdAt,
        status: WatchStatus.watching,
      ),
      WatchlistItem(
        id: 'w2',
        title: 'Frieren',
        mediaType: MediaType.anime,
        createdAt: createdAt,
        status: WatchStatus.watching,
      ),
      // Completed, so the "in progress" count must not include it.
      WatchlistItem(
        id: 'w3',
        title: 'The Expanse',
        mediaType: MediaType.tvShow,
        createdAt: createdAt,
        status: WatchStatus.completed,
      ),
    ],
  );

  final vault = VaultState(
    items: [
      VaultItem(
        id: 'v1',
        type: VaultItemType.password,
        name: 'Bank login',
        encryptedPayload: 'ciphertext',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      VaultItem(
        id: 'v2',
        type: VaultItemType.identity,
        name: 'Passport',
        encryptedPayload: 'ciphertext',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    ],
  );

  final projects = ProjectsState(
    projects: [
      Project(
        id: 'p1',
        name: 'Everything App',
        description: 'The offline-first personal dashboard.',
        createdAt: createdAt,
        updatedAt: createdAt,
        colorValue: 0xFFFFB300,
      ),
      // A sub-project: it must not appear as a root, only in its parent's count.
      Project(
        id: 'p2',
        name: 'Phase 14 — Hardening',
        parentProjectId: 'p1',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      Project(
        id: 'p3',
        name: 'Flat renovation',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    ],
  );

  final documents = DocumentsState(
    documents: [
      Document(
        id: 'd1',
        title: 'Reading list',
        content: 'Designing Data-Intensive Applications, then SICP.',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      // Filed under a project, so the Notes section must not list it.
      Document(
        id: 'd2',
        title: 'Phase notes',
        content: 'Golden tests for the four reference screens.',
        projectId: 'p1',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    ],
  );

  testWidgets('the Library hub renders its collections, projects and notes',
      (tester) async {
    await freeze(() async {
      final bookmarksBloc = MockBookmarksBloc();
      final toBuyBloc = MockToBuyBloc();
      final watchlistBloc = MockWatchlistBloc();
      final vaultBloc = MockVaultBloc();
      final projectsBloc = MockProjectsBloc();
      final documentsBloc = MockDocumentsBloc();

      whenListen(bookmarksBloc, const Stream<BookmarksState>.empty(),
          initialState: bookmarks);
      whenListen(toBuyBloc, const Stream<ToBuyState>.empty(),
          initialState: toBuy);
      whenListen(watchlistBloc, const Stream<WatchlistState>.empty(),
          initialState: watchlist);
      whenListen(vaultBloc, const Stream<VaultState>.empty(),
          initialState: vault);
      whenListen(projectsBloc, const Stream<ProjectsState>.empty(),
          initialState: projects);
      whenListen(documentsBloc, const Stream<DocumentsState>.empty(),
          initialState: documents);

      await pumpGolden(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider<BookmarksBloc>.value(value: bookmarksBloc),
            BlocProvider<ToBuyBloc>.value(value: toBuyBloc),
            BlocProvider<WatchlistBloc>.value(value: watchlistBloc),
            BlocProvider<VaultBloc>.value(value: vaultBloc),
            BlocProvider<ProjectsBloc>.value(value: projectsBloc),
            BlocProvider<DocumentsBloc>.value(value: documentsBloc),
          ],
          child: const LibraryPage(),
        ),
      );

      // The counts are the whole point of the tiles, so they are asserted here as
      // well as in the pixels: a golden alone would happily record "0 saved".
      expect(find.text('3'), findsOneWidget, reason: '3 bookmarks');
      expect(find.text('2'), findsWidgets, reason: '2 to buy, 2 watching, 2 vault');
      expect(find.text('Flat renovation'), findsOneWidget,
          reason: 'the second root project is listed');
      expect(find.text('Phase 14 — Hardening'), findsNothing,
          reason: 'a sub-project is not a root');

      await expectLater(
        find.byType(LibraryPage),
        matchesGoldenFile('goldens/library_page.png'),
      );
    });
  });
}
