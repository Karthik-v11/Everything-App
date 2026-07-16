import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/services/security_service.dart';

/// [AuthRepository] defines the contract for app access control.
abstract class AuthRepository {
  /// [databaseKey] returns the SQLCipher key, creating it on first launch.
  Future<JsonResponse> databaseKey();

  /// [hasPIN] is true once a PIN has been set.
  Future<bool> hasPIN();

  /// [setPIN] stores a new PIN as a salted hash.
  Future<JsonResponse> setPIN(String pin);

  /// [verifyPIN] checks a PIN and advances the lockout counter on failure.
  Future<JsonResponse> verifyPIN(String pin);

  /// [removePIN] deletes the PIN, but only if the given one is correct.
  Future<JsonResponse> removePIN(String pin);

  /// [lockoutStatus] is the current failure count and lockout expiry.
  Future<LockoutStatus> lockoutStatus();

  /// [isBiometricAvailable] is true when the device has enrolled biometrics.
  Future<bool> isBiometricAvailable();

  /// [authenticateBiometric] prompts for fingerprint / face.
  Future<JsonResponse> authenticateBiometric({required String reason});
}

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({required this.securityService});

  final SecurityService securityService;

  @override
  Future<JsonResponse> databaseKey() => securityService.databaseKey();

  @override
  Future<bool> hasPIN() => securityService.hasPIN();

  @override
  Future<JsonResponse> setPIN(String pin) => securityService.setPIN(pin);

  @override
  Future<JsonResponse> verifyPIN(String pin) => securityService.verifyPIN(pin);

  @override
  Future<JsonResponse> removePIN(String pin) => securityService.removePIN(pin);

  @override
  Future<LockoutStatus> lockoutStatus() => securityService.lockoutStatus();

  @override
  Future<bool> isBiometricAvailable() => securityService.isBiometricAvailable();

  @override
  Future<JsonResponse> authenticateBiometric({required String reason}) =>
      securityService.authenticateBiometric(reason: reason);
}
