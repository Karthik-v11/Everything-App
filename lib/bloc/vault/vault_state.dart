part of 'vault_bloc.dart';

/// [VaultState] holds everything the Vault screen renders.
///
/// [items] is the list, and **every payload on it is ciphertext** — it can be
/// filtered, searched, counted and drawn without decrypting anything, which is
/// what lets the list exist behind Requirements 9.2 and 9.5.
///
/// [revealed] is the one currently decrypted item. A single nullable field rather
/// than a map on purpose: the type makes holding two secrets at once impossible.
/// Cleared the moment the detail screen closes or the vault re-locks.
class VaultState extends Equatable {
  const VaultState({
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.items = const <VaultItem>[],
    this.folders = const <Folder>[],
    this.isUnlocked = false,
    this.isUnlocking = false,
    this.isRevealing = false,
    this.revealed,
    this.type,
    this.folderId,
    this.query = '',
  });

  final bool isLoading;
  final String error;
  final String message;

  /// The vault as the list knows it: names, types, folders, ciphertext.
  final List<VaultItem> items;
  final List<Folder> folders;

  /// Whether the entry challenge has been passed **this visit** (Requirement 9.2).
  /// Never persisted, and reset when the vault screen is left.
  final bool isUnlocked;

  /// The challenge is in flight — the biometric sheet is up, or the PIN is being
  /// checked.
  final bool isUnlocking;

  final bool isRevealing;

  /// The one decrypted item, or null. The only plaintext in the app.
  final VaultSecret? revealed;

  final VaultItemType? type;
  final String? folderId;
  final String query;

  /// [visibleItems] is the list under the active filters and the search query.
  ///
  /// The search runs over names and types only — there is nothing else here to
  /// search, so Requirement 9.5 holds by construction.
  List<VaultItem> get visibleItems => [
        for (final item in items)
          if (_matches(item)) item,
      ];

  bool _matches(VaultItem item) {
    if (type != null && item.type != type) return false;
    if (folderId != null && item.folderId != folderId) return false;
    if (query.isNotBlank && !item.matches(query)) return false;
    return true;
  }

  bool get isFiltered => type != null || folderId != null || query.isNotBlank;

  /// [countOf] is how many items a type holds — the number on its chip, counted
  /// within the folder filter but not the type filter.
  int countOf(VaultItemType value) {
    var count = 0;
    for (final item in items) {
      if (item.type != value) continue;
      if (folderId != null && item.folderId != folderId) continue;
      if (query.isNotBlank && !item.matches(query)) continue;
      count++;
    }
    return count;
  }

  /// [types] are the types the user actually has items in — the only ones worth a
  /// chip.
  List<VaultItemType> get types => [
        for (final value in VaultItemType.values)
          if (countOf(value) > 0) value,
      ];

  Folder? folderOf(VaultItem item) {
    for (final folder in folders) {
      if (folder.id == item.folderId) return folder;
    }
    return null;
  }

  Folder? get selectedFolder {
    for (final folder in folders) {
      if (folder.id == folderId) return folder;
    }
    return null;
  }

  /// [itemById] resolves the item a revealed secret belongs to, so the detail
  /// screen can show its name and type alongside its contents.
  VaultItem? itemById(String? id) {
    if (id == null) return null;
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  VaultState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    List<VaultItem>? items,
    List<Folder>? folders,
    bool? isUnlocked,
    bool? isUnlocking,
    bool? isRevealing,
    VaultSecret? revealed,
    bool clearRevealed = false,
    VaultItemType? type,
    bool clearType = false,
    String? folderId,
    bool clearFolderId = false,
    String? query,
  }) =>
      VaultState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        items: items ?? this.items,
        folders: folders ?? this.folders,
        isUnlocked: isUnlocked ?? this.isUnlocked,
        isUnlocking: isUnlocking ?? this.isUnlocking,
        isRevealing: isRevealing ?? this.isRevealing,
        revealed: clearRevealed ? null : (revealed ?? this.revealed),
        type: clearType ? null : (type ?? this.type),
        folderId: clearFolderId ? null : (folderId ?? this.folderId),
        query: query ?? this.query,
      );

  @override
  List<Object?> get props => [
        isLoading,
        error,
        message,
        items,
        folders,
        isUnlocked,
        isUnlocking,
        isRevealing,
        revealed,
        type,
        folderId,
        query,
      ];
}
