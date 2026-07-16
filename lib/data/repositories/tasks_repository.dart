import 'package:everything_app/data/models/category.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/data/services/tasks_service.dart';

/// [TasksRepository] defines the contract for task persistence.
abstract class TasksRepository {
  /// [watchAll] streams every task, refreshing on any change to the table.
  Stream<List<Task>> watchAll();

  /// [watchCategories] streams the category list.
  Stream<List<Category>> watchCategories();

  /// [categories] reads the categories once.
  Future<JsonResponse> categories();

  /// [seedDefaultCategories] installs the starter categories on first launch.
  Future<JsonResponse> seedDefaultCategories();

  /// [create] inserts a task. Fails on a blank title.
  Future<JsonResponse> create(Task task);

  /// [update] saves an edited task.
  Future<JsonResponse> update(Task task);

  /// [setCompleted] completes or re-opens a task, generating the next occurrence
  /// of a recurring task on completion.
  Future<JsonResponse> setCompleted({
    required Task task,
    required bool isCompleted,
  });

  /// [delete] removes a task by id.
  Future<JsonResponse> delete(String id);
}

class TasksRepositoryImpl implements TasksRepository {
  const TasksRepositoryImpl({required this.tasksService});

  final TasksService tasksService;

  @override
  Stream<List<Task>> watchAll() => tasksService.watchAll();

  @override
  Stream<List<Category>> watchCategories() => tasksService.watchCategories();

  @override
  Future<JsonResponse> categories() => tasksService.categories();

  @override
  Future<JsonResponse> seedDefaultCategories() =>
      tasksService.seedDefaultCategories();

  @override
  Future<JsonResponse> create(Task task) => tasksService.create(task);

  @override
  Future<JsonResponse> update(Task task) => tasksService.update(task);

  @override
  Future<JsonResponse> setCompleted({
    required Task task,
    required bool isCompleted,
  }) =>
      tasksService.setCompleted(task: task, isCompleted: isCompleted);

  @override
  Future<JsonResponse> delete(String id) => tasksService.delete(id);
}
