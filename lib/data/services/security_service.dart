import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/data/models/json_response.dart';
// `show compute`: an unrestricted import collides with encrypt's `Key`.
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// PIN hashing work factor. Raising it slows every brute-force guess by the same
/// proportion as a legitimate unlock.
const int kPBKDF2Iterations = 120000;

/// [SecurityService] owns every secret the app holds and the gate in front of
/// them (Requirements 1 and 23): the database encryption key (generated once,
/// held in the platform keychain / keystore-backed EncryptedSharedPreferences),
/// the PIN (stored only as a salted PBKDF2 hash, never plaintext), and the
/// lockout after repeated PIN failures (Requirement 1.4).
class SecurityService {
  /// [iterations] is a parameter only so tests can lower it; production uses
  /// [kPBKDF2Iterations]. Each hash stores the factor it was written with, so
  /// changing it never invalidates existing PINs.
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

  /// The GCM nonce length. 96 bits is what the mode is specified around; another
  /// length is legal but is hashed down to this one internally, for no benefit.
  static const int _ivLengthBytes = 12;

  // ── Database key ───────────────────────────────────────────────────────────

  /// Returns the SQLCipher key, generating it on first launch: 256 bits from the
  /// OS CSPRNG. Not derived from the PIN — a 4-digit PIN carries ~13 bits of
  /// entropy, which would make encryption at rest worthless. The PIN gates the
  /// UI; this key protects the file.
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

  /// The secure-storage entry holding the vault's 256-bit key. Not in
  /// `core/utils/constants.dart` because that file is protected (CLAUDE.md §0).
  static const String _kVaultKey = 'vault_encryption_key';

  /// Cached: the vault list decrypts every row, and a keychain round trip and an
  /// AES cipher rebuild per item are both avoidable.
  Key? _cachedVaultKey;

  Encrypter? _cachedVaultEncrypter;

  /// Returns the vault's item-encryption key, generating it on first use.
  ///
  /// Deliberately not the database key: reusing it would add a layer that any
  /// code holding an open database handle could peel straight off, which is the
  /// attacker this layer exists to stop.
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

  /// The GCM cipher over [vaultKey], built once.
  Future<Encrypter> _vaultEncrypter() async =>
      _cachedVaultEncrypter ??= Encrypter(AES(await vaultKey(), mode: AESMode.gcm));

  /// The vault's item-level AES-256 (Requirement 9.1).
  ///
  /// GCM, not CBC: GCM authenticates as well as encrypts, so an altered payload
  /// fails to decrypt rather than decrypting into plausible nonsense the app
  /// would show the user as their bank details. The IV is random per write and
  /// stored alongside the ciphertext — a fixed IV would give identical items
  /// identical ciphertext, leaking which of the user's passwords are the same.
  Future<JsonResponse> encryptSecret(String plaintext) async {
    try {
      final iv = IV(_randomBytes(_ivLengthBytes));
      final encrypter = await _vaultEncrypter();

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

  /// Reverses [encryptSecret]. A failure is reported, not swallowed: an item that
  /// will not decrypt is damaged or was written under a key this install no
  /// longer has, and rendering it empty would look like an item left blank.
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
      final encrypter = await _vaultEncrypter();

      final plaintext = encrypter.decrypt64(
        payload.substring(separator + 1),
        iv: iv,
      );

      return JsonResponse.success(message: 'Decrypted.', data: plaintext);
    } on Exception {
      // Reached when GCM's authentication tag does not verify: the payload has
      // been tampered with or corrupted.
      return JsonResponse.failure(
        statusCode: 422,
        message: 'This item is damaged and cannot be read.',
      );
    }
  }

  // ── Backup keys (Requirement 22) ───────────────────────────────────────────

  /// The secure-storage entry holding the 256-bit master key `EVB1` backups are
  /// derived from.
  static const String _kBackupKey = 'backup_master_key';

