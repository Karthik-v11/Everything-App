import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/services/backup_service.dart';

/// [BackupRepository] defines the contract for encrypted backup and restore
/// (Requirement 22).
abstract class BackupRepository {
  /// [createBackup] writes one encrypted, integrity-tagged backup to local
  /// storage. On success [JsonResponse.data] is a `BackupMetadata`.
  Future<JsonResponse> createBackup();

  /// [restoreFromFile] verifies a backup's integrity tag and, only if it passes,
  /// replaces the database with its contents (Requirement 22.6).
  Future<JsonResponse> restoreFromFile(String path);

  /// [listBackups] returns the on-device backups, newest first, as a
  /// `List<BackupMetadata>`.
  Future<JsonResponse> listBackups();

  /// [deleteBackup] removes one backup file.
  Future<JsonResponse> deleteBackup(String path);
}

class BackupRepositoryImpl implements BackupRepository {
  const BackupRepositoryImpl({required this.backupService});

  final BackupService backupService;

  @override
  Future<JsonResponse> createBackup() => backupService.createBackup();

  @override
  Future<JsonResponse> restoreFromFile(String path) =>
      backupService.restoreFromFile(path);

  @override
  Future<JsonResponse> listBackups() => backupService.listBackups();

  @override
  Future<JsonResponse> deleteBackup(String path) =>
      backupService.deleteBackup(path);
}
