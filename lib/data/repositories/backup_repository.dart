import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/services/backup_service.dart';
import 'package:everything_app/data/services/security_service.dart';

/// [BackupRepository] defines the contract for encrypted backup and restore
/// (Requirement 22).
abstract class BackupRepository {
  /// [createBackup] writes one encrypted, integrity-tagged backup to local
  /// storage, sealed with [pin]. On success [JsonResponse.data] is a
  /// `BackupMetadata`.
  Future<JsonResponse> createBackup({required String pin});

  /// [restoreFromFile] verifies a backup's integrity tag using [pin] and, only if
  /// it passes, replaces the database with its contents (Requirement 22.6).
  Future<JsonResponse> restoreFromFile(String path, {required String pin});

  /// [hasBackupPIN] is true once a backup PIN has been set.
  Future<bool> hasBackupPIN();

  /// [setBackupPIN] stores the PIN that new backups are sealed with.
  Future<JsonResponse> setBackupPIN(String pin);

  /// [backupPIN] returns the stored PIN, so an automatic backup can seal without
  /// prompting.
  Future<JsonResponse> backupPIN();

  /// [listBackups] returns the on-device backups, newest first, as a
  /// `List<BackupMetadata>`.
  Future<JsonResponse> listBackups();

  /// [deleteBackup] removes one backup file.
  Future<JsonResponse> deleteBackup(String path);
}

class BackupRepositoryImpl implements BackupRepository {
  const BackupRepositoryImpl({
    required this.backupService,
    required this.securityService,
  });

  final BackupService backupService;
  final SecurityService securityService;

  @override
  Future<JsonResponse> createBackup({required String pin}) =>
      backupService.createBackup(pin: pin);

  @override
  Future<JsonResponse> restoreFromFile(String path, {required String pin}) =>
      backupService.restoreFromFile(path, pin: pin);

  @override
  Future<bool> hasBackupPIN() => securityService.hasBackupPIN();

  @override
  Future<JsonResponse> setBackupPIN(String pin) =>
      securityService.setBackupPIN(pin);

  @override
  Future<JsonResponse> backupPIN() => securityService.backupPIN();

  @override
  Future<JsonResponse> listBackups() => backupService.listBackups();

  @override
  Future<JsonResponse> deleteBackup(String path) =>
      backupService.deleteBackup(path);
}
