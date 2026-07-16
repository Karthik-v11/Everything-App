import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/models/folder.dart';
import 'package:everything_app/data/models/vault_item.dart';
import 'package:everything_app/data/repositories/auth_repository.dart';
import 'package:everything_app/data/repositories/vault_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'vault_event.dart';
part 'vault_state.dart';

/// [VaultBloc] owns the Vault (Requirement 9).
///
/// Style A: it holds the item list, the folders, the filters, and the lock.
///
/// **It is deliberately not a [HydratedBloc].** A persisted `isUnlocked` would
/// restore the vault open on the next launch, which is precisely the thing
/// Requirement 9.2 exists to prevent. The lock is session state and dies with the
/// process — the same reasoning as [AuthBloc].
///
/// Three rules make this a vault rather than a list with a password on it:
///
/// 1. **The challenge is fresh, and it is not the app's.** Unlocking the app gets
///    you as far as the Library; it does not get you into the vault. This bloc runs
///    its own biometric-or-PIN challenge on entry, through the same
///    [AuthRepository] — so the same lockout policy applies to a vault guess as to
///    an app guess (Requirement 1.4), and an attacker cannot get unlimited attempts
///    by coming in through the vault instead of the lock screen.
///
/// 2. **It re-locks when the screen is left.** [LockVaultEvent] fires from the
///    vault screen's `dispose`, so leaving and coming back is a new entry and a new
///    challenge. A vault that stayed open for the life of the process would be open
///    to whoever picked the phone up next, which is the case it exists for.
///
/// 3. **The list never holds a plaintext.** [items] are ciphertext blobs; exactly
///    one item is decrypted at a time, into [VaultState.revealed], when its detail
///    screen opens — and it is cleared when that screen closes ([ClearRevealedEvent]).
///
/// Events:
/// 1) [WatchVaultEvent] — subscribe to items and folders. Fired once.
/// 2) [VaultFoldersUpdatedEvent] — a folder was added, renamed or removed.
/// 3) [UnlockVaultEvent] / [UnlockVaultWithPINEvent] — the entry challenge.
/// 4) [LockVaultEvent] — leaving the vault.
/// 5) [RevealVaultItemEvent] / [ClearRevealedEvent] — the detail screen.
/// 6) [SaveVaultItemEvent] / [DeleteVaultItemEvent] — the sheet and the swipe.
/// 7) [FilterVaultEvent] / [SearchVaultEvent] — narrowing the list.
/// 8) [SaveVaultFolderEvent] / [DeleteVaultFolderEvent] — folder management.
class VaultBloc extends Bloc<VaultEvent, VaultState> {
  VaultBloc({
    required this.repository,
    required this.authRepository,
  }) : super(const VaultState()) {
    on<WatchVaultEvent>(_onWatchVaultEvent);
    on<VaultFoldersUpdatedEvent>(_onVaultFoldersUpdatedEvent);
    on<UnlockVaultEvent>(_onUnlockVaultEvent);
    on<UnlockVaultWithPINEvent>(_onUnlockVaultWithPINEvent);
    on<LockVaultEvent>(_onLockVaultEvent);
    on<RevealVaultItemEvent>(_onRevealVaultItemEvent);
    on<ClearRevealedEvent>(_onClearRevealedEvent);
    on<SaveVaultItemEvent>(_onSaveVaultItemEvent);
    on<DeleteVaultItemEvent>(_onDeleteVaultItemEvent);
    on<FilterVaultEvent>(_onFilterVaultEvent);
    on<SearchVaultEvent>(_onSearchVaultEvent);
    on<SaveVaultFolderEvent>(_onSaveVaultFolderEvent);
    on<DeleteVaultFolderEvent>(_onDeleteVaultFolderEvent);
  }

  final VaultRepository repository;
  final AuthRepository authRepository;

  StreamSubscription<List<Folder>>? _folders;

