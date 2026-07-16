import 'dart:math';

import 'package:drift/drift.dart' show Variable;
import 'package:everything_app/data/database/app_database.dart';
import 'package:everything_app/data/database/daos/search_dao.dart';
import 'package:everything_app/data/models/search_result.dart';
import 'package:everything_app/data/services/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Global Search — Property 5 and the < 300 ms bar over 10,000 items
/// (Requirements 17, 24.2).
///
/// These run against a real Drift database in memory, so the FTS5 index and its
/// triggers — created in `AppDatabase.migration.beforeOpen` — are exercised
/// exactly as they are on device. Rows are inserted with raw SQL so the seed does
/// not depend on eight services; the triggers fire regardless of how a row
/// arrives, which is the whole point of maintaining the index in the database.
void main() {
  late AppDatabase database;
  late SearchService service;

  // A fixed timestamp for every row: the columns are not read by search.
  const stamp = 1700000000;

  Future<void> insertTask(String id, String title, [String? notes]) =>
      database.customInsert(
        'INSERT INTO tasks (id, title, notes, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?)',
        variables: [
          Variable<String>(id),
          Variable<String>(title),
          Variable<String>(notes),
          const Variable<int>(stamp),
          const Variable<int>(stamp),
        ],
      );

  Future<void> insertTransaction(String id, String title, String category) =>
      database.customInsert(
        'INSERT INTO transactions '
        '(id, title, amount_minor, date, type, category, account_id, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable<String>(id),
          Variable<String>(title),
          const Variable<int>(1000),
          const Variable<int>(stamp),
          const Variable<String>('expense'),
          Variable<String>(category),
          const Variable<String>('account-1'),
          const Variable<int>(stamp),
        ],
      );

  Future<void> insertBookmark(String id, String title, String url) =>
      database.customInsert(
        'INSERT INTO bookmarks '
        '(id, url, title, source_type, saved_at) VALUES (?, ?, ?, ?, ?)',
        variables: [
          Variable<String>(id),
          Variable<String>(url),
          Variable<String>(title),
          const Variable<String>('website'),
          const Variable<int>(stamp),
        ],
      );

  Future<void> insertWatchlist(String id, String title) =>
      database.customInsert(
        'INSERT INTO watchlist '
        '(id, title, media_type, status, created_at) VALUES (?, ?, ?, ?, ?)',
        variables: [
          Variable<String>(id),
          Variable<String>(title),
          const Variable<String>('movie'),
          const Variable<String>('wishlist'),
          const Variable<int>(stamp),
        ],
      );

  /// Vault rows carry a plaintext [name] and an opaque [payload]. Only the name
  /// is ever indexed (Requirement 9.5).
  Future<void> insertVault(String id, String name, String payload) =>
      database.customInsert(
        'INSERT INTO vault_items '
        '(id, type, name, encrypted_payload, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        variables: [
          Variable<String>(id),
          const Variable<String>('password'),
          Variable<String>(name),
          Variable<String>(payload),
          const Variable<int>(stamp),
          const Variable<int>(stamp),
        ],
      );

  Future<void> insertDocument(String id, String title, String content) =>
      database.customInsert(
        'INSERT INTO documents '
        '(id, title, content_json, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?)',
        variables: [
          Variable<String>(id),
          Variable<String>(title),
          Variable<String>(content),
          const Variable<int>(stamp),
          const Variable<int>(stamp),
        ],
      );

  setUp(() {
    database = AppDatabase.memory();
    service = SearchService(dao: SearchDao(database));
  });

  tearDown(() => database.close());

  group('Property 5 — results only ever match the query', () {
    // Feature: everything-app, Property 5: For any non-empty query run against up
    // to 10,000 items, every result contains the query in a searchable field, and
    // no result is from a module that was not queried.

    test('every result contains the queried term in a searchable field',
        () async {
      await insertTask('t1', 'Quarterly report draft');
      await insertTask('t2', 'Buy milk', 'from the corner shop');
      await insertTransaction('x1', 'Report printing', 'Office');
      await insertBookmark('b1', 'Reporting tools', 'https://example.com');
      await insertDocument('d1', 'Meeting notes', 'the annual report is due');
      await insertWatchlist('w1', 'The Departed');

      final response = await service.search('report');
      final results = response.data! as List<SearchResult>;

      expect(results, isNotEmpty);
      // Every hit contains the term in its title or its body snippet.
      for (final result in results) {
        final haystack = '${result.title} ${result.subtitle}'.toLowerCase();
        expect(
          haystack.contains('report'),
          isTrue,
          reason: 'result "${result.title}" does not contain the query',
        );
      }
      // Nothing that lacks the term leaks in.
      final ids = results.map((r) => r.id).toSet();
      expect(ids, containsAll(<String>['t1', 'x1', 'b1', 'd1']));
      expect(ids, isNot(contains('t2')));
      expect(ids, isNot(contains('w1')));
    });

    test('every result belongs to a real, queried module', () async {
      await insertTask('t1', 'Alpha task');
      await insertBookmark('b1', 'Alpha bookmark', 'https://alpha.example');
      await insertVault('v1', 'Alpha vault', 'nothing');

      final response = await service.search('alpha');
      final results = response.data! as List<SearchResult>;

      expect(results, isNotEmpty);
      for (final result in results) {
        expect(SearchModule.values, contains(result.module));
      }
    });

    test('a blank or punctuation-only query returns nothing, not an error',
        () async {
      await insertTask('t1', 'Something');

      for (final query in ['', '   ', '***', '"()"']) {
        final response = await service.search(query);
        expect(response.success, isTrue, reason: 'query "$query"');
        expect(response.data! as List<SearchResult>, isEmpty);
      }
    });
  });

  group('Requirement 9.5 — the vault indexes its title only', () {
    test('a vault item matches on its name', () async {
      await insertVault('v1', 'Netflix login', 'secretpayloadtoken');

      final results =
          (await service.search('netflix')).data! as List<SearchResult>;

      expect(results.map((r) => r.id), contains('v1'));
      expect(
        results.firstWhere((r) => r.id == 'v1').module,
        SearchModule.vault,
      );
    });

    test('a vault item never matches on its encrypted payload', () async {
      // The payload holds a distinctive token that appears nowhere else. If it
      // were indexed, this search would surface the vault item.
      await insertVault('v1', 'Netflix login', 'secretpayloadtoken');

      final results =
          (await service.search('secretpayloadtoken')).data! as List<SearchResult>;

      expect(
        results.where((r) => r.module == SearchModule.vault),
        isEmpty,
        reason: 'encrypted payload must never enter the search index',
      );
    });
  });

  group('Requirement 24.2 — search stays under 300 ms over 10,000 items', () {
    test('a query over a seeded 10k dataset returns within the budget',
        () async {
      final random = Random(24);
      const words = [
        'alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf',
        'hotel', 'india', 'juliet', 'report', 'invoice', 'meeting', 'travel',
        'grocery', 'project', 'design', 'review', 'budget', 'holiday',
      ];

      String phrase() => List.generate(
            3,
            (_) => words[random.nextInt(words.length)],
          ).join(' ');

      // 10,000 rows spread across the eight modules, inserted in one transaction
      // so the FTS triggers fire but the seed stays fast.
      await database.transaction(() async {
        for (var i = 0; i < 2000; i++) {
          await insertTask('task-$i', 'Task ${phrase()}');
        }
        for (var i = 0; i < 2000; i++) {
          await insertTransaction('txn-$i', 'Txn ${phrase()}', 'Category');
        }
        for (var i = 0; i < 1500; i++) {
          await insertBookmark(
            'bm-$i',
            'Bookmark ${phrase()}',
            'https://example.com/$i',
          );
        }
        for (var i = 0; i < 1000; i++) {
          await insertWatchlist('wl-$i', 'Watch ${phrase()}');
        }
        for (var i = 0; i < 1000; i++) {
          await insertVault('vault-$i', 'Vault ${phrase()}', 'payload-$i');
        }
        for (var i = 0; i < 1000; i++) {
          await insertDocument('doc-$i', 'Doc ${phrase()}', phrase());
        }
        // Tasks with notes make up the remaining 1,500.
        for (var i = 0; i < 1500; i++) {
          await insertTask('note-$i', 'Note ${phrase()}', phrase());
        }
      });

      final total = await database
          .customSelect('SELECT count(*) AS c FROM search_index')
          .getSingle();
      expect(total.read<int>('c'), 10000);

      // Warm up once — the first query compiles the statement — then measure.
      await service.search('report');

      for (final term in ['report', 'meeting', 'alpha', 'budget review']) {
        final watch = Stopwatch()..start();
        final response = await service.search(term);
        watch.stop();

        expect(response.success, isTrue);
        expect(
          watch.elapsedMilliseconds,
          lessThan(300),
          reason: 'query "$term" took ${watch.elapsedMilliseconds}ms',
        );
      }
    });
  });
}
