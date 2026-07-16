import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/app_database.dart';

/// [Document] is one plain-Markdown document (Requirement 11).
///
/// [content] is the raw Markdown, stored as-is — there is no rich-text model, no
/// Delta, and no revision history (a deliberate simplification over `design.md`,
/// which the plan carries). It maps to the table's `contentJson` column, so named
/// from an earlier design; the value it holds now is plain text, not JSON.
///
/// [projectId] files the document under a project (Requirement 10.1). It is
/// nullable in the schema, but every document created in the app is filed under
/// the project whose screen created it.
///
/// [lastAutoSavedAt] is stamped by the 30-second auto-save (Requirement 11.2) so
/// the editor can show when the document was last written without saying "Edited"
/// forever.
class Document extends Equatable {
  const Document({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.projectId,
    this.lastAutoSavedAt,
  });

  final String id;
  final String title;
  final String content;
  final String? projectId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastAutoSavedAt;

  /// [displayTitle] is what a list shows: the title, or a placeholder for a
  /// document saved before its title was typed. The stored title is left blank
  /// rather than defaulted, so nothing the auto-save writes differs from what the
  /// user typed (Property 12).
  String get displayTitle => title.isBlank ? 'Untitled document' : title;

  /// [preview] is the first non-empty line of the body, for the list card.
  String get preview {
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  bool matches(String query) {
    if (query.isBlank) return true;
    return title.containsIgnoreCase(query) ||
        content.containsIgnoreCase(query);
  }

  factory Document.fromEntry(DocumentEntry entry) => Document(
        id: entry.id,
        title: entry.title,
        content: entry.contentJson,
        projectId: entry.projectId,
        createdAt: entry.createdAt,
        updatedAt: entry.updatedAt,
        lastAutoSavedAt: entry.lastAutoSavedAt,
      );

  /// [toCompanion] omits `revisionsJson`, leaving the column at its schema
  /// default: this build keeps no revision history, so writing it would only
  /// clear the empty list already there.
  DocumentsTableCompanion toCompanion() => DocumentsTableCompanion.insert(
        id: id,
        title: title,
        contentJson: content,
        projectId: Value(projectId),
        createdAt: createdAt,
        updatedAt: updatedAt,
        lastAutoSavedAt: Value(lastAutoSavedAt),
      );

  Document copyWith({
    String? id,
    String? title,
    String? content,
    String? projectId,
    bool clearProjectId = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastAutoSavedAt,
    bool clearLastAutoSavedAt = false,
  }) =>
      Document(
        id: id ?? this.id,
        title: title ?? this.title,
        content: content ?? this.content,
        projectId: clearProjectId ? null : (projectId ?? this.projectId),
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        lastAutoSavedAt: clearLastAutoSavedAt
            ? null
            : (lastAutoSavedAt ?? this.lastAutoSavedAt),
      );

  @override
  List<Object?> get props => [
        id,
        title,
        content,
        projectId,
        createdAt,
        updatedAt,
        lastAutoSavedAt,
      ];
}
