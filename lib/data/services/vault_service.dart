import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/daos/vault_dao.dart';
import 'package:everything_app/data/models/folder.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/vault_item.dart';
import 'package:everything_app/data/services/security_service.dart';
import 'package:uuid/uuid.dart';

/// [VaultService] is the Vault's persistence layer (Requirement 9).
///
/// The only place a vault plaintext exists, and it holds none of it: nothing
/// here caches, collects or logs a decrypted value. That is what lets [watchAll]
/// stream the whole vault safely — every item on it is an opaque blob, so the
/// list, its filters and its search never touch a secret (Requirements 9.2, 9.5).
///
/// Authentication is *not* enforced here. The gate is `VaultBloc`, which will not
/// dispatch a reveal until the user has re-authenticated (Requirement 9.2); a
/// second check here would be a second place for that rule to drift.
class VaultService {
  VaultService({required this.dao, required this.securityService});

  final VaultDao dao;
  final SecurityService securityService;

  static const Uuid _uuid = Uuid();

  /// [watchAll] streams names, types, folders and ciphertext only — no plaintext
  /// is decrypted to build it.
  Stream<List<VaultItem>> watchAll() =>
      dao.watchAll().map((rows) => rows.map(VaultItem.fromEntry).toList());

  Stream<List<Folder>> watchFolders() =>
      dao.watchFolders().map((rows) => rows.map(Folder.fromEntry).toList());

  /// [save] encrypts [secret] and writes it against [item] (Requirement 9.1).
  ///
  /// [VaultItem.encryptedPayload] is *always* rewritten from [secret], never
  /// carried over from the model passed in: accepting a caller's payload is the
  /// one hole through which plaintext could reach the table.
  Future<JsonResponse> save({
    required VaultItem item,
    required VaultSecret secret,
  }) async {
    try {
      if (item.name.isBlank) {
        return JsonResponse.failure(
          statusCode: 400,
          message: 'This item needs a name.',
        );
      }

      final encrypted = await securityService.encryptSecret(secret.encode());
      if (!encrypted.success) return encrypted;

      final now = DateTime.now();
      final isNew = item.id.isBlank;

      final prepared = item.copyWith(
        id: isNew ? _uuid.v4() : item.id,
        name: item.name.trim(),
        encryptedPayload: encrypted.data! as String,
        createdAt: isNew ? now : item.createdAt,
        updatedAt: now,
      );

      await dao.upsert(prepared.toCompanion());

      return isNew
          ? JsonResponse.created(message: 'Saved to your vault.', data: prepared)
          : JsonResponse.success(message: 'Item updated.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not save this item.',
      );
    }
  }

  /// [reveal] decrypts one item by id, on demand — never the list
  /// (Requirement 9.2). The returned [VaultSecret] is the only plaintext the app
  /// holds; callers drop it when the detail screen closes.
  ///
  /// The row is re-read rather than decrypted from a caller's [VaultItem], so the
  /// plaintext is of what is in the database now, not of a copy the list has held
  /// since it last streamed.
  Future<JsonResponse> reveal(String id) async {
    try {
      final entry = await dao.findById(id);
      if (entry == null) {
        return JsonResponse.failure(
          statusCode: 404,
          message: 'That item no longer exists.',
        );
      }

      final decrypted =
          await securityService.decryptSecret(entry.encryptedPayload);
      if (!decrypted.success) return decrypted;

      return JsonResponse.success(
        message: 'Loaded successfully.',
        data: VaultSecret.decode(
          itemId: id,
          plain: decrypted.data! as String,
        ),
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not read this item.',
      );
    }
  }

  Future<JsonResponse> delete(String id) async {
    try {
      final removed = await dao.deleteById(id);

      return removed == 0
          ? JsonResponse.failure(
              statusCode: 404,
              message: 'That item no longer exists.',
            )
          : JsonResponse.success(message: 'Item deleted.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not delete this item.',
      );
    }
  }

  // ── Folders (Requirement 9.4) ──────────────────────────────────────────────

  Future<JsonResponse> saveFolder(Folder folder) async {
    try {
      if (folder.name.isBlank) {
        return JsonResponse.failure(
          statusCode: 400,
          message: 'A folder needs a name.',
        );
      }

      final prepared = folder.copyWith(
        id: folder.id.isBlank ? _uuid.v4() : folder.id,
        name: folder.name.trim(),
        scope: FolderScope.vault,
      );

      await dao.upsertFolder(prepared.toCompanion());

      return JsonResponse.success(message: 'Folder saved.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not save the folder.',
      );
    }
  }

  Future<JsonResponse> deleteFolder(String id) async {
    try {
      await dao.deleteFolder(id);

      return JsonResponse.success(
        message: 'Folder deleted — its items were kept.',
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not delete the folder.',
      );
    }
  }
}
