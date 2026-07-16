import 'package:bloc_test/bloc_test.dart';
import 'package:everything_app/bloc/vault/vault_bloc.dart';
import 'package:everything_app/data/models/folder.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/vault_item.dart';
import 'package:everything_app/data/repositories/auth_repository.dart';
import 'package:everything_app/data/repositories/vault_repository.dart';
import 'package:everything_app/data/services/security_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// [_FakeAuth] is the app's authentication, with both answers under our control.
class _FakeAuth implements AuthRepository {
  bool isBiometricOk = true;
  bool isPINOk = true;

  /// Every PIN this fake was asked to verify — how the test proves the vault goes
  /// through the *app's* lockout rather than its own.
  final List<String> verifiedPINs = [];

  @override
  Future<JsonResponse> authenticateBiometric({required String reason}) async =>
      isBiometricOk
          ? JsonResponse.success(message: 'Unlocked.')
          : JsonResponse.failure(statusCode: 401, message: 'Cancelled.');

  @override
  Future<JsonResponse> verifyPIN(String pin) async {
    verifiedPINs.add(pin);

    return isPINOk
        ? JsonResponse.success(message: 'Unlocked.')
        : JsonResponse.failure(
            statusCode: 401,
            message: 'Incorrect PIN. 2 attempt(s) remaining.',
          );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool> hasPIN() async => true;

  @override
  Future<bool> isBiometricAvailable() async => true;

  @override
  Future<JsonResponse> setPIN(String pin) async =>
      JsonResponse.success(message: 'Set.');

  @override
  Future<JsonResponse> removePIN(String pin) async =>
      JsonResponse.success(message: 'Removed.');

  @override
  Future<LockoutStatus> lockoutStatus() async =>
      const LockoutStatus(failedAttempts: 0, lockedUntil: null);
}

/// [_FakeVault] is the vault's storage. [reveals] records every decryption asked
/// for, which is how the tests below prove one never happens behind the lock.
class _FakeVault implements VaultRepository {
  final List<String> reveals = [];
  final List<VaultItem> saved = [];

  @override
  Stream<List<VaultItem>> watchAll() => Stream.value([_item]);

  @override
  Stream<List<Folder>> watchFolders() => Stream.value(const []);

  @override
  Future<JsonResponse> reveal(String id) async {
    reveals.add(id);

    return JsonResponse.success(
      message: 'Loaded.',
      data: const VaultSecret(
        itemId: 'v1',
        fields: {'Password': 'hunter2'},
      ),
    );
  }

  @override
  Future<JsonResponse> save({
    required VaultItem item,
    required VaultSecret secret,
  }) async {
    saved.add(item);
    return JsonResponse.created(message: 'Saved.', data: item);
  }

  @override
  Future<JsonResponse> delete(String id) async =>
      JsonResponse.success(message: 'Deleted.');

  @override
  Future<JsonResponse> saveFolder(Folder folder) async =>
      JsonResponse.success(message: 'Saved.');