  /// Returns the pair an `EVB1` backup was sealed with. **Legacy, read-only** —
  /// new backups use [backupKeysFor]. This device-bound master is why the old
  /// format was unrestorable: secure storage does not survive an uninstall or
  /// "clear data" and does not travel to a new phone, so an intact backup failed
  /// its MAC and reported tampering. Kept only so an install still holding its
  /// master can read the backups it already has.
  ///
  /// Encrypt-then-MAC with separate keys (Requirement 22.6): the AES and HMAC
  /// keys are derived apart from one master by labelled SHA-256, so the integrity
  /// tag cannot be forged by anyone who only learns the cipher key. Not the
  /// database key — a backup must outlive the install that wrote it.
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

  /// Labelled SHA-256 over the master, giving two 256-bit keys that share no bits
  /// an attacker could pivot between.
  static Uint8List _deriveKey(Uint8List master, String label) => Uint8List.fromList(
        sha256.convert([...master, ...utf8.encode(label)]).bytes,
      );

  // ── Backup PIN (portable backups) ──────────────────────────────────────────

  /// Work factor for the backup PIN. Higher than the app-lock factor because a
  /// stolen backup file can be attacked offline as fast as the hardware allows,
  /// with no lockout in the way. A short numeric PIN has little entropy, so this
  /// is the only thing between the file and an exhaustive search.
  static const int kBackupPBKDF2Iterations = 210000;

  /// Holds the backup PIN itself, not a hash: the PIN *is* the key material for
  /// every backup file, so an unattended automatic backup must re-derive it, and
  /// a hash cannot encrypt. It sits in the same keychain/keystore as the database
  /// key and never leaves the device; losing it costs nothing, because the user
  /// knows the PIN and each file carries its own salt.
  static const String _kBackupPIN = 'backup_pin';

  /// True once the user has chosen one.
  Future<bool> hasBackupPIN() async {
    try {
      final stored = await storage.read(key: _kBackupPIN);
      return stored != null && stored.isNotEmpty;
    } on Exception {
      return false;
    }
  }

  /// Remembers the PIN new backups are sealed with. Changing it does not
  /// invalidate older backups: each file stores the salt and work factor it was
  /// written with — which is why those parameters live in the file, not here.
  Future<JsonResponse> setBackupPIN(String pin) async {
    try {
      if (pin.trim().length < 4) {
        return JsonResponse.failure(
          statusCode: 400,
          message: 'Your backup PIN must be at least 4 digits.',
        );
      }

      await storage.write(key: _kBackupPIN, value: pin.trim());
      return JsonResponse.created(message: 'Backup PIN set.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not save your backup PIN.',
      );
    }
  }

