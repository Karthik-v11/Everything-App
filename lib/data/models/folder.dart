import 'package:equatable/equatable.dart';
import 'package:everything_app/data/database/app_database.dart';

/// [FolderScope] is which module a folder belongs to.
///
/// Bookmarks and the vault both organise into folders (Requirements 6.4, 9.4) and
/// there is one table behind both, so the scope is what keeps a bookmark folder
/// from turning up in the vault's folder picker.
enum FolderScope {
  bookmark,
  vault;

  static FolderScope fromName(String? name) => FolderScope.values.firstWhere(
        (value) => value.name == name,
        orElse: () => FolderScope.bookmark,
      );
}

/// [Folder] is a user-defined folder (Requirements 6.4, 9.4).
class Folder extends Equatable {
  const Folder({
    required this.id,
    required this.name,
    required this.scope,
    required this.createdAt,
  });

  final String id;
  final String name;
  final FolderScope scope;
  final DateTime createdAt;

  factory Folder.fromEntry(FolderEntry entry) => Folder(
        id: entry.id,
        name: entry.name,
        scope: FolderScope.fromName(entry.scope),
        createdAt: entry.createdAt,
      );

  FoldersTableCompanion toCompanion() => FoldersTableCompanion.insert(
        id: id,
        name: name,
        scope: scope.name,
        createdAt: createdAt,
      );

  Folder copyWith({String? id, String? name, FolderScope? scope}) => Folder(
        id: id ?? this.id,
        name: name ?? this.name,
        scope: scope ?? this.scope,
        createdAt: createdAt,
      );

  @override
  List<Object?> get props => [id, name, scope, createdAt];
}
