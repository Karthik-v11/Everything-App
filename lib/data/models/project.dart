import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:flutter/material.dart';

/// [Project] is a container for long-term work (Requirement 10).
///
/// [parentProjectId] is what makes a project a sub-project (Requirement 10.2). It
/// is a plain nullable id rather than a nested list of children: the tree is
/// rebuilt in memory from one flat stream, so no two rows can disagree about who a
/// project's parent is, and moving a project is one field rather than two list
/// edits.
class Project extends Equatable {
  const Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.parentProjectId,
    this.colorValue,
  });

  final String id;
  final String name;
  final String? description;
  final String? parentProjectId;
  final int? colorValue;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isSubProject => parentProjectId != null;

  /// [color] is the project's colour, or null to let the screen use the accent.
  Color? get color => colorValue == null ? null : Color(colorValue!);

  bool matches(String query) {
    if (query.isBlank) return true;
    return name.containsIgnoreCase(query) ||
        (description?.containsIgnoreCase(query) ?? false);
  }

  factory Project.fromEntry(ProjectEntry entry) => Project(
        id: entry.id,
        name: entry.name,
        description: entry.description,
        parentProjectId: entry.parentProjectId,
        colorValue: entry.colorValue,
        createdAt: entry.createdAt,
        updatedAt: entry.updatedAt,
      );

  ProjectsTableCompanion toCompanion() => ProjectsTableCompanion.insert(
        id: id,
        name: name,
        description: Value(description),
        parentProjectId: Value(parentProjectId),
        colorValue: Value(colorValue),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Project copyWith({
    String? id,
    String? name,
    String? description,
    bool clearDescription = false,
    String? parentProjectId,
    bool clearParentProjectId = false,
    int? colorValue,
    bool clearColorValue = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Project(
        id: id ?? this.id,
        name: name ?? this.name,
        description:
            clearDescription ? null : (description ?? this.description),
        parentProjectId: clearParentProjectId
            ? null
            : (parentProjectId ?? this.parentProjectId),
        colorValue: clearColorValue ? null : (colorValue ?? this.colorValue),
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        parentProjectId,
        colorValue,
        createdAt,
        updatedAt,
      ];
}

/// [ProjectTree] answers the questions a flat list of projects cannot: who are a
/// project's children, and what would deleting it actually take with it.
///
/// It is a pure function of the project list, built where it is needed rather than
/// stored, so it cannot go stale — the parent ids in the rows are the only truth
/// about the shape of the tree.
class ProjectTree {
  ProjectTree(this.projects) {
    for (final project in projects) {
      _byId[project.id] = project;
      _children.putIfAbsent(project.parentProjectId, () => []).add(project);
    }
  }

  final List<Project> projects;

  final Map<String, Project> _byId = {};
  final Map<String?, List<Project>> _children = {};

  /// [roots] are the top-level projects — the ones the Library hub lists.
  List<Project> get roots => childrenOf(null);

  /// [childrenOf] are the direct sub-projects of [id], or the roots for null.
  List<Project> childrenOf(String? id) => _children[id] ?? const [];

  Project? byId(String? id) => id == null ? null : _byId[id];

  /// [descendantsOf] is every project below [id], at any depth, excluding [id]
  /// itself.
  ///
  /// Iterative rather than recursive, and it tracks what it has already walked: a
  /// cycle in `parentProjectId` — which nothing in the app creates, but a bad
  /// restore or a future move could — would otherwise hang the app rather than
  /// deleting a project.
  List<Project> descendantsOf(String id) {
    final found = <Project>[];
    final seen = <String>{id};
    final queue = <String>[id];

    while (queue.isNotEmpty) {
      for (final child in childrenOf(queue.removeAt(0))) {
        if (!seen.add(child.id)) continue;
        found.add(child);
        queue.add(child.id);
      }
    }

    return found;
  }

  /// [ancestorsOf] is the path from [id] up to its root, nearest parent first —
  /// the breadcrumb on a sub-project's screen.
  List<Project> ancestorsOf(String id) {
    final path = <Project>[];
    final seen = <String>{id};

    var parentId = _byId[id]?.parentProjectId;
    while (parentId != null && seen.add(parentId)) {
      final parent = _byId[parentId];
      if (parent == null) break;
      path.add(parent);
      parentId = parent.parentProjectId;
    }

    return path;
  }

  /// [canReparent] is whether [project] may be moved under [newParentId].
  ///
  /// A project cannot be its own parent, nor be moved inside its own descendant —
  /// that would detach the whole branch from the tree, leaving projects that exist
  /// in the database and appear on no screen.
  bool canReparent(Project project, String? newParentId) {
    if (newParentId == null) return true;
    if (newParentId == project.id) return false;
    return !descendantsOf(project.id).any((child) => child.id == newParentId);
  }
}
