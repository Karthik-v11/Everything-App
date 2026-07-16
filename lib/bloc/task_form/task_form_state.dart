part of 'task_form_bloc.dart';

/// [TaskFormState] is the abstract base class for all task form states.
abstract class TaskFormState extends Equatable {
  const TaskFormState();

  @override
  List<Object> get props => [];
}

/// [TaskFormInitial] is the idle state — the form is open and untouched.
class TaskFormInitial extends TaskFormState {}

/// [SavingTask] is emitted while the write is in flight.
class SavingTask extends TaskFormState {}

/// [TaskFormSuccess] is emitted when the task has been saved.
/// [task] is the saved task, with its generated id and timestamps.
class TaskFormSuccess extends TaskFormState {
  const TaskFormSuccess({required this.task});

  final Task task;

  @override
  List<Object> get props => [task];
}

/// [TaskFormFailure] is emitted when the save fails.
/// [message] is always present and safe to show the user.
class TaskFormFailure extends TaskFormState {
  const TaskFormFailure({required this.message});

  final String message;

  @override
  List<Object> get props => [message];
}
