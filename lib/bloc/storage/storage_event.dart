part of 'storage_bloc.dart';

/// [StorageEvent] is the base class for every storage event.
abstract class StorageEvent extends Equatable {
  const StorageEvent();

  @override
  List<Object?> get props => [];
}

/// [ReadStorageEvent] measures the app's storage (Requirement 25.4).
///
/// Dispatched when the Storage section is opened and when the user pulls to
/// refresh it — never on a write, because the measurement is a `dbstat` scan and
/// two directory walks and nothing is reading the result until the section is on
/// screen.
class ReadStorageEvent extends StorageEvent {
  const ReadStorageEvent();
}