  @override
  Future<JsonResponse> deleteFolder(String id) async =>
      JsonResponse.success(message: 'Deleted.');
}

final VaultItem _item = VaultItem(
  id: 'v1',
  type: VaultItemType.password,
  name: 'Bank login',
  encryptedPayload: 'iv:ciphertext',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

/// The vault's authentication gate (Requirement 9.2).
///
/// The claim being tested is not "there is a lock screen" — that is a widget. It is
/// that **no plaintext can be produced without passing the challenge**, that the
/// challenge is fresh on every entry, and that leaving the vault forgets what was
/// decrypted. Those are properties of the bloc, and they hold however the UI is
/// later rearranged.
void main() {
  late _FakeAuth auth;
  late _FakeVault vault;

  setUp(() {
    auth = _FakeAuth();
    vault = _FakeVault();
  });

  VaultBloc build() => VaultBloc(repository: vault, authRepository: auth);

  group('the gate', () {
    test('starts locked', () {
      expect(build().state.isUnlocked, isFalse);
    });

    blocTest<VaultBloc, VaultState>(
      'a successful biometric unlocks it',
      build: build,
      act: (bloc) => bloc.add(const UnlockVaultEvent()),
      skip: 1, // the isUnlocking emission
      expect: () => [
        isA<VaultState>()
            .having((s) => s.isUnlocked, 'isUnlocked', isTrue)
            .having((s) => s.isUnlocking, 'isUnlocking', isFalse),
      ],
    );

    blocTest<VaultBloc, VaultState>(
      'a cancelled biometric leaves it locked, and is not an error',
      build: () {
        auth.isBiometricOk = false;
        return build();
      },
      act: (bloc) => bloc.add(const UnlockVaultEvent()),
      skip: 1,
      expect: () => [
        // Cancelling the prompt is the PIN fallback path (Requirement 1.3), not a
        // failure to report.
        isA<VaultState>()
            .having((s) => s.isUnlocked, 'isUnlocked', isFalse)
            .having((s) => s.error, 'error', isEmpty),
      ],
    );

    blocTest<VaultBloc, VaultState>(
      'a correct PIN unlocks it',
      build: build,
      act: (bloc) => bloc.add(const UnlockVaultWithPINEvent(pin: '1234')),
      skip: 1,
      expect: () => [
        isA<VaultState>().having((s) => s.isUnlocked, 'isUnlocked', isTrue),
      ],
      verify: (_) {
        // Through the *app's* auth repository — which is what makes a wrong guess
        // here advance the same lockout counter as a wrong guess on the lock screen
        // (Requirement 1.4). A vault with its own PIN check would have been a second
        // front door with no bolt on it.
        expect(auth.verifiedPINs, ['1234']);
      },
    );

    blocTest<VaultBloc, VaultState>(
      'a wrong PIN leaves it locked and reports the attempts left',
      build: () {
        auth.isPINOk = false;
        return build();
      },
      act: (bloc) => bloc.add(const UnlockVaultWithPINEvent(pin: '0000')),
      skip: 1,
      expect: () => [
        isA<VaultState>()
            .having((s) => s.isUnlocked, 'isUnlocked', isFalse)
            .having((s) => s.error, 'error', contains('attempt')),
      ],
    );
  });

  group('nothing is decrypted behind the lock', () {
    blocTest<VaultBloc, VaultState>(
      'a reveal while locked is refused, and never reaches the repository',
      build: build,
      act: (bloc) => bloc.add(const RevealVaultItemEvent(id: 'v1')),
      expect: () => [
        isA<VaultState>()
            .having((s) => s.error, 'error', 'The vault is locked.')
            .having((s) => s.revealed, 'revealed', isNull),
      ],
      verify: (_) {
        // The assertion that matters. Not "the UI showed an error" — the decryption
        // was never asked for.
        expect(vault.reveals, isEmpty);
      },
    );

    blocTest<VaultBloc, VaultState>(
      'a save while locked is refused',
      build: build,
      act: (bloc) => bloc.add(
        SaveVaultItemEvent(
          item: _item,
          secret: const VaultSecret(itemId: 'v1', fields: {'a': 'b'}),
        ),
      ),
      expect: () => [
        isA<VaultState>()
            .having((s) => s.error, 'error', 'The vault is locked.'),
      ],
      verify: (_) => expect(vault.saved, isEmpty),
    );

    blocTest<VaultBloc, VaultState>(
      'a reveal once unlocked produces the plaintext',
      build: build,
      act: (bloc) => bloc
        ..add(const UnlockVaultEvent())
        ..add(const RevealVaultItemEvent(id: 'v1')),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(vault.reveals, ['v1']);
        expect(bloc.state.revealed?.fields['Password'], 'hunter2');
      },
    );
  });

  group('the plaintext does not outlive the screen showing it', () {
    blocTest<VaultBloc, VaultState>(
      'leaving the vault re-locks it and drops the decrypted item',
      build: build,
      act: (bloc) async {
        bloc
          ..add(const UnlockVaultEvent())
          ..add(const RevealVaultItemEvent(id: 'v1'));

        await Future<void>.delayed(const Duration(milliseconds: 10));

        bloc.add(const LockVaultEvent());
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        // Both halves. The bloc is app-scoped and outlives the screen, so a vault
        // that stayed unlocked would be open to whoever picked the phone up next —
        // with the last person's password still sitting in its state.
        expect(bloc.state.isUnlocked, isFalse);
        expect(bloc.state.revealed, isNull);
      },
    );

    blocTest<VaultBloc, VaultState>(
      'closing the detail sheet drops the plaintext but stays unlocked',
      build: build,
      act: (bloc) async {
        bloc
          ..add(const UnlockVaultEvent())
          ..add(const RevealVaultItemEvent(id: 'v1'));

        await Future<void>.delayed(const Duration(milliseconds: 10));

        bloc.add(const ClearRevealedEvent());
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.revealed, isNull);
        // Still in the vault — the user closed one item, they did not leave.
        expect(bloc.state.isUnlocked, isTrue);
      },
    );
  });

  group('the list holds no secret', () {
    blocTest<VaultBloc, VaultState>(
      'the streamed items carry ciphertext, not contents',
      build: build,
      act: (bloc) => bloc.add(const WatchVaultEvent()),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        final items = bloc.state.items;

        expect(items, hasLength(1));
        // The vault streams from launch, while still locked — which is safe only
        // because this is true. Nothing readable has been loaded.
        expect(bloc.state.isUnlocked, isFalse);
        expect(items.single.encryptedPayload, isNot(contains('hunter2')));
        expect(bloc.state.revealed, isNull);
      },
    );

    blocTest<VaultBloc, VaultState>(
      'search matches a name and never a secret',
      build: build,
      act: (bloc) async {
        bloc
          ..add(const WatchVaultEvent())
          ..add(const SearchVaultEvent(query: 'hunter2'));

        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Requirement 9.5: contents never reach a search index. Here that holds
        // structurally — there is nothing on a VaultItem to match against, so the
        // one item's password is unfindable while its name is not.
        expect(bloc.state.visibleItems, isEmpty);

        bloc.add(const SearchVaultEvent(query: 'Bank'));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) => expect(bloc.state.visibleItems, hasLength(1)),
    );
  });
}
