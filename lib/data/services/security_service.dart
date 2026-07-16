import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// [kPBKDF2Iterations] is the PIN hashing work factor. Raising it slows every
/// brute-force guess by the same proportion as a legitimate unlock.
const int kPBKDF2Iterations = 120000;

/// [SecurityService] owns every secret the app holds and the gate in front of
/// them (Requirements 1 and 23).
///
/// Three responsibilities:
/// 1) The database encryption key — generated once, then held in the platform
///    keychain (iOS) / keystore-backed EncryptedSharedPreferences (Android).
/// 2) The PIN — stored only as a salted PBKDF2 hash, never as plaintext.
/// 3) The lockout after repeated PIN failures (Requirement 1.4).
///
/// Like every other service it returns [JsonResponse] and never throws.
class SecurityService {
  /// [iterations] is the PBKDF2 work factor. It is a parameter only so tests can
  /// lower it; production always uses [kPBKDF2Iterations]. The value used is
  /// stored alongside each hash, so changing it never invalidates existing PINs.
  SecurityService({
    required this.storage,
    required this.localAuth,
    this.iterations = kPBKDF2Iterations,
  });

  final FlutterSecureStorage storage;
  final LocalAuthentication localAuth;
  final int iterations;

  static const int _keyLengthBytes = 32; // 256-bit
  static const int _saltLengthBytes = 16;

  /// The GCM nonce length. 96 bits is what the mode is specified around — a
  /// different length is legal but is hashed down to this one internally, for no
  /// benefit.
  static const int _ivLengthBytes = 12;

  // ── Database key ───────────────────────────────────────────────────────────

