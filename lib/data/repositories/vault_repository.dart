import 'package:everything_app/data/models/folder.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/vault_item.dart';
import 'package:everything_app/data/services/vault_service.dart';

/// [VaultRepository] defines the contract for the Vault (Requirement 9).
///
/// Note what is not here: a method that hands back the vault's plaintext in bulk.
/// [watchAll] streams items whose payloads are ciphertext, and [reveal] decrypts
/// exactly one, by id, on demand. The list can therefore be built, filtered and
/// searched without a plaintext ever existing (Requirements 9.2, 9.5).
abstract class VaultRepository {
  /// [watchAll] streams every vault item — names and ciphertext, never contents.
  Stream<List<VaultItem>> watchAll();

  /// [watchFolders] streams the vault folders (Requirement 9.4).
  Stream<List<Folder>> watchFolders();

  /// [save] encrypts [secret] with AES-256-GCM and writes it (Requirement 9.1).
  Future<JsonResponse> save({
    required VaultItem item,
    required VaultSecret secret,
  });

  /// [reveal] decrypts one item. Its result is the only plaintext the app holds,
  /// and the caller drops it when the detail screen closes.
  Future<JsonResponse> reveal(String id);

  /// [delete] removes an item by id.
  Future<JsonResponse> delete(String id);

  /// [saveFolder] inserts or renames a vault folder.
  Future<JsonResponse> saveFolder(Folder folder);

  /// [deleteFolder] removes a folder, keeping its items.
  Future<JsonResponse> deleteFolder(String id);
}

class VaultRepositoryImpl implements VaultRepository {
  const VaultRepositoryImpl({required this.vaultService});

  final VaultService vaultService;

  @override
  Stream<List<VaultItem>> watchAll() => vaultService.watchAll();

  @override
  Stream<List<Folder>> watchFolders() => vaultService.watchFolders();

  @override
  Future<JsonResponse> save({
    required VaultItem item,
    required VaultSecret secret,
  }) =>
      vaultService.save(item: item, secret: secret);

  @override
  Future<JsonResponse> reveal(String id) => vaultService.reveal(id);

  @override
  Future<JsonResponse> delete(String id) => vaultService.delete(id);

  @override
  Future<JsonResponse> saveFolder(Folder folder) =>
      vaultService.saveFolder(folder);

  @override
  Future<JsonResponse> deleteFolder(String id) =>
      vaultService.deleteFolder(id);
}
