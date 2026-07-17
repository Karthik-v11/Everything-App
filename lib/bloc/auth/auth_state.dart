part of 'auth_bloc.dart';

/// [AuthState] holds the app's lock state (Requirement 1).
///
/// [isChecked] is false until [CheckAuthEvent] completes; `Application` withholds
/// the tree until then, so a locked app never flashes its contents.
/// [isUnlocked] is the gate the router reads.
/// [hasPIN] is false when no PIN has been set, and such a user is never locked.
/// [failedAttempts] and [lockedUntil] mirror the persisted lockout, and drive the
/// countdown on the lock screen.
class AuthState extends Equatable {
  const AuthState({
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.isChecked = false,
    this.isUnlocked = false,
    this.hasPIN = false,
    this.isBiometricAvailable = false,
    this.failedAttempts = 0,
    this.lockedUntil,
  });

  final bool isLoading;
  final String error;
  final String message;
  final bool isChecked;
  final bool isUnlocked;
  final bool hasPIN;
  final bool isBiometricAvailable;
  final int failedAttempts;
  final DateTime? lockedUntil;

  /// [isLockedOut] is true while the 30-second penalty is running
  /// (Requirement 1.4).
  bool get isLockedOut =>
      lockedUntil != null && lockedUntil!.isAfter(DateTime.now().toUtc());

  /// [lockoutRemaining] drives the countdown on the lock screen.
  Duration get lockoutRemaining => isLockedOut
      ? lockedUntil!.difference(DateTime.now().toUtc())
      : Duration.zero;

  int get attemptsRemaining =>
      (kMaxPINAttempts - failedAttempts).clamp(0, kMaxPINAttempts);

  /// [clearLockedUntil] is required to clear a lockout: under the `??` idiom,
  /// `lockedUntil: null` is indistinguishable from the argument not being passed.
  AuthState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    bool? isChecked,
    bool? isUnlocked,
    bool? hasPIN,
    bool? isBiometricAvailable,
    int? failedAttempts,
    DateTime? lockedUntil,
    bool clearLockedUntil = false,
  }) =>
      AuthState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        isChecked: isChecked ?? this.isChecked,
        isUnlocked: isUnlocked ?? this.isUnlocked,
        hasPIN: hasPIN ?? this.hasPIN,
        isBiometricAvailable:
            isBiometricAvailable ?? this.isBiometricAvailable,
        failedAttempts: failedAttempts ?? this.failedAttempts,
        lockedUntil: clearLockedUntil ? null : (lockedUntil ?? this.lockedUntil),
      );

  @override
  List<Object?> get props => [
        isLoading,
        error,
        message,
        isChecked,
        isUnlocked,
        hasPIN,
        isBiometricAvailable,
        failedAttempts,
        lockedUntil,
      ];
}
