import 'package:equatable/equatable.dart';

/// [StorageModule] is a line in the Storage Usage section (Requirement 25.4).
///
/// The requirement names Tasks, Library, Finance and the AI model; [search],
/// [backups] and [other] are here so the parts add up to the total. [other] is
/// what is left — schema, free pages, drift's bookkeeping — rather than the
/// difference being rounded into one of the named modules.
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
  /// counts without byte figures. Surfaced to the UI so the screen does not claim
  /// a size it does not know.
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