  /// [_onWatchVaultEvent] subscribes to the vault's rows.
  ///
  /// It runs whether or not the vault is unlocked, and that is safe *because* of how
  /// [VaultItem] is shaped: every payload on this stream is ciphertext. Streaming
  /// the list behind the lock means the vault is ready the instant the challenge is
  /// passed, rather than the user staring at a spinner having just proved who they
  /// are — and nothing readable has been loaded in the meantime.
  FutureOr<void> _onWatchVaultEvent(
    WatchVaultEvent event,
    Emitter<VaultState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: '', message: ''));

    await _folders?.cancel();
    _folders = repository.watchFolders().listen(
          (folders) => add(VaultFoldersUpdatedEvent(folders: folders)),
          onError: (_) => add(
            const VaultFoldersUpdatedEvent(
              folders: <Folder>[],
              hasFailed: true,
            ),
          ),
        );

    await emit.forEach<List<VaultItem>>(
      repository.watchAll(),
      onData: (items) =>
          state.copyWith(isLoading: false, items: items, error: ''),
      onError: (_, _) => state.copyWith(
        isLoading: false,
        error: 'Could not load your vault.',
      ),
    );
  }

  FutureOr<void> _onVaultFoldersUpdatedEvent(
    VaultFoldersUpdatedEvent event,
    Emitter<VaultState> emit,
  ) {
    emit(
      event.hasFailed
          ? state.copyWith(error: 'Could not load your folders.')
          : state.copyWith(folders: event.folders, error: ''),
    );
  }

  // ── The gate (Requirement 9.2) ─────────────────────────────────────────────

  /// [_onUnlockVaultEvent] runs the biometric challenge.
  ///
  /// A failed or cancelled prompt is **not** an error: it is the PIN fallback path,
  /// exactly as on the lock screen (Requirement 1.3). The vault simply stays locked
  /// and the screen offers the PIN.
  FutureOr<void> _onUnlockVaultEvent(
    UnlockVaultEvent event,
    Emitter<VaultState> emit,
  ) async {
    try {
      emit(state.copyWith(isUnlocking: true, error: ''));

      final response = await authRepository.authenticateBiometric(
        reason: 'Unlock your vault',
      );

      emit(
        state.copyWith(
          isUnlocking: false,
          isUnlocked: response.success,
        ),
      );
    } on Exception {
      emit(state.copyWith(isUnlocking: false));
    }
  }

  /// [_onUnlockVaultWithPINEvent] is the PIN fallback.
  ///
  /// It goes through the same [AuthRepository.verifyPIN] as the app's lock screen,
  /// so a wrong guess here advances the *same* lockout counter (Requirement 1.4).
  /// A separate vault PIN check would have been a second front door with no bolt on
  /// it: three guesses at the lock screen, three more at the vault.
  FutureOr<void> _onUnlockVaultWithPINEvent(
    UnlockVaultWithPINEvent event,
    Emitter<VaultState> emit,
  ) async {
    try {
      emit(state.copyWith(isUnlocking: true, error: ''));

      final response = await authRepository.verifyPIN(event.pin);

      emit(
        response.success
            ? state.copyWith(isUnlocking: false, isUnlocked: true, error: '')
            : state.copyWith(isUnlocking: false, error: response.message),
      );
    } on Exception {
      emit(
        state.copyWith(
          isUnlocking: false,
          error: 'Could not verify your PIN.',
        ),
      );
    }
  }

  /// [_onLockVaultEvent] re-locks the vault and **drops the revealed plaintext**.
  ///
  /// Both halves matter. Leaving the vault must not leave a decrypted secret sitting
  /// in the state of a bloc that outlives the screen — the bloc is app-scoped, and
  /// the next thing to open the vault would find the last person's password already
  /// in memory.
  FutureOr<void> _onLockVaultEvent(
    LockVaultEvent event,
    Emitter<VaultState> emit,
  ) {
    emit(
      state.copyWith(
        isUnlocked: false,
        isUnlocking: false,
        clearRevealed: true,
        error: '',
        message: '',
      ),
    );
  }

  // ── Contents ───────────────────────────────────────────────────────────────

  /// [_onRevealVaultItemEvent] decrypts exactly one item, for the detail screen.
  ///
  /// Refused outright while the vault is locked. Nothing in the app should be able
  /// to reach this event without having passed the challenge, but a decryption that
  /// checked would be one fewer way for a future screen to get it wrong.
  FutureOr<void> _onRevealVaultItemEvent(
    RevealVaultItemEvent event,
    Emitter<VaultState> emit,
  ) async {
    if (!state.isUnlocked) {
      emit(state.copyWith(error: 'The vault is locked.'));
      return;
    }

    try {
      emit(state.copyWith(isRevealing: true, error: '', clearRevealed: true));

      final response = await repository.reveal(event.id);

      if (!response.success || response.data is! VaultSecret) {
        emit(
          state.copyWith(isRevealing: false, error: response.message),
        );
        return;
      }

      emit(
        state.copyWith(
          isRevealing: false,
          revealed: response.data! as VaultSecret,
          error: '',
        ),
      );
    } on Exception {
      emit(
        state.copyWith(
          isRevealing: false,
          error: 'Could not read this item.',
        ),
      );
    }
  }

  /// [_onClearRevealedEvent] drops the plaintext when the detail screen closes.
  ///
  /// This is the other half of "plaintext is never held in list state": it exists in
  /// exactly one field, for exactly as long as one screen is showing it.
  FutureOr<void> _onClearRevealedEvent(
    ClearRevealedEvent event,
    Emitter<VaultState> emit,
  ) {
    emit(state.copyWith(clearRevealed: true));
  }

  FutureOr<void> _onSaveVaultItemEvent(
    SaveVaultItemEvent event,
    Emitter<VaultState> emit,
  ) async {
    if (!state.isUnlocked) {
      emit(state.copyWith(error: 'The vault is locked.'));
      return;
    }

    try {
      final response = await repository.save(
        item: event.item,
        secret: event.secret,
      );

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not save this item.'));
    }
  }

  FutureOr<void> _onDeleteVaultItemEvent(
    DeleteVaultItemEvent event,
    Emitter<VaultState> emit,
  ) async {
    try {
      final response = await repository.delete(event.id);

      emit(
        response.success
            // The deleted item may be the one currently revealed, and its plaintext
            // must not outlive the row it came from.
            ? state.copyWith(
                message: response.message,
                error: '',
                clearRevealed: state.revealed?.itemId == event.id,
              )
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not delete this item.'));
    }
  }

  // ── Narrowing ──────────────────────────────────────────────────────────────

  FutureOr<void> _onFilterVaultEvent(
    FilterVaultEvent event,
    Emitter<VaultState> emit,
  ) {
    emit(
      state.copyWith(
        type: event.type,
        clearType: event.type == null,
        folderId: event.folderId,
        clearFolderId: event.folderId == null,
      ),
    );
  }

  FutureOr<void> _onSearchVaultEvent(
    SearchVaultEvent event,
    Emitter<VaultState> emit,
  ) {
    emit(state.copyWith(query: event.query));
  }

  FutureOr<void> _onSaveVaultFolderEvent(
    SaveVaultFolderEvent event,
    Emitter<VaultState> emit,
  ) async {
    try {
      final response = await repository.saveFolder(event.folder);

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not save the folder.'));
    }
  }

  FutureOr<void> _onDeleteVaultFolderEvent(
    DeleteVaultFolderEvent event,
    Emitter<VaultState> emit,
  ) async {
    try {
      final response = await repository.deleteFolder(event.id);

      emit(
        response.success
            ? state.copyWith(
                message: response.message,
                error: '',
                clearFolderId: state.folderId == event.id,
              )
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not delete the folder.'));
    }
  }

  @override
  Future<void> close() {
    _folders?.cancel();
    return super.close();
  }
}
