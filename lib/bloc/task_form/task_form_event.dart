part of 'task_form_bloc.dart';

/// [TaskFormEvent] is the base class for task form events.
abstract class TaskFormEvent extends Equatable {
  const TaskFormEvent();

  @override
  List<Object?> get props => [];
}

/// [SubmitTaskEvent] saves the form.
///
/// [task] is the fully assembled task. [isEditing] chooses between an insert and
/// an update — the form knows which it is, so the bloc does not have to guess from
/// whether an id happens to be present.
class SubmitTaskEvent extends TaskFormEvent {
  const SubmitTaskEvent({required this.task, this.isEditing = false});

  final Task task;
  final bool isEditing;

  @override
  List<Object?> get props => [task, isEditing];
}

/// [ResetTaskFormEvent] returns the bloc to its initial state.
///
/// Needed because the form bloc is app-scoped: without a reset, reopening the
/// sheet after a save would find it still in [TaskFormSuccess] and immediately
/// dismiss itself.
class ResetTaskFormEvent extends TaskFormEvent {
  const ResetTaskFormEvent();
}
