part of 'storage_bloc.dart';

/// [StorageEvent] is the base class for every storage event.
abstract class StorageEvent extends Equatable {
  const StorageEvent();

  @override
  List<Object?> get props => [];
}

/// [ReadStorageEvent] measures the app's storage (Requirement 25.4). Dispatched
/// on section open and pull-to-refresh — never on a write: the measurement is a
/// `dbstat` scan plus two directory walks.
class ReadStorageEvent extends StorageEvent {
  const ReadStorageEvent();
}
