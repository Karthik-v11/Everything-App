part of 'vault_bloc.dart';

/// [VaultEvent] is the base class for every Vault event.
abstract class VaultEvent extends Equatable {
  const VaultEvent();

  @override
  List<Object?> get props => [];
}

/// [WatchVaultEvent] subscribes to the items and folders. Fired once.
class WatchVaultEvent extends VaultEvent {
  const WatchVaultEvent();
}

/// [VaultFoldersUpdatedEvent] carries a folder list in from its own subscription.
class VaultFoldersUpdatedEvent extends VaultEvent {
  const VaultFoldersUpdatedEvent({
    required this.folders,
    this.hasFailed = false,
  });

  final List<Folder> folders;
  final bool hasFailed;

  @override
  List<Object?> get props => [folders, hasFailed];
}

/// [UnlockVaultEvent] runs the biometric challenge on entry (Requirement 9.2).
class UnlockVaultEvent extends VaultEvent {
  const UnlockVaultEvent();
}

/// [UnlockVaultWithPINEvent] is the PIN fallback, checked against the app's own
/// PIN and subject to the same lockout (Requirements 1.3, 1.4, 9.2).
class UnlockVaultWithPINEvent extends VaultEvent {
  const UnlockVaultWithPINEvent({required this.pin});

  final String pin;

  @override
  List<Object?> get props => [pin];
}

/// [LockVaultEvent] re-locks the vault and drops any revealed plaintext. Fired when
/// the vault screen is left, so returning to it is a fresh challenge.
class LockVaultEvent extends VaultEvent {
  const LockVaultEvent();
}

/// [RevealVaultItemEvent] decrypts one item for its detail screen.
class RevealVaultItemEvent extends VaultEvent {
  const RevealVaultItemEvent({required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}

/// [ClearRevealedEvent] drops the decrypted item when its detail screen closes.
class ClearRevealedEvent extends VaultEvent {
  const ClearRevealedEvent();
}

/// [SaveVaultItemEvent] creates or updates an item.
///
/// [secret] is the plaintext and is always supplied: the payload on [item] is
/// ciphertext the caller cannot produce, so the service rewrites it from this
/// rather than trusting whatever the model arrived with.
class SaveVaultItemEvent extends VaultEvent {
  const SaveVaultItemEvent({required this.item, required this.secret});

  final VaultItem item;
  final VaultSecret secret;

  @override
  List<Object?> get props => [item, secret];
}

/// [DeleteVaultItemEvent] removes an item.
class DeleteVaultItemEvent extends VaultEvent {
  const DeleteVaultItemEvent({required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}

/// [FilterVaultEvent] narrows by type and folder.
class FilterVaultEvent extends VaultEvent {
  const FilterVaultEvent({this.type, this.folderId});

  final VaultItemType? type;
  final String? folderId;

  @override
  List<Object?> get props => [type, folderId];
}

/// [SearchVaultEvent] searches the vault — by name only (Requirement 9.5).
class SearchVaultEvent extends VaultEvent {
  const SearchVaultEvent({required this.query});

  final String query;

  @override
  List<Object?> get props => [query];
}

/// [SaveVaultFolderEvent] adds or renames a vault folder (Requirement 9.4).
class SaveVaultFolderEvent extends VaultEvent {
  const SaveVaultFolderEvent({required this.folder});

  final Folder folder;

  @override
  List<Object?> get props => [folder];
}

/// [DeleteVaultFolderEvent] removes a folder. Its items are kept.
class DeleteVaultFolderEvent extends VaultEvent {
  const DeleteVaultFolderEvent({required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}
