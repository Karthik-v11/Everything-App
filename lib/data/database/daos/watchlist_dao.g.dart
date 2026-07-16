// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'watchlist_dao.dart';

// ignore_for_file: type=lint
mixin _$WatchlistDaoMixin on DatabaseAccessor<AppDatabase> {
  $WatchlistTableTable get watchlistTable => attachedDatabase.watchlistTable;
  WatchlistDaoManager get managers => WatchlistDaoManager(this);
}

class WatchlistDaoManager {
  final _$WatchlistDaoMixin _db;
  WatchlistDaoManager(this._db);
  $$WatchlistTableTableTableManager get watchlistTable =>
      $$WatchlistTableTableTableManager(
        _db.attachedDatabase,
        _db.watchlistTable,
      );
}
