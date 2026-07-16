import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/data/models/backup_metadata.dart';
import 'package:everything_app/data/repositories/backup_repository.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'backup_event.dart';
part 'backup_state.dart';

/// [BackupBloc] owns the Backup, Restore & Export section (Requirement 22).
///
/// Style A, hydrated: it accumulates the automatic-backup preference, the last
/// backup time and the current file list. The preference and the timestamp
/// persist; the list is re-read from disk each launch.
///
/// **Automatic backup is opportunistic, not a background job.** A true scheduled
/// task belongs to the platform worker introduced in Phase 12 (WorkManager /
/// BGTask); until then, [InitBackupEvent] takes an overdue backup at launch when
/// the feature is on. That covers the common case — an app opened most days keeps
/// a recent backup — without a second, native moving part, and it composes with a
/// real scheduler later rather than being replaced by one.
///
/// Events:
/// 1) [InitBackupEvent] — load the list; back up if one is overdue.
/// 2) [CreateBackupEvent] — back up now.
/// 3) [RestoreBackupEvent] — verify and apply a backup (Requirement 22.6).
/// 4) [DeleteBackupEvent] — remove a backup file.
/// 5) [ToggleAutoBackupEvent] — turn automatic backup on or off.
class BackupBloc extends HydratedBloc<BackupEvent, BackupState> {
  BackupBloc({required this.repository}) : super(const BackupState()) {
    on<InitBackupEvent>(_onInitBackupEvent);
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
    await _refreshList(emit);

    final last = state.lastBackupAt;
    final isOverdue =
        last == null || DateTime.now().difference(last) >= autoBackupInterval;
    if (state.isAutoBackupEnabled && isOverdue) {
      await _createBackup(emit, isAutomatic: true);
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
  /// A failed integrity check comes back from the repository as a plain failure
  /// with the live data untouched, so it is surfaced like any other error — there
  /// is no separate "was anything changed?" branch, because on failure nothing was.
  FutureOr<void> _onRestoreBackupEvent(
    RestoreBackupEvent event,
    Emitter<BackupState> emit,
  ) async {
    emit(state.copyWith(isRestoring: true, error: '', message: ''));

    try {
      final response = await repository.restoreFromFile(event.path);
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

    // Turning it on with nothing to fall back to is the moment to take the first
    // one — otherwise the switch says "protected" while no backup exists.
    if (event.isEnabled && state.lastBackupAt == null) {
      await _createBackup(emit, isAutomatic: true);
    }
  }

  Future<void> _createBackup(
    Emitter<BackupState> emit, {
    required bool isAutomatic,
  }) async {
    emit(state.copyWith(isLoading: true, error: '', message: ''));

    try {
      final response = await repository.createBackup();
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
