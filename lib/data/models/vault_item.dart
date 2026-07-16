import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/app_database.dart';
import 'package:flutter/material.dart';

/// [VaultItemType] is what a vault item holds (Requirement 9.3).
enum VaultItemType {
  password,
  document,
  bankDetail,
  identity,
  license,
  card;

  String get label => switch (this) {
        VaultItemType.password => 'Password',
        VaultItemType.document => 'Document',
        VaultItemType.bankDetail => 'Bank details',
        VaultItemType.identity => 'ID',
        VaultItemType.license => 'License',
        VaultItemType.card => 'Card',
      };

  IconData get icon => switch (this) {
        VaultItemType.password => Icons.key_rounded,
        VaultItemType.document => Icons.description_outlined,
        VaultItemType.bankDetail => Icons.account_balance_outlined,
        VaultItemType.identity => Icons.badge_outlined,
        VaultItemType.license => Icons.card_membership_outlined,
        VaultItemType.card => Icons.credit_card_rounded,
      };

  /// [fields] is the form this type shows, in order. The vault stores free-form
  /// key/value pairs, so this is a starting shape rather than a schema — the user
  /// can add their own field to any item.
  List<String> get fields => switch (this) {
        VaultItemType.password => const ['Username', 'Password', 'Website'],
        VaultItemType.document => const ['Reference', 'Notes'],
        VaultItemType.bankDetail => const [
            'Account number',
            'IFSC',
            'Bank',
            'Holder',
          ],
        VaultItemType.identity => const ['Number', 'Issued by', 'Expires'],
        VaultItemType.license => const ['Number', 'Issued by', 'Expires'],
        VaultItemType.card => const [
            'Card number',
            'Expiry',
            'CVV',
            'Name on card',
          ],
      };

  /// [secretFields] are the fields masked until the user asks to see them
  /// (Requirement 23.4). Everything else on the item is already behind the vault's
  /// own lock; these are the ones that are also worth hiding from the person
  /// standing behind you.
  static const Set<String> secretFields = {
    'Password',
    'CVV',
    'Card number',
    'Account number',
  };

  static VaultItemType fromName(String? name) =>
      VaultItemType.values.firstWhere(
        (value) => value.name == name,
        orElse: () => VaultItemType.password,
      );
}

/// [VaultItem] is a vault entry **as the list knows it**: a name, a type, and an
/// opaque blob.
///
/// This is the whole point of the type. [encryptedPayload] is AES-256-GCM
/// ciphertext (Requirement 9.1) and there is no method here that can turn it back
/// into anything readable — decryption lives in `VaultService`, behind the vault's
/// own authentication, and produces a [VaultSecret] that only the detail screen
/// ever holds. So a vault list can be built, filtered, searched and rendered
/// without a single plaintext value existing anywhere in the process, which is
/// what Requirements 9.2 and 9.5 actually ask for.
///
/// [name] is deliberately plaintext: Requirement 9.5 wants vault items findable by
/// title and forbids their *contents* from reaching a search index. A name is the
/// only field that can be both.
class VaultItem extends Equatable {
  const VaultItem({
    required this.id,
    required this.type,
    required this.name,
    required this.encryptedPayload,
    required this.createdAt,
    required this.updatedAt,
    this.folderId,
  });

  final String id;
  final VaultItemType type;
  final String name;
  final String encryptedPayload;
  final String? folderId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// [matches] searches the name and nothing else — there is nothing else here to
  /// search, by design (Requirement 9.5).
  bool matches(String query) {
    if (query.isBlank) return true;
    return name.containsIgnoreCase(query) ||
        type.label.containsIgnoreCase(query);
  }

  factory VaultItem.fromEntry(VaultItemEntry entry) => VaultItem(
        id: entry.id,
        type: VaultItemType.fromName(entry.type),
        name: entry.name,
        encryptedPayload: entry.encryptedPayload,
        folderId: entry.folderId,
        createdAt: entry.createdAt,
        updatedAt: entry.updatedAt,
      );

  VaultItemsTableCompanion toCompanion() => VaultItemsTableCompanion.insert(
        id: id,
        type: type.name,
        name: name,
        encryptedPayload: encryptedPayload,
        folderId: Value(folderId),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  VaultItem copyWith({
    String? id,
    VaultItemType? type,
    String? name,
    String? encryptedPayload,
    String? folderId,
    bool clearFolderId = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      VaultItem(
        id: id ?? this.id,
        type: type ?? this.type,
        name: name ?? this.name,
        encryptedPayload: encryptedPayload ?? this.encryptedPayload,
        folderId: clearFolderId ? null : (folderId ?? this.folderId),
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  List<Object?> get props => [
        id,
        type,
        name,
        encryptedPayload,
        folderId,
        createdAt,
        updatedAt,
      ];
}

/// [VaultSecret] is a decrypted vault item — the plaintext, and the only form of it
/// that exists in the app.
///
/// It is produced by `VaultService.reveal` and held by exactly one thing at a time:
/// the open detail screen, through `VaultState.revealed`, which is cleared the
/// moment that screen closes. It is never in a list, never in a collection, and
/// never persisted.
///
/// [fields] is an ordered map so a card's number stays above its CVV rather than
/// being reordered by a hash on every open.
class VaultSecret extends Equatable {
  const VaultSecret({required this.itemId, required this.fields});

  final String itemId;
  final Map<String, String> fields;

  /// [encode] is what gets encrypted. JSON rather than a delimited string, so a
  /// password containing the delimiter is not a corrupted item.
  String encode() => jsonEncode(fields);

  /// [decode] reads a decrypted payload back.
  ///
  /// A payload that does not parse is not silently dropped: it means the item was
  /// written by a build with a different format, or the ciphertext is damaged, and
  /// either way the honest answer is an empty item the user can see is wrong rather
  /// than an exception thrown into the vault list.
  factory VaultSecret.decode({required String itemId, required String plain}) {
    try {
      final decoded = jsonDecode(plain);
      if (decoded is! Map) {
        return VaultSecret(itemId: itemId, fields: const {});
      }

      return VaultSecret(
        itemId: itemId,
        fields: {
          for (final entry in decoded.entries)
            '${entry.key}': '${entry.value ?? ''}',
        },
      );
    } on FormatException {
      return VaultSecret(itemId: itemId, fields: const {});
    }
  }

  VaultSecret copyWith({Map<String, String>? fields}) =>
      VaultSecret(itemId: itemId, fields: fields ?? this.fields);

  @override
  List<Object?> get props => [itemId, fields];
}

/// [kMaskedSecret] is what a hidden field renders as (Requirement 23.4, Property
/// 15).
///
/// It is a **constant**, not a function of the value it stands in for. A mask that
/// ran one dot per character would leak the length — a nine-dot password tells an
/// onlooker more than it should — and a constant cannot contain a character of the
/// plaintext because it never sees it.
const String kMaskedSecret = '••••••••';
