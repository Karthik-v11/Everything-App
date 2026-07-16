part of 'auth_bloc.dart';

/// [AuthEvent] is the base class for every authentication event.
abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object> get props => [];
}

/// [CheckAuthEvent] runs once at startup to establish whether the app should be
/// gated at all, and to restore any lockout that was in force.
class CheckAuthEvent extends AuthEvent {
  const CheckAuthEvent();
}

/// [AuthenticateBiometricEvent] prompts for fingerprint / face
/// (Requirement 1.2).
class AuthenticateBiometricEvent extends AuthEvent {
  const AuthenticateBiometricEvent();
}

/// [SubmitPINEvent] submits a PIN attempt (Requirement 1.3).
/// [pin] is the entered code.
class SubmitPINEvent extends AuthEvent {
  const SubmitPINEvent({required this.pin});

  final String pin;

  @override
  List<Object> get props => [pin];
}

/// [SetPINEvent] creates or replaces the PIN.
/// [pin] is the new code.
class SetPINEvent extends AuthEvent {
  const SetPINEvent({required this.pin});

  final String pin;

  @override
  List<Object> get props => [pin];
}

/// [RemovePINEvent] removes the app lock entirely.
///
/// [pin] is the *current* PIN: removing the lock is an authenticated action, not
/// a toggle.
class RemovePINEvent extends AuthEvent {
  const RemovePINEvent({required this.pin});

  final String pin;

  @override
  List<Object> get props => [pin];
}

/// [LockEvent] re-locks the app (Requirement 1.5).
///
/// [force] locks immediately. When false, the app locks only if it has been
/// backgrounded longer than the auto-lock duration.
class LockEvent extends AuthEvent {
  const LockEvent({this.force = false});

  final bool force;

  @override
  List<Object> get props => [force];
}
