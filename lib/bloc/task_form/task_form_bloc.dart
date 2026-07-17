import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/data/repositories/tasks_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'task_form_event.dart';
part 'task_form_state.dart';

/// [TaskFormBloc] saves a new or edited task (Requirement 4.4).
///
/// Holds no data between events: the saved task goes to the database and reaches
/// the UI through [TasksBloc]'s stream.
///
/// Separate from [TasksBloc] so a validation failure in the form does not put an
/// error on the state the task list renders from.
class TaskFormBloc extends Bloc<TaskFormEvent, TaskFormState> {
  TaskFormBloc({required this.repository}) : super(TaskFormInitial()) {
    on<SubmitTaskEvent>(_onSubmitTaskEvent);
    on<ResetTaskFormEvent>(_onResetTaskFormEvent);
  }

  final TasksRepository repository;

  FutureOr<void> _onSubmitTaskEvent(
    SubmitTaskEvent event,
    Emitter<TaskFormState> emit,
  ) async {
    emit(SavingTask());
    try {
      final response = event.isEditing
          ? await repository.update(event.task)
          : await repository.create(event.task);

      if (response.success) {
        emit(TaskFormSuccess(task: response.data! as Task));
      } else {
        emit(TaskFormFailure(message: response.message));
      }
    } catch (_) {
      emit(const TaskFormFailure(message: 'Something went wrong'));
    }
  }

  FutureOr<void> _onResetTaskFormEvent(
    ResetTaskFormEvent event,
    Emitter<TaskFormState> emit,
  ) {
    emit(TaskFormInitial());
  }
}