  /// Returns the remembered PIN, so an automatic backup can seal without
  /// prompting. [JsonResponse.data] is the PIN.
  Future<JsonResponse> backupPIN() async {
    try {
      final stored = await storage.read(key: _kBackupPIN);
      if (stored == null || stored.isEmpty) {
        return JsonResponse.failure(
          statusCode: 404,
          message: 'Set a backup PIN before backing up.',
        );
      }
      return JsonResponse.success(message: 'Backup PIN loaded.', data: stored);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not access the secure keystore.',
      );
    }
  }

  /// Stretches [pin] into the encrypt and MAC key pair, using the [salt] and
  /// [iterations] carried by the file being sealed or opened.
  ///
  /// One PBKDF2 pass produces 64 bytes split into two 256-bit halves rather than
  /// running twice: the halves are independent output of the same KDF, so the MAC
  /// key still cannot be recovered from the cipher key, at half the cost. The
  /// derivation depends on nothing but the PIN and the file's own header — no
  /// device secret, no install state — which is what makes a backup restorable on
  /// a phone that has never seen the one that wrote it.
  ///
  /// [JsonResponse.data] is `({Key encKey, List<int> macKey})`.
  static Future<JsonResponse> backupKeysFor({
    required String pin,
    required Uint8List salt,
    required int iterations,
  }) async {
    try {
      final derived = await _pbkdf2Async(pin, salt, iterations, _keyLengthBytes * 2);
      return JsonResponse.success(
        message: 'Backup keys ready.',
        data: (
          encKey: Key(Uint8List.sublistView(derived, 0, _keyLengthBytes)),
          macKey: Uint8List.sublistView(derived, _keyLengthBytes),
        ),
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not derive the backup keys.',
      );
    }
  }

  /// A fresh per-file PBKDF2 salt. Per file, not per install: two backups sealed
  /// with the same PIN must not derive the same key, or one cracked file would
  /// open every other.
  Uint8List backupSalt() => _randomBytes(_saltLengthBytes);

  // ── PIN ────────────────────────────────────────────────────────────────────

  /// True once the user has set one.
  Future<bool> hasPIN() async {
    try {
      final stored = await storage.read(key: kPINHash);
      return stored != null && stored.isNotEmpty;
    } on Exception {
      return false;
    }
  }

  /// Stores [pin] as `iterations:salt:hash`, all hex. PBKDF2 with a per-user
  /// random salt, so the small keyspace of a numeric PIN cannot be attacked with
  /// a precomputed table, and each guess costs real work.
  Future<JsonResponse> setPIN(String pin) async {
    try {
      if (pin.trim().length < 4) {
        return JsonResponse.failure(
          statusCode: 400,
          message: 'Your PIN must be at least 4 digits.',
        );
      }

      final salt = _randomBytes(_saltLengthBytes);
      final hash = await _pbkdf2Async(pin, salt, iterations, _keyLengthBytes);
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

  /// Deletes the PIN, but only after [pin] verifies, so an unattended unlocked
  /// phone is not one tap away from losing its lock. The database key is
  /// untouched — not being PIN-derived, the data stays encrypted at rest with no
  /// lock screen (Requirement 23.1).
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

  /// Checks [pin] and maintains the lockout counter. [JsonResponse.data] is the
  /// resulting [LockoutStatus], so the caller can render "2 attempts remaining"
  /// or a countdown without a second round-trip.
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
      final actual =
          await _pbkdf2Async(pin, salt, storedIterations, expected.length);

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

  /// Reports the current failure count and lockout expiry. Both live in secure
  /// storage, not memory: an in-memory counter would reset on force-quit, giving
  /// an attacker unlimited PIN guesses three at a time.
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

  /// True when the device has enrolled biometrics.
  Future<bool> isBiometricAvailable() async {
    try {
      return await localAuth.canCheckBiometrics &&
          await localAuth.isDeviceSupported();
    } on Exception {
      return false;
    }
  }

  /// Prompts for fingerprint / face. A failure is not an error state — it is the
  /// normal path to the PIN fallback (Requirement 1.3), so the caller shows the
  /// PIN pad rather than an error.
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

  /// Runs [_pbkdf2] on a background isolate. At 120k–210k HMAC rounds the
  /// derivation is measured in seconds, and both callers sit on interactive
  /// paths (the lock screen, the backup sheet).
  static Future<Uint8List> _pbkdf2Async(
    String password,
    Uint8List salt,
    int iterations,
    int outputLength,
  ) =>
      compute(
        _pbkdf2Entry,
        (
          password: password,
          salt: salt,
          iterations: iterations,
          outputLength: outputLength,
        ),
      );

  /// `compute` entry point: it takes exactly one argument.
  static Uint8List _pbkdf2Entry(
    ({String password, Uint8List salt, int iterations, int outputLength}) args,
  ) =>
      _pbkdf2(args.password, args.salt, args.iterations, args.outputLength);

  /// PBKDF2-HMAC-SHA256 (RFC 8018). Hand-rolled because `package:crypto` ships
  /// HMAC but not PBKDF2.
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

  /// Compares without short-circuiting: a plain `==` returns as soon as two bytes
  /// differ, leaking through timing how much of a guess was correct.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}

/// The PIN lockout state (Requirement 1.4). [lockedUntil] is UTC, null when not
/// locked out.
class LockoutStatus {
  const LockoutStatus({required this.failedAttempts, required this.lockedUntil});

  final int failedAttempts;
  final DateTime? lockedUntil;

  bool get isLockedOut =>
      lockedUntil != null && lockedUntil!.isAfter(DateTime.now().toUtc());

  /// How long the lockout still has to run.
  Duration get remaining {
    if (!isLockedOut) return Duration.zero;
    return lockedUntil!.difference(DateTime.now().toUtc());
  }

  /// How many guesses are left before a lockout.
  int get attemptsRemaining =>
      (kMaxPINAttempts - failedAttempts).clamp(0, kMaxPINAttempts);
}
