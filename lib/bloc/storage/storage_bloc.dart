import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/data/models/storage_usage.dart';
import 'package:everything_app/data/repositories/storage_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'storage_event.dart';
part 'storage_state.dart';

/// [StorageBloc] drives the Storage Usage section (Requirement 25.4).
///
/// Nothing is persisted: a remembered figure is wrong the moment anything is
/// written.
///
/// Deliberately **not** driven off the DAO streams the way `HomeWidgetBloc` is —
/// measuring costs a `dbstat` scan and two directory walks, too much to repeat on
/// every write for a section only visible at the bottom of Settings. Read on open,
/// re-read on request.
class StorageBloc extends Bloc<StorageEvent, StorageState> {
  StorageBloc({required this.repository}) : super(const StorageInitial()) {
    on<ReadStorageEvent>(_onReadStorageEvent);
  }

  final StorageRepository repository;

  FutureOr<void> _onReadStorageEvent(
    ReadStorageEvent event,
    Emitter<StorageState> emit,
  ) async {
    emit(const StorageLoading());

    try {
      final response = await repository.read();

      emit(
        response.success
            ? StorageLoaded(usage: response.data! as StorageUsage)
            : StorageFailure(message: response.message),
      );
    } on Exception {
      emit(const StorageFailure(message: 'Could not measure storage.'));
    }
  }
}
