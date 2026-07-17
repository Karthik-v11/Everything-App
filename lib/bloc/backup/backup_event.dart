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

/// [CreateBackupEvent] writes a new encrypted backup now (Requirement 22.1),
/// sealed with the stored backup PIN. Fails plainly if none is set — the UI asks
/// for one first.
class CreateBackupEvent extends BackupEvent {
  const CreateBackupEvent();
}

/// [SetBackupPINEvent] chooses the PIN that new backups are sealed with.
class SetBackupPINEvent extends BackupEvent {
  const SetBackupPINEvent({required this.pin});

  final String pin;

  @override
  List<Object?> get props => [pin];
}

/// [RestoreBackupEvent] verifies and applies the backup at [path], unsealing it
/// with [pin] (Requirement 22.6).
///
/// [pin] is whatever the user typed at the restore prompt, not the stored one: the
/// file may have come from another phone and been sealed with a PIN this install
/// has never held.
class RestoreBackupEvent extends BackupEvent {
  const RestoreBackupEvent({required this.path, required this.pin});

  final String path;
  final String pin;

  @override
  List<Object?> get props => [path, pin];
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
