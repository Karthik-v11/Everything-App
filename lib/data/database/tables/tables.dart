import 'package:drift/drift.dart';

// The full schema, at schemaVersion 1. Every table is declared up front, even
// those not yet used, so that a new module adds a DAO and no migration.
//
// Conventions:
// - Primary keys are UUID v4 strings generated in Dart, never autoincrement
//   integers: backup/restore and any future sync must merge rows from two devices
//   without key collisions.
// - Enums are stored as their `name`, not their index. An index would remap every
//   existing row if the enum were ever reordered.
// - Money is an `IntColumn` in minor units (paise/cents).
// - Lists and maps are stored as JSON text, which keeps a read to a single row at
//   the cost of a join table — required by the < 200 ms create and < 300 ms search
//   budgets.

/// [TasksTable] holds tasks (Requirement 4).
///
/// [parentTaskId] chains a recurring task to the occurrence it was generated
/// from, so a series can be traced or bulk-edited later.
/// [completedAt] records when the status changed, which the status alone cannot
/// answer.
@DataClassName('TaskEntry')
class TasksTable extends Table {
  @override
  String get tableName => 'tasks';

  TextColumn get id => text()();
  TextColumn get title => text()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get priority => text().withDefault(const Constant('medium'))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get categoryId => text().nullable()();
  TextColumn get projectId => text().nullable()();
  TextColumn get parentTaskId => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get recurrenceJson => text().nullable()();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  TextColumn get remindersJson => text().withDefault(const Constant('[]'))();
  TextColumn get subtasksJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// [CategoriesTable] holds user-defined task categories (Work, Personal, …).
@DataClassName('CategoryEntry')
class CategoriesTable extends Table {
  @override
  String get tableName => 'categories';

  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get colorValue => integer()();
  TextColumn get iconName => text().nullable()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// [TransactionsTable] holds finance transactions (Requirement 12).
///
/// [amountMinor] is an **integer count of minor units** (paise), not a double.
/// Requirement/Property 6 forbids precision loss past two decimals and Property 7
/// sums an arbitrary sequence of expenses — binary floating point cannot promise
/// either under repeated addition. Convert at the UI edge with `Helpers`.
@DataClassName('TransactionEntry')
class TransactionsTable extends Table {
  @override
  String get tableName => 'transactions';

  TextColumn get id => text()();
  TextColumn get title => text()();
  IntColumn get amountMinor => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get type => text()(); // income | expense | transfer | investment
  TextColumn get category => text()();
  TextColumn get accountId => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// [AccountsTable] holds finance accounts — cash, bank, card, wallet, UPI.
@DataClassName('AccountEntry')
class AccountsTable extends Table {
  @override
  String get tableName => 'accounts';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  IntColumn get openingBalanceMinor =>
      integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// [BudgetsTable] holds one budget per month (Requirement 14).
///
/// [categoryLimitsJson] maps category name → limit in minor units.
@DataClassName('BudgetEntry')
class BudgetsTable extends Table {
  @override
  String get tableName => 'budgets';

  TextColumn get id => text()();
  IntColumn get monthlyLimitMinor => integer()();
  TextColumn get categoryLimitsJson =>
      text().withDefault(const Constant('{}'))();
  IntColumn get month => integer()();
  IntColumn get year => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// [BookmarksTable] holds saved links (Requirement 6).
@DataClassName('BookmarkEntry')
class BookmarksTable extends Table {
  @override
  String get tableName => 'bookmarks';

  TextColumn get id => text()();
  TextColumn get url => text()();
  TextColumn get title => text()();
  TextColumn get thumbnailUrl => text().nullable()();
  TextColumn get sourceType => text()();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  TextColumn get folderId => text().nullable()();
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// [ToBuyItemsTable] holds the shopping wishlist (Requirement 7).
@DataClassName('ToBuyItemEntry')
class ToBuyItemsTable extends Table {
  @override
  String get tableName => 'to_buy_items';

  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get estimatedPriceMinor => integer().nullable()();
  TextColumn get store => text().nullable()();
  TextColumn get priority => text().withDefault(const Constant('medium'))();
  BoolColumn get isPurchased => boolean().withDefault(const Constant(false))();
  DateTimeColumn get reminderAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// [WatchlistTable] tracks movies, shows, anime, manga, books, games (Req 8).
@DataClassName('WatchlistItemEntry')
class WatchlistTable extends Table {
  @override
  String get tableName => 'watchlist';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get mediaType => text()();
  TextColumn get status => text()();
  RealColumn get rating => real().nullable()();
  IntColumn get currentProgress => integer().nullable()();
  IntColumn get totalEpisodes => integer().nullable()();
  IntColumn get totalChapters => integer().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// [VaultItemsTable] holds secure items (Requirement 9).
///
/// Only [name] is plaintext — everything the user actually wants hidden lives in
/// [encryptedPayload], an AES-256 blob whose key never touches this table. The
/// database is *already* encrypted at rest; this second layer means a vault item
/// stays unreadable even to code that holds an open database handle, and it is
/// what lets Requirement 9.5 index vault items for search without indexing their
/// contents.
@DataClassName('VaultItemEntry')
class VaultItemsTable extends Table {
  @override
  String get tableName => 'vault_items';

  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get name => text()();
  TextColumn get encryptedPayload => text()();
  TextColumn get folderId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// [FoldersTable] holds folders for bookmarks and vault items alike.
///
/// [scope] keeps the two namespaces apart ('bookmark' | 'vault'). One table with
/// a discriminator beats two near-identical tables.
@DataClassName('FolderEntry')
class FoldersTable extends Table {
  @override
  String get tableName => 'folders';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get scope => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// [ProjectsTable] holds projects, which may nest (Requirement 10).
@DataClassName('ProjectEntry')
class ProjectsTable extends Table {
  @override
  String get tableName => 'projects';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get parentProjectId => text().nullable()();
  IntColumn get colorValue => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// [DocumentsTable] holds rich-text documents (Requirement 11).
///
/// [contentJson] is a Quill delta. [revisionsJson] is the version history, capped
/// at the 10 most recent (Requirement 11.3).
@DataClassName('DocumentEntry')
class DocumentsTable extends Table {
  @override
  String get tableName => 'documents';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get contentJson => text()();
  TextColumn get projectId => text().nullable()();
  TextColumn get revisionsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastAutoSavedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// [AttachmentsTable] holds files attached to any owner.
///
/// [ownerType] + [ownerId] is a deliberate polymorphic association: tasks,
/// transactions, projects and documents all take attachments, and four near-empty
/// join tables would buy nothing.
@DataClassName('AttachmentEntry')
class AttachmentsTable extends Table {
  @override
  String get tableName => 'attachments';

  TextColumn get id => text()();
  TextColumn get ownerType => text()(); // task | transaction | project | document
  TextColumn get ownerId => text()();
  TextColumn get filePath => text()();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get sizeBytes => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
