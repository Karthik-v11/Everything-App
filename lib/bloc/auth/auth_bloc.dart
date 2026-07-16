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
/// Style A: it holds persistent state (locked / unlocked, lockout counters) that
/// many events update in different slices.
///
/// It is not a [HydratedBloc]: a persisted `isUnlocked` would restore the app in
/// the unlocked state on the next launch. The lockout counters do survive a
/// restart, but in secure storage via [SecurityService], not here.
///
/// Events:
/// 1) [CheckAuthEvent] — decides at startup whether to gate at all.
/// 2) [AuthenticateBiometricEvent] — fingerprint / face (Requirement 1.2).
/// 3) [SubmitPINEvent] — PIN fallback (Requirement 1.3, 1.4).
/// 4) [SetPINEvent] — first-run PIN creation.
/// 5) [RemovePINEvent] — removes the app lock, gated on the current PIN.
/// 6) [LockEvent] — auto-lock on resume (Requirement 1.5).
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

  /// [_backgroundedAt] is when the app last went to the background. It lives in
  /// the bloc rather than the state because it is bookkeeping, not something the
  /// UI renders.
  DateTime? _backgroundedAt;

  /// [markBackgrounded] is called from the lifecycle listener when the app is
  /// backgrounded, so a later [LockEvent] can tell how long it was away.
  void markBackgrounded() => _backgroundedAt = DateTime.now();

  FutureOr<void> _onCheckAuthEvent(
    CheckAuthEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      emit(state.copyWith(isLoading: true, error: '', message: ''));

      // Concurrent, not sequential: two keychain reads and a pair of local_auth
      // platform calls that know nothing about each other. Awaited one after the
      // other they cost three round-trips, and the whole tree is held behind the
      // surface colour for all three — this is the single event standing between
      // launch and anything being on screen.
      final (hasPIN, biometricAvailable, lockout) = await (
        repository.hasPIN(),
        repository.isBiometricAvailable(),
        repository.lockoutStatus(),
      ).wait;

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

  /// [_onRemovePINEvent] removes the app lock. The app stays unlocked: with no
  /// PIN there is nothing to authenticate against, and [_onLockEvent] will not
  /// lock a PIN-less app.
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

  /// [_onLockEvent] re-locks the app (Requirement 1.5).
  ///
  /// [LockEvent.force] bypasses the duration check — used when the user locks
  /// manually. Otherwise the app only locks if it was backgrounded for longer
  /// than [kAutoLockDuration], so briefly switching apps does not force a
  /// re-authentication.
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
