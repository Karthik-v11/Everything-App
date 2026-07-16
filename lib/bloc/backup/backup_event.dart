part of 'backup_bloc.dart';

/// [BackupEvent] is the base class for every backup event.
abstract class BackupEvent extends Equatable {
  const BackupEvent();

  @override
  List<Object?> get props => [];
}

/// [InitBackupEvent] loads the on-device backup list and, if automatic backup is
/// on and one is overdue, takes one. Fired once at launch.
class InitBackupEvent extends BackupEvent {
  const InitBackupEvent();
}

/// [CreateBackupEvent] writes a new encrypted backup now (Requirement 22.1).
class CreateBackupEvent extends BackupEvent {
  const CreateBackupEvent();
}

/// [RestoreBackupEvent] verifies and applies the backup at [path]
/// (Requirement 22.6).
class RestoreBackupEvent extends BackupEvent {
  const RestoreBackupEvent({required this.path});

  final String path;

  @override
  List<Object?> get props => [path];
}

/// [DeleteBackupEvent] removes one backup file.
class DeleteBackupEvent extends BackupEvent {
  const DeleteBackupEvent({required this.path});

  final String path;

  @override
  List<Object?> get props => [path];
}

/// [ToggleAutoBackupEvent] turns the automatic scheduled backup on or off
/// (Requirement 22.4).
class ToggleAutoBackupEvent extends BackupEvent {
  const ToggleAutoBackupEvent({required this.isEnabled});

  final bool isEnabled;

  @override
  List<Object?> get props => [isEnabled];
}
