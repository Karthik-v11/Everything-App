import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/data/repositories/auth_repository.dart';
import 'package:everything_app/data/services/security_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// [AuthBloc] gates access to the app (Requirement 1).
///
/// Deliberately not a [HydratedBloc]: a persisted `isUnlocked` would restore the
/// app unlocked on the next launch. The lockout counters do survive a restart,
/// but in secure storage via [SecurityService], not here.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required this.repository}) : super(const AuthState()) {
    on<CheckAuthEvent>(_onCheckAuthEvent);
    on<AuthenticateBiometricEvent>(_onAuthenticateBiometricEvent);
    on<SubmitPINEvent>(_onSubmitPINEvent);
    on<SetPINEvent>(_onSetPINEvent);
    on<RemovePINEvent>(_onRemovePINEvent);
    on<LockEvent>(_onLockEvent);
  }

  final AuthRepository repository;

  /// When the app last went to the background. Bookkeeping, not rendered, so it
  /// lives in the bloc rather than the state.
  DateTime? _backgroundedAt;

  /// Called from the lifecycle listener on background, so a later [LockEvent]
  /// can tell how long the app was away.
  void markBackgrounded() => _backgroundedAt = DateTime.now();

  FutureOr<void> _onCheckAuthEvent(
    CheckAuthEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      emit(state.copyWith(isLoading: true, error: '', message: ''));

      // Concurrent: these are independent, and this event is the only thing
      // standing between launch and the first frame — sequential awaits cost
      // round-trips of blank screen.
      //
      // `isBiometricAvailable` is deliberately not in this group. It is two
      // sequential platform channel calls into the OS biometric subsystem — the
      // slowest of the three, where the other two are keychain reads — and the
      // gate does not need it: it decides whether the *lock screen* draws a
      // fingerprint button. With no PIN the lock screen never renders and the
      // answer is discarded, so it is resolved after the gate opens instead.
      final (hasPIN, lockout) = await (
        repository.hasPIN(),
        repository.lockoutStatus(),
      ).wait;

      // With a PIN it must be awaited after all: [LockPage] reads it once in a
      // post-frame callback to decide whether to prompt on mount, so resolving
      // it later would race that read and silently drop the auto-prompt. This
      // costs nothing in the common case, where there is no PIN.
      final biometricAvailable =
          hasPIN ? await repository.isBiometricAvailable() : false;

      // With no PIN there is nothing to authenticate against, so the app opens
      // unlocked. The lock becomes active only once a PIN is set in Settings.
      emit(
        state.copyWith(
          isLoading: false,
          isChecked: true,
          hasPIN: hasPIN,
          isBiometricAvailable: biometricAvailable,
          isUnlocked: !hasPIN,
          failedAttempts: lockout.failedAttempts,
          lockedUntil: lockout.lockedUntil,
          clearLockedUntil: lockout.lockedUntil == null,
        ),
      );

      // Resolved off the critical path for the no-PIN case: the Vault reads it
      // to offer biometric unlock, and it is reached long after this settles.
      if (!hasPIN) {
        final available = await repository.isBiometricAvailable();
        if (!isClosed) {
          emit(state.copyWith(isBiometricAvailable: available));
        }
      }
    } on Exception {
      // Unreadable security settings unlock rather than brick the app: the data
      // is protected by the database key, not by this gate. The error is shown.
      emit(
        state.copyWith(
          isLoading: false,
          isChecked: true,
          isUnlocked: true,
          error: 'Could not read your security settings.',
        ),
      );
    }
  }

  FutureOr<void> _onAuthenticateBiometricEvent(
    AuthenticateBiometricEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      emit(state.copyWith(isLoading: true, error: '', message: ''));

      final response = await repository.authenticateBiometric(
        reason: 'Unlock Everything',
      );

      if (response.success) {
        emit(state.copyWith(isLoading: false, isUnlocked: true));
      } else {
        // A cancelled or failed biometric prompt is the PIN fallback path
        // (Requirement 1.3), not an error state.
        emit(state.copyWith(isLoading: false));
      }
    } on Exception {
      emit(state.copyWith(isLoading: false));
    }
  }

  FutureOr<void> _onSubmitPINEvent(
    SubmitPINEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      emit(state.copyWith(isLoading: true, error: '', message: ''));

      final response = await repository.verifyPIN(event.pin);
      final lockout = await repository.lockoutStatus();

      if (response.success) {
        emit(
          state.copyWith(
            isLoading: false,
            isUnlocked: true,
            failedAttempts: 0,
            clearLockedUntil: true,
          ),
        );
      } else {
        emit(
          state.copyWith(
            isLoading: false,
            error: response.message,
            failedAttempts: lockout.failedAttempts,
            lockedUntil: lockout.lockedUntil,
            clearLockedUntil: lockout.lockedUntil == null,
          ),
        );
      }
    } on Exception {
      emit(
        state.copyWith(isLoading: false, error: 'Could not verify your PIN.'),
      );
    }
  }

  FutureOr<void> _onSetPINEvent(
    SetPINEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      emit(state.copyWith(isLoading: true, error: '', message: ''));

      final response = await repository.setPIN(event.pin);

      if (response.success) {
        emit(
          state.copyWith(
            isLoading: false,
            hasPIN: true,
            isUnlocked: true,
            failedAttempts: 0,
            clearLockedUntil: true,
            message: 'PIN set.',
          ),
        );
      } else {
        emit(state.copyWith(isLoading: false, error: response.message));
      }
    } on Exception {
      emit(state.copyWith(isLoading: false, error: 'Could not save your PIN.'));
    }
  }

  /// Removes the app lock. The app stays unlocked: with no PIN there is nothing
  /// to authenticate against, and [_onLockEvent] will not lock a PIN-less app.
  FutureOr<void> _onRemovePINEvent(
    RemovePINEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      emit(state.copyWith(isLoading: true, error: '', message: ''));

      final response = await repository.removePIN(event.pin);

      if (response.success) {
        emit(
          state.copyWith(
            isLoading: false,
            hasPIN: false,
            isUnlocked: true,
            failedAttempts: 0,
            clearLockedUntil: true,
            message: 'App lock removed.',
          ),
        );
      } else {
        // A wrong PIN advances the lockout counter in the service, so re-read it.
        final lockout = await repository.lockoutStatus();
        emit(
          state.copyWith(
            isLoading: false,
            error: response.message,
            failedAttempts: lockout.failedAttempts,
            lockedUntil: lockout.lockedUntil,
            clearLockedUntil: lockout.lockedUntil == null,
          ),
        );
      }
    } on Exception {
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Could not remove the app lock.',
        ),
      );
    }
  }

  /// Re-locks the app (Requirement 1.5). [LockEvent.force] (a manual lock)
  /// bypasses the duration check; otherwise the app locks only after
  /// [kAutoLockDuration] backgrounded, so a brief app switch does not re-prompt.
  FutureOr<void> _onLockEvent(LockEvent event, Emitter<AuthState> emit) {
    if (!state.hasPIN) return null;

    if (!event.force) {
      final backgroundedAt = _backgroundedAt;
      if (backgroundedAt == null) return null;
      if (DateTime.now().difference(backgroundedAt) < kAutoLockDuration) {
        return null;
      }
    }

    _backgroundedAt = null;
    emit(state.copyWith(isUnlocked: false, error: '', message: ''));
  }
}