  /// [databaseKey] returns the SQLCipher key, generating it on first launch.
  ///
  /// The key is 256 bits from [Random.secure], the OS CSPRNG. It is not derived
  /// from the PIN: a 4-digit PIN carries ~13 bits of entropy, which would make the
  /// encryption at rest worthless. The PIN gates the UI; this key protects the
  /// file.
  Future<JsonResponse> databaseKey() async {
    try {
      final existing = await storage.read(key: kDatabaseKey);
      if (existing != null && existing.isNotEmpty) {
        return JsonResponse.success(message: 'Key loaded.', data: existing);
      }

      final key = _randomHex(_keyLengthBytes);
      await storage.write(key: kDatabaseKey, value: key);
      return JsonResponse.created(message: 'Key created.', data: key);
    } on Exception catch (error) {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not access the secure keystore. $error',
      );
    }
  }

  // ── Vault item key (Requirement 9.1) ───────────────────────────────────────

  /// [_kVaultKey] is the secure-storage entry holding the vault's 256-bit key.
  ///
  /// It lives here rather than in `core/utils/constants.dart` because that file is
  /// protected (CLAUDE.md §0), and because nothing outside this class has any
  /// business naming it.
  static const String _kVaultKey = 'vault_encryption_key';

  /// [_vaultKey] is the cached vault key, so that reading a vault item does not
  /// cost a keychain round trip per item.
  Key? _cachedVaultKey;

  /// [vaultKey] returns the vault's item-encryption key, generating it on first
  /// use.
  ///
  /// It is **not** the database key. The database is already encrypted at rest with
  /// that one, so reusing it here would add a second layer that any code holding an
  /// open database handle could peel straight back off — which is exactly the
  /// attacker this layer exists to stop. Two keys, two jobs: the database key makes
  /// the file unreadable off the device, and this one keeps a vault item unreadable
  /// even to code that is already inside the database.
  Future<Key> vaultKey() async {
    final cached = _cachedVaultKey;
    if (cached != null) return cached;

    final existing = await storage.read(key: _kVaultKey);
    if (existing != null && existing.isNotEmpty) {
      return _cachedVaultKey = Key.fromBase64(existing);
    }

    final key = Key(_randomBytes(_keyLengthBytes));
    await storage.write(key: _kVaultKey, value: key.base64);

    return _cachedVaultKey = key;
  }

  /// [encryptSecret] is the vault's item-level AES-256 (Requirement 9.1).
  ///
  /// **GCM, not CBC.** GCM authenticates as well as encrypts, so a payload that has
  /// been altered — by a corrupt write, a bad restore, or someone editing the
  /// database file — fails to decrypt rather than decrypting into plausible
  /// nonsense that the app would then show the user as their bank details.
  ///
  /// The IV is random per write and stored alongside the ciphertext, which is what
  /// it is for: a fixed IV would mean two items with the same contents produced
  /// identical ciphertext, and the encrypted column would leak which of the user's
  /// passwords are the same password.
  Future<JsonResponse> encryptSecret(String plaintext) async {
    try {
      final iv = IV(_randomBytes(_ivLengthBytes));
      final encrypter = Encrypter(AES(await vaultKey(), mode: AESMode.gcm));

      final encrypted = encrypter.encrypt(plaintext, iv: iv);

      return JsonResponse.success(
        message: 'Encrypted.',
        data: '${iv.base64}:${encrypted.base64}',
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not encrypt this item.',
      );
    }
  }

  /// [decryptSecret] reverses [encryptSecret].
  ///
  /// A failure here is reported rather than swallowed: an item that will not
  /// decrypt is either damaged or was written under a key this install no longer
  /// has, and silently rendering it as empty would look exactly like an item the
  /// user had left blank.
  Future<JsonResponse> decryptSecret(String payload) async {
    try {
      final separator = payload.indexOf(':');
      if (separator <= 0) {
        return JsonResponse.failure(
          statusCode: 422,
          message: 'This item is damaged and cannot be read.',
        );
      }

      final iv = IV.fromBase64(payload.substring(0, separator));
      final encrypter = Encrypter(AES(await vaultKey(), mode: AESMode.gcm));

      final plaintext = encrypter.decrypt64(
        payload.substring(separator + 1),
        iv: iv,
      );

      return JsonResponse.success(message: 'Decrypted.', data: plaintext);
    } on Exception {
      // Reached when GCM's authentication tag does not verify, which is the whole
      // reason for using GCM: the payload has been tampered with or corrupted.
      return JsonResponse.failure(
        statusCode: 422,
        message: 'This item is damaged and cannot be read.',
      );
    }
  }

  // ── Backup keys (Requirement 22) ───────────────────────────────────────────

  /// [_kBackupKey] is the secure-storage entry holding the 256-bit master key the
  /// encrypted backups are derived from.
  static const String _kBackupKey = 'backup_master_key';

  /// [backupKeys] returns the pair a backup is sealed with, generating the master
  /// on first use.
  ///
  /// Two independent keys, both derived from one stored master by SHA-256 with a
  /// distinct label: the AES key that encrypts the payload, and the HMAC key that
  /// authenticates it. **Encrypt-then-MAC with separate keys** (Requirement 22.6):
  /// reusing one key for both is the classic footgun, and deriving them apart
  /// means the integrity tag cannot be forged by anyone who only learns the cipher
  /// key.
  ///
  /// It is **not** the database key. A backup outlives the install that wrote it —
  /// the whole point is to survive a reinstall — so it is keyed by a secret of its
  /// own rather than one bound to a single device's SQLCipher file.
  ///
  /// [JsonResponse.data] is `({Key encKey, List<int> macKey})`.
  Future<JsonResponse> backupKeys() async {
    try {
      var master = await storage.read(key: _kBackupKey);
      if (master == null || master.isEmpty) {
        master = _randomHex(_keyLengthBytes);
        await storage.write(key: _kBackupKey, value: master);
      }

      final raw = _unhex(master);
      return JsonResponse.success(
        message: 'Backup keys ready.',
        data: (
          encKey: Key(_deriveKey(raw, 'enc')),
          macKey: _deriveKey(raw, 'mac'),
        ),
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not access the secure keystore.',
      );
    }
  }

  /// [_deriveKey] is a labelled SHA-256 over the master, giving two 256-bit keys
  /// that share no bits an attacker could pivot between.
  static Uint8List _deriveKey(Uint8List master, String label) => Uint8List.fromList(
        sha256.convert([...master, ...utf8.encode(label)]).bytes,
      );

  // ── PIN ────────────────────────────────────────────────────────────────────

  /// [hasPIN] is true once the user has set one.
  Future<bool> hasPIN() async {
    try {
      final stored = await storage.read(key: kPINHash);
      return stored != null && stored.isNotEmpty;
    } on Exception {
      return false;
    }
  }

  /// [setPIN] stores [pin] as `iterations:salt:hash`, all hex.
  ///
  /// PBKDF2 with a per-user random salt, so the small keyspace of a numeric PIN
  /// cannot be attacked with a precomputed table, and each guess costs real work.
  Future<JsonResponse> setPIN(String pin) async {
    try {
      if (pin.trim().length < 4) {
        return JsonResponse.failure(
          statusCode: 400,
          message: 'Your PIN must be at least 4 digits.',
        );
      }

      final salt = _randomBytes(_saltLengthBytes);
      final hash = _pbkdf2(pin, salt, iterations, _keyLengthBytes);
      await storage.write(
        key: kPINHash,
        value: '$iterations:${_hex(salt)}:${_hex(hash)}',
      );
      await _clearFailures();

      return JsonResponse.created(message: 'PIN set.');
    } on Exception catch (error) {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not save your PIN. $error',
      );
    }
  }

  /// [removePIN] deletes the PIN, but only after [pin] verifies against it, so an
  /// unattended unlocked phone is not one tap away from losing its lock.
  ///
  /// The database key is untouched: it is not derived from the PIN, so the data
  /// remains encrypted at rest with no lock screen (Requirement 23.1).
  Future<JsonResponse> removePIN(String pin) async {
    try {
      final verification = await verifyPIN(pin);
      if (!verification.success) return verification;

      await storage.delete(key: kPINHash);
      await _clearFailures();

      return JsonResponse.success(message: 'App lock removed.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not remove the app lock.',
      );
    }
  }

  /// [verifyPIN] checks [pin] and maintains the lockout counter.
  ///
  /// The returned [JsonResponse.data] is the [LockoutStatus] afterwards, so the
  /// caller can render "2 attempts remaining" or a countdown without a second
  /// round-trip.
  Future<JsonResponse> verifyPIN(String pin) async {
    try {
      final lockout = await lockoutStatus();
      if (lockout.isLockedOut) {
        return JsonResponse.failure(
          statusCode: 429,
          message: 'Too many attempts. Try again in '
              '${lockout.remaining.inSeconds}s.',
        );
      }

      final stored = await storage.read(key: kPINHash);
      if (stored == null || stored.isEmpty) {
        return JsonResponse.failure(
          statusCode: 404,
          message: 'No PIN has been set.',
        );
      }

      final parts = stored.split(':');
      if (parts.length != 3) {
        return JsonResponse.failure(
          statusCode: 500,
          message: 'Your stored PIN is corrupt. Please reset the app.',
        );
      }

      // The stored work factor, not the current one: a hash written before the
      // factor changed must still verify.
      final storedIterations = int.tryParse(parts[0]) ?? iterations;
      final salt = _unhex(parts[1]);
      final expected = _unhex(parts[2]);
      final actual = _pbkdf2(pin, salt, storedIterations, expected.length);

      if (!_constantTimeEquals(expected, actual)) {
        final status = await _recordFailure();
        return JsonResponse.failure(
          statusCode: 401,
          message: status.isLockedOut
              ? 'Too many attempts. Locked for '
                  '${status.remaining.inSeconds}s.'
              : 'Incorrect PIN. '
                  '${status.attemptsRemaining} attempt(s) remaining.',
        );
      }

      await _clearFailures();
      return JsonResponse.success(
        message: 'Unlocked.',
        data: const LockoutStatus(failedAttempts: 0, lockedUntil: null),
      );
    } on Exception catch (error) {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not verify your PIN. $error',
      );
    }
  }

  // ── Lockout (Requirement 1.4) ──────────────────────────────────────────────

  /// [lockoutStatus] reports the current failure count and lockout expiry.
  ///
  /// Both live in **secure storage, not in memory**, and that is the point: an
  /// in-memory counter would be reset by force-quitting the app, so an attacker
  /// would get unlimited PIN guesses three at a time. Persisting it means the
  /// lockout survives a restart.
  Future<LockoutStatus> lockoutStatus() async {
    try {
      final attempts =
          int.tryParse(await storage.read(key: _kFailedAttempts) ?? '') ?? 0;
      final untilRaw = await storage.read(key: _kLockedUntil);
      final until =
          untilRaw == null ? null : DateTime.tryParse(untilRaw)?.toUtc();

      return LockoutStatus(failedAttempts: attempts, lockedUntil: until);
    } on Exception {
      return const LockoutStatus(failedAttempts: 0, lockedUntil: null);
    }
  }

  Future<LockoutStatus> _recordFailure() async {
    final current = await lockoutStatus();
    final attempts = current.failedAttempts + 1;

    DateTime? lockedUntil;
    if (attempts >= kMaxPINAttempts) {
      lockedUntil = DateTime.now().toUtc().add(kPINLockoutDuration);
    }

    await storage.write(key: _kFailedAttempts, value: '$attempts');
    if (lockedUntil != null) {
      await storage.write(
        key: _kLockedUntil,
        value: lockedUntil.toIso8601String(),
      );
    }

    return LockoutStatus(failedAttempts: attempts, lockedUntil: lockedUntil);
  }

  Future<void> _clearFailures() async {
    await storage.delete(key: _kFailedAttempts);
    await storage.delete(key: _kLockedUntil);
  }

  // ── Biometrics (Requirement 1.2) ───────────────────────────────────────────

  /// [isBiometricAvailable] is true when the device has enrolled biometrics.
  Future<bool> isBiometricAvailable() async {
    try {
      return await localAuth.canCheckBiometrics &&
          await localAuth.isDeviceSupported();
    } on Exception {
      return false;
    }
  }

  /// [authenticateBiometric] prompts for fingerprint / face.
  ///
  /// A failure here is not an error state — it is the normal path to the PIN
  /// fallback (Requirement 1.3), so the caller shows the PIN pad rather than an
  /// error.
  Future<JsonResponse> authenticateBiometric({required String reason}) async {
    try {
      final didAuthenticate = await localAuth.authenticate(
        localizedReason: reason,
        // Leave the PIN fallback to our own UI rather than the OS device
        // credential sheet, so the lockout policy stays ours to enforce.
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      return didAuthenticate
          ? JsonResponse.success(message: 'Unlocked.')
          : JsonResponse.failure(
              statusCode: 401,
              message: 'Biometric authentication was not completed.',
            );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 401,
        message: 'Biometric authentication is unavailable.',
      );
    }
  }

  // ── Crypto primitives ──────────────────────────────────────────────────────

  static const String _kFailedAttempts = 'pin_failed_attempts';
  static const String _kLockedUntil = 'pin_locked_until';

  final Random _random = Random.secure();

  Uint8List _randomBytes(int length) => Uint8List.fromList(
        List<int>.generate(length, (_) => _random.nextInt(256)),
      );

  String _randomHex(int length) => _hex(_randomBytes(length));

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _unhex(String hex) => Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);

  /// [_pbkdf2] is PBKDF2-HMAC-SHA256 (RFC 8018).
  ///
  /// Hand-rolled because `package:crypto` ships HMAC but not PBKDF2, and pulling
  /// in a second crypto dependency for ~15 lines of standard block iteration is
  /// not worth it.
  static Uint8List _pbkdf2(
    String password,
    Uint8List salt,
    int iterations,
    int outputLength,
  ) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final output = BytesBuilder();
    var block = 1;

    while (output.length < outputLength) {
      // U1 = HMAC(password, salt || INT_32_BE(block))
      final blockIndex = Uint8List(4)
        ..buffer.asByteData().setUint32(0, block, Endian.big);
      var u = Uint8List.fromList(
        hmac.convert([...salt, ...blockIndex]).bytes,
      );
      final accumulated = Uint8List.fromList(u);

      // Ui = HMAC(password, Ui-1), XOR-folded into the accumulator.
      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < accumulated.length; j++) {
          accumulated[j] ^= u[j];
        }
      }

      output.add(accumulated);
      block++;
    }

    return Uint8List.fromList(output.takeBytes().sublist(0, outputLength));
  }

  /// [_constantTimeEquals] compares without short-circuiting.
  ///
  /// A plain `==` returns as soon as two bytes differ, which leaks how much of a
  /// guess was correct through timing. Irrelevant for a local PIN in most threat
  /// models, but it costs nothing to do properly.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}

/// [LockoutStatus] is the PIN lockout state (Requirement 1.4).
///
/// [lockedUntil] is UTC, and null when not locked out.
class LockoutStatus {
  const LockoutStatus({required this.failedAttempts, required this.lockedUntil});

  final int failedAttempts;
  final DateTime? lockedUntil;

  bool get isLockedOut =>
      lockedUntil != null && lockedUntil!.isAfter(DateTime.now().toUtc());

  /// [remaining] is how long the lockout still has to run.
  Duration get remaining {
    if (!isLockedOut) return Duration.zero;
    return lockedUntil!.difference(DateTime.now().toUtc());
  }

  /// [attemptsRemaining] is how many guesses are left before a lockout.
  int get attemptsRemaining =>
      (kMaxPINAttempts - failedAttempts).clamp(0, kMaxPINAttempts);
}
