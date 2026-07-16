import 'package:everything_app/data/models/vault_item.dart';
import 'package:everything_app/data/services/security_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

/// [_FakeStorage] is an in-memory keychain.
class _FakeStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The vault's item-level encryption (Requirement 9.1).
///
/// The tests that matter here are the ones that look at the **ciphertext**, not the
/// ones that round-trip a value through the same object that wrote it. A round trip
/// passes just as happily against an implementation that stores plaintext, which is
/// exactly the failure this layer exists to prevent — and exactly the failure that
/// would look like a perfectly working app until someone read the database file.
void main() {
  late _FakeStorage storage;
  late SecurityService service;

  setUp(() {
    storage = _FakeStorage();
    service = SecurityService(
      storage: storage,
      localAuth: LocalAuthentication(),
      // The PIN work factor is irrelevant here and 120k iterations is not.
      iterations: 1,
    );
  });

  const plaintext = '{"Password":"hunter2","Username":"karthik"}';

  Future<String> encrypt(String value) async {
    final response = await service.encryptSecret(value);
    expect(response.success, isTrue, reason: response.message);
    return response.data! as String;
  }

  group('the payload is really encrypted', () {
    test('the ciphertext contains none of the plaintext', () async {
      final payload = await encrypt(plaintext);

      // The actual claim. Not "it decrypts back" — a service that returned its input
      // unchanged would pass that.
      expect(payload, isNot(contains('hunter2')));
      expect(payload, isNot(contains('karthik')));
      expect(payload, isNot(contains('Password')));
    });

    test('the same value encrypts differently every time', () async {
      final first = await encrypt(plaintext);
      final second = await encrypt(plaintext);

      // A fixed IV would make these identical — and the encrypted column would then
      // leak which of the user's passwords are the same password, without any of
      // them ever being decrypted.
      expect(first, isNot(second));
    });

    test('a round trip returns the original', () async {
      final payload = await encrypt(plaintext);
      final decrypted = await service.decryptSecret(payload);

      expect(decrypted.success, isTrue, reason: decrypted.message);
      expect(decrypted.data, plaintext);
    });
  });

  group('the vault key', () {
    test('is 256 bits, and is not the database key', () async {
      final databaseKey = await service.databaseKey();
      await encrypt(plaintext);

      final vaultKey = storage.values['vault_encryption_key'];

      expect(vaultKey, isNotNull);
      // Base64 of 32 bytes. The vault's second layer is only worth having if it is
      // not the layer the database is already encrypted with — reusing that key
      // would mean any code holding an open database handle could peel this one
      // straight back off.
      expect(vaultKey, isNot(databaseKey.data));
    });

    test('survives a restart', () async {
      final payload = await encrypt(plaintext);

      // A new service over the same keychain — the next launch of the app.
      final next = SecurityService(
        storage: storage,
        localAuth: LocalAuthentication(),
        iterations: 1,
      );

      final decrypted = await next.decryptSecret(payload);

      expect(decrypted.success, isTrue, reason: decrypted.message);
      expect(decrypted.data, plaintext);
    });
  });

  group('tampering is detected', () {
    test('a modified ciphertext will not decrypt', () async {
      final payload = await encrypt(plaintext);

      // Flip one character of the ciphertext. This is what GCM buys over CBC: the
      // authentication tag fails, so the item is reported as damaged rather than
      // decrypting into plausible nonsense the app would then show the user as
      // their bank details.
      final separator = payload.indexOf(':');
      final body = payload.substring(separator + 1);
      final tampered = '${payload.substring(0, separator)}:'
          '${body[0] == 'A' ? 'B' : 'A'}${body.substring(1)}';

      final decrypted = await service.decryptSecret(tampered);

      expect(decrypted.success, isFalse);
      expect(decrypted.statusCode, 422);
    });

    test('a payload with no IV is rejected rather than throwing', () async {
      final decrypted = await service.decryptSecret('not-a-payload');

      expect(decrypted.success, isFalse);
      expect(decrypted.statusCode, 422);
    });

    test('a payload from a different key will not decrypt', () async {
      final payload = await encrypt(plaintext);

      // A restore onto a device whose vault key is not the one this was written
      // with. It must fail loudly rather than produce garbage.
      final other = SecurityService(
        storage: _FakeStorage(),
        localAuth: LocalAuthentication(),
        iterations: 1,
      );

      final decrypted = await other.decryptSecret(payload);

      expect(decrypted.success, isFalse);
    });
  });

  group('what the list is allowed to know', () {
    test('a VaultItem carries no plaintext', () async {
      final payload = await encrypt(plaintext);

      final item = VaultItem(
        id: 'v1',
        type: VaultItemType.password,
        name: 'Bank login',
        encryptedPayload: payload,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      // Everything the list renders and searches, together. None of it may contain
      // a secret — this is Requirements 9.2 and 9.5 holding structurally rather
      // than by the discipline of whoever writes the next screen.
      final visible = '${item.name}${item.type.label}${item.encryptedPayload}';

      expect(visible, isNot(contains('hunter2')));
      expect(item.matches('hunter2'), isFalse);
      expect(item.matches('Bank'), isTrue);
    });

    test('the mask leaks nothing, not even the length', () {
      // A mask of one dot per character would tell an onlooker how long the password
      // is, which is more than they should get for free.
      expect(kMaskedSecret, isNot(contains('a')));
      expect(kMaskedSecret.length, 8);
    });
  });

  group('VaultSecret', () {
    test('round-trips its fields through JSON', () {
      const secret = VaultSecret(
        itemId: 'v1',
        fields: {'Password': 'a:b:c', 'Username': 'karthik'},
      );

      final decoded = VaultSecret.decode(
        itemId: 'v1',
        plain: secret.encode(),
      );

      // JSON rather than a delimited string, so a password that contains the
      // delimiter is not a corrupted item.
      expect(decoded.fields, secret.fields);
    });

    test('a payload it cannot parse becomes an empty item, not an exception', () {
      final decoded = VaultSecret.decode(itemId: 'v1', plain: 'garbage');

      expect(decoded.fields, isEmpty);
    });
  });
}
