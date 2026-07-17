part of 'backup_bloc.dart';

/// [BackupState] holds the backup section's state (Requirement 22).
///
/// Only the auto-backup preference and last backup time are persisted; [backups] is
/// re-read from the filesystem on launch, since a file deleted by the OS or another
/// install would make a remembered list wrong.
class BackupState extends Equatable {
  const BackupState({
    this.isLoading = false,
    this.isRestoring = false,
    this.error = '',
    this.message = '',
    this.isAutoBackupEnabled = false,
    this.hasBackupPIN = false,
    this.lastBackupAt,
    this.backups = const [],
  });

  final bool isLoading;

  /// Kept apart from [isLoading] so a restore can block the whole screen while a
  /// backup merely creates in the background.
  final bool isRestoring;

  final String error;
  final String message;

  /// Whether an overdue backup is taken automatically at launch (Requirement 22.4).
  final bool isAutoBackupEnabled;

  /// Whether a backup PIN has been chosen. Read from secure storage at launch, never
  /// persisted here: a remembered `true` would outlive an uninstall that cleared the
  /// keystore.
  final bool hasBackupPIN;

  /// When the most recent backup was written, or null if none has been.
  final DateTime? lastBackupAt;

  final List<BackupMetadata> backups;

  BackupState copyWith({
    bool? isLoading,
    bool? isRestoring,
    String? error,
    String? message,
    bool? isAutoBackupEnabled,
    bool? hasBackupPIN,
    DateTime? lastBackupAt,
    List<BackupMetadata>? backups,
  }) =>
      BackupState(
        isLoading: isLoading ?? this.isLoading,
        isRestoring: isRestoring ?? this.isRestoring,
        error: error ?? this.error,
        message: message ?? this.message,
        isAutoBackupEnabled: isAutoBackupEnabled ?? this.isAutoBackupEnabled,
        hasBackupPIN: hasBackupPIN ?? this.hasBackupPIN,
        lastBackupAt: lastBackupAt ?? this.lastBackupAt,
        backups: backups ?? this.backups,
      );

  /// [fromJson] restores only the user's preference and the last backup time. The
  /// list is streamed from disk, not persisted.
  factory BackupState.fromJson(Map<String, dynamic> json) => BackupState(
        isAutoBackupEnabled: json['HydratedAutoBackup'] as bool? ?? false,
        lastBackupAt: json['HydratedLastBackupAt'] == null
            ? null
            : DateTime.tryParse(json['HydratedLastBackupAt'].toString()),
      );

  Map<String, dynamic> toJson() => {
        'HydratedAutoBackup': isAutoBackupEnabled,
        'HydratedLastBackupAt': lastBackupAt?.toIso8601String(),
      };

  @override
  List<Object?> get props => [
        isLoading,
        isRestoring,
        error,
        message,
        isAutoBackupEnabled,
        hasBackupPIN,
        lastBackupAt,
        backups,
      ];
}
