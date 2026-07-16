part of 'on_device_model_bloc.dart';

/// [OnDeviceModelState] is the on-device model's status (Phase 13).
///
/// Style A. Nothing here is persisted: [isEnabled] is the user's setting and is
/// owned by [SettingsBloc], and [isInstalled] is re-read from disk at launch for
/// the reason Phase 11 re-read its backup list rather than remembering it — the
/// OS can reclaim a 584 MB file, and a remembered "installed" is a lie that only
/// surfaces as a failed load.
class OnDeviceModelState extends Equatable {
  const OnDeviceModelState({
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.isEnabled = false,
    this.isInstalled = false,
    this.isLoaded = false,
    this.isDownloading = false,
    this.progress = 0,
    this.isConfigured = false,
    this.downloadSizeBytes = 0,
  });

  final bool isLoading;
  final String error;
  final String message;

  /// The user's switch. Off by default — the assistant is fully functional
  /// without a model, and 584 MB is not something to fetch on someone's behalf.
  final bool isEnabled;

  /// Whether the weights are on disk.
  final bool isInstalled;

  /// Whether the weights are in memory and can answer now. This is the only
  /// field [ModelBackedAiRepository] cares about, and it reads it from the
  /// repository rather than from here — a bloc's state is not another layer's
  /// data source.
  final bool isLoaded;

  final bool isDownloading;

  /// Download progress, 0–100.
  final int progress;

  /// Whether a HuggingFace token exists to download with. False is not an
  /// error — it is a build without the key, the same as a build with no weather
  /// key (Phase 6, note 5) — and the UI says so instead of offering a download
  /// that would 401 at the end.
  final bool isConfigured;

  final int downloadSizeBytes;

  /// [isDownloadable] is whether offering the download is honest: a token
  /// exists, nothing is on disk, and nothing is in flight.
  bool get isDownloadable =>
      isConfigured && !isInstalled && !isDownloading && !isLoading;

  /// [isActive] is whether the assistant's prose is actually model-backed right
  /// now — which is the only claim the Settings section is entitled to make.
  bool get isActive => isEnabled && isLoaded;

  /// [downloadSizeLabel] is the download's cost in whole MB, for a warning shown
  /// before rather than after.
  String get downloadSizeLabel =>
      '${(downloadSizeBytes / (1000 * 1000)).round()} MB';

  OnDeviceModelState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    bool? isEnabled,
    bool? isInstalled,
    bool? isLoaded,
    bool? isDownloading,
    int? progress,
    bool? isConfigured,
    int? downloadSizeBytes,
  }) =>
      OnDeviceModelState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        isEnabled: isEnabled ?? this.isEnabled,
        isInstalled: isInstalled ?? this.isInstalled,
        isLoaded: isLoaded ?? this.isLoaded,
        isDownloading: isDownloading ?? this.isDownloading,
        progress: progress ?? this.progress,
        isConfigured: isConfigured ?? this.isConfigured,
        downloadSizeBytes: downloadSizeBytes ?? this.downloadSizeBytes,
      );

  @override
  List<Object?> get props => [
        isLoading,
        error,
        message,
        isEnabled,
        isInstalled,
        isLoaded,
        isDownloading,
        progress,
        isConfigured,
        downloadSizeBytes,
      ];
}
