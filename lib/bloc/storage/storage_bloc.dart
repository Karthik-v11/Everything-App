import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/data/models/storage_usage.dart';
import 'package:everything_app/data/repositories/storage_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'storage_event.dart';
part 'storage_state.dart';

/// [StorageBloc] drives the Storage Usage section (Requirement 25.4).
///
/// **Style B**: one focused async action with no accumulated state — the usage is
/// read, and the state is exactly one of loading, loaded or failed. There is
/// nothing to keep across events and nothing to persist: a remembered figure is a
/// figure that is wrong the moment anything is written, and this is the one screen
/// where the whole point is that the number is current.
///
/// It is deliberately **not** driven off the DAO streams the way `HomeWidgetBloc`
/// is. Measuring means a `dbstat` scan and two directory walks, and doing that on
/// every write in the app — to keep a section fresh that is only visible when the
/// user has scrolled to the bottom of Settings — would be work nobody asked for.
/// It is read when the section is opened, and re-read when the user asks.
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
