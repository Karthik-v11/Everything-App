import 'package:equatable/equatable.dart';

/// [StorageModule] is a line in the Storage Usage section (Requirement 25.4).
///
/// The requirement names Tasks, Library, Finance and the AI model; [search],
/// [backups] and [other] are here because they are real consumers on a device and
/// a breakdown whose parts do not add up to the total is a breakdown nobody
/// believes. [other] is what is left — the schema, free pages, drift's own
/// bookkeeping — and it exists so the arithmetic closes honestly rather than by
/// quietly rounding the difference into one of the named modules.
enum StorageModule {
  tasks,
  library,
  finance,
  search,
  backups,
  aiModel,
  other;

  String get label => switch (this) {
        StorageModule.tasks => 'Tasks',
        StorageModule.library => 'Library',
        StorageModule.finance => 'Finance',
        StorageModule.search => 'Search index',
        StorageModule.backups => 'Backups',
        StorageModule.aiModel => 'AI model',
        StorageModule.other => 'Other',
      };
}

/// [StorageLine] is one module's usage.
class StorageLine extends Equatable {
  const StorageLine({
    required this.module,
    required this.bytes,
    this.itemCount,
    this.detail = '',
  });

  final StorageModule module;
  final int bytes;

  /// How many rows the module holds, where that is a meaningful thing to say.
  /// Null for the ones it is not — the AI model is not a count of anything.
  final int? itemCount;

  /// A short qualifier, used where a size alone would mislead — "Not installed"
  /// against an AI model that is a rule-based parser occupying nothing.
  final String detail;

  @override
  List<Object?> get props => [module, bytes, itemCount, detail];
}

/// [StorageUsage] is the whole breakdown (Requirement 25.4).
class StorageUsage extends Equatable {
  const StorageUsage({
    required this.lines,
    required this.databaseBytes,
    required this.attachmentBytes,
    required this.isEstimated,
  });

  final List<StorageLine> lines;

  /// The encrypted database file, as it sits on disk.
  final int databaseBytes;

  /// Attachment files, which live beside the database rather than in it.
  final int attachmentBytes;

  /// True when the per-module split could not be measured and the lines are row
  /// counts without byte figures.
  ///
  /// Surfaced to the UI rather than hidden, because "Tasks — 142 items" and
  /// "Tasks — 142 items, 2.1 MB" are different claims and the screen should not
  /// make the second one when only the first is known.
  final bool isEstimated;

  int get totalBytes => databaseBytes + attachmentBytes + _backupBytes;

  int get _backupBytes => lines
      .where((line) => line.module == StorageModule.backups)
      .fold(0, (sum, line) => sum + line.bytes);

  @override
  List<Object?> get props => [
        lines,
        databaseBytes,
        attachmentBytes,
        isEstimated,
      ];
}
