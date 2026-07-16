part of 'storage_bloc.dart';

/// [StorageState] is the Storage Usage section's state (Requirement 25.4).
///
/// **Style B**, as a Dart 3 `sealed class`, so the section's builder is an
/// exhaustive `switch` and a state added later cannot be forgotten at the one
/// place that renders it.
sealed class StorageState extends Equatable {
  const StorageState();

  @override
  List<Object?> get props => [];
}

/// [StorageInitial] is before the section has been opened. Nothing has been
/// measured and nothing is being measured.
class StorageInitial extends StorageState {
  const StorageInitial();
}

/// [StorageLoading] is a measurement in flight. It carries no data — a partial
/// breakdown is not a breakdown.
class StorageLoading extends StorageState {
  const StorageLoading();
}

class StorageLoaded extends StorageState {
  const StorageLoaded({required this.usage});

  final StorageUsage usage;

  @override
  List<Object?> get props => [usage];
}

class StorageFailure extends StorageState {
  const StorageFailure({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}
