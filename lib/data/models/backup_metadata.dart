import 'package:equatable/equatable.dart';

/// [BackupMetadata] describes one encrypted backup file on disk (Requirement 22).
///
/// It is derived from the filesystem — path, modified time and size — not parsed
/// from the backup's own contents, which stay encrypted until a restore. So it
/// carries no `fromJson`/`toJson`: there is nothing to decode without the key,
/// and the list screen never needs one.
class BackupMetadata extends Equatable {
  const BackupMetadata({
    required this.path,
    required this.createdAt,
    required this.sizeBytes,
  });

  /// The absolute path to the `.evbak` file.
  final String path;

  /// When the file was written, read from its filesystem timestamp.
  final DateTime createdAt;

  /// The encrypted size on disk.
  final int sizeBytes;

  @override
  List<Object?> get props => [path, createdAt, sizeBytes];
}
