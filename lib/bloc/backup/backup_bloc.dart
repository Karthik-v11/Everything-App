import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/data/models/backup_metadata.dart';
import 'package:everything_app/data/repositories/backup_repository.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'backup_event.dart';
part 'backup_state.dart';

/// [BackupBloc] owns the Backup, Restore & Export section (Requirement 22).
///
/// The auto-backup preference and last-backup time are hydrated; the file list is
/// re-read from disk each launch.
///
/// Automatic backup is opportunistic, not a background job: with no platform worker
/// (WorkManager / BGTask), [InitBackupEvent] takes an overdue backup at launch when
/// the feature is on.
///
/// Every backup is sealed with the user's backup PIN, so nothing here runs before
/// one is set. The file carries its own KDF salt, so the PIN alone unseals it on any
/// phone and no key has to survive an uninstall for a restore to work.
class BackupBloc extends HydratedBloc<BackupEvent, BackupState> {
  BackupBloc({required this.repository}) : super(const BackupState()) {
    on<InitBackupEvent>(_onInitBackupEvent);
    on<SetBackupPINEvent>(_onSetBackupPINEvent);
    on<CreateBackupEvent>(_onCreateBackupEvent);
    on<RestoreBackupEvent>(_onRestoreBackupEvent);
    on<DeleteBackupEvent>(_onDeleteBackupEvent);
    on<ToggleAutoBackupEvent>(_onToggleAutoBackupEvent);
  }

  final BackupRepository repository;

  /// [autoBackupInterval] is how stale the last backup may be before an automatic
  /// one is taken at launch (Requirement 22.4).
  static const Duration autoBackupInterval = Duration(days: 1);

  FutureOr<void> _onInitBackupEvent(
    InitBackupEvent event,
    Emitter<BackupState> emit,
  ) async {
    emit(state.copyWith(hasBackupPIN: await repository.hasBackupPIN()));
    await _refreshList(emit);

    final last = state.lastBackupAt;
    final isOverdue =
        last == null || DateTime.now().difference(last) >= autoBackupInterval;

    // No PIN means nothing to seal with; the Settings tile asks for one. Skipping
    // quietly leaves the preference on, so a backup happens once a PIN exists.
    if (state.isAutoBackupEnabled && state.hasBackupPIN && isOverdue) {
      await _createBackup(emit, isAutomatic: true);
    }
  }

  FutureOr<void> _onSetBackupPINEvent(
    SetBackupPINEvent event,
    Emitter<BackupState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: '', message: ''));

    try {
      final response = await repository.setBackupPIN(event.pin);
      emit(
        response.success
            ? state.copyWith(
                isLoading: false,
                hasBackupPIN: true,
                message: response.message,
              )
            : state.copyWith(isLoading: false, error: response.message),
      );
    } on Exception {
      emit(
        state.copyWith(isLoading: false, error: 'Could not save your backup PIN.'),
      );
    }
  }

  FutureOr<void> _onCreateBackupEvent(
    CreateBackupEvent event,
    Emitter<BackupState> emit,
  ) async {
    await _createBackup(emit, isAutomatic: false);
  }

  /// [_onRestoreBackupEvent] verifies and applies a backup (Requirement 22.6).
  ///
  /// A failed integrity check returns a plain failure with the live data untouched,
  /// so it needs no separate "was anything changed?" branch.
  FutureOr<void> _onRestoreBackupEvent(
    RestoreBackupEvent event,
    Emitter<BackupState> emit,
  ) async {
    emit(state.copyWith(isRestoring: true, error: '', message: ''));

    try {
      final response = await repository.restoreFromFile(event.path, pin: event.pin);
      emit(
        response.success
            ? state.copyWith(isRestoring: false, message: response.message)
            : state.copyWith(isRestoring: false, error: response.message),
      );
    } on Exception {
      emit(
        state.copyWith(isRestoring: false, error: 'Could not restore the backup.'),
      );
    }
  }

  FutureOr<void> _onDeleteBackupEvent(
    DeleteBackupEvent event,
    Emitter<BackupState> emit,
  ) async {
    try {
      final response = await repository.deleteBackup(event.path);
      if (!response.success) {
        emit(state.copyWith(error: response.message));
        return;
      }
      await _refreshList(emit);
      emit(state.copyWith(message: response.message));
    } on Exception {
      emit(state.copyWith(error: 'Could not delete the backup.'));
    }
  }

  FutureOr<void> _onToggleAutoBackupEvent(
    ToggleAutoBackupEvent event,
    Emitter<BackupState> emit,
  ) async {
    emit(
      state.copyWith(
        isAutoBackupEnabled: event.isEnabled,
        error: '',
        message: '',
      ),
    );

    // Take the first backup on enable, or the switch says "protected" while none
    // exists.
    if (event.isEnabled && state.hasBackupPIN && state.lastBackupAt == null) {
      await _createBackup(emit, isAutomatic: true);
    }
  }

  Future<void> _createBackup(
    Emitter<BackupState> emit, {
    required bool isAutomatic,
  }) async {
    emit(state.copyWith(isLoading: true, error: '', message: ''));

    try {
      final pin = await repository.backupPIN();
      if (!pin.success) {
        emit(state.copyWith(isLoading: false, error: pin.message));
        return;
      }

      final response = await repository.createBackup(pin: pin.data! as String);
      if (!response.success) {
        emit(state.copyWith(isLoading: false, error: response.message));
        return;
      }

      final metadata = response.data! as BackupMetadata;
      emit(state.copyWith(isLoading: false, lastBackupAt: metadata.createdAt));
      await _refreshList(emit);
      emit(
        state.copyWith(
          message: isAutomatic ? 'Automatic backup created.' : response.message,
        ),
      );
    } on Exception {
      emit(state.copyWith(isLoading: false, error: 'Could not create a backup.'));
    }
  }

  Future<void> _refreshList(Emitter<BackupState> emit) async {
    final response = await repository.listBackups();
    if (response.success) {
      emit(state.copyWith(backups: response.data! as List<BackupMetadata>));
    }
  }

  @override
  BackupState? fromJson(Map<String, dynamic> json) => BackupState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(BackupState state) => state.toJson();
}
