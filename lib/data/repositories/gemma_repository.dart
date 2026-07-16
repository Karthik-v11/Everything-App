import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/repositories/text_engine.dart';
import 'package:everything_app/data/services/gemma_service.dart';

/// [GemmaRepository] is the on-device model's lifecycle, as the app sees it
/// (Phase 13).
///
/// It is a normal repository returning `Future<JsonResponse>` (CLAUDE.md §5).
/// The AI layer's documented exception — bare domain types — belongs to
/// [AiRepository], which is about *parsing*; downloading 584 MB is an ordinary
/// fallible operation with an ordinary result, and [OnDeviceModelBloc] branches
/// on it exactly like every other bloc in the app.
abstract class GemmaRepository implements TextEngine {
  /// [isInstalled] is whether the weights are on disk.
  Future<bool> isInstalled();

  /// [isLoaded] is whether the model is in memory and can answer now.
  @override
  bool get isLoaded;

  /// [download] fetches the model, reporting progress as a percentage.
  Future<JsonResponse> download({required void Function(int percent) onProgress});

  /// [load] brings a downloaded model into memory.
  Future<JsonResponse> load();

  /// [unload] frees the model's memory, leaving the download on disk.
  Future<void> unload();

  /// [remove] unloads the model and deletes the download.
  Future<JsonResponse> remove();

  /// [generate] runs one grounded prompt and returns the model's text as
  /// [JsonResponse.data].
  @override
  Future<JsonResponse> generate(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens,
  });

  /// [isConfigured] is whether a HuggingFace token exists to download with. False
  /// is not an error — it is a build without the key, which the UI states plainly
  /// rather than failing at the end of a download.
  bool get isConfigured;

  /// [downloadSizeBytes] is what the download will cost, for a UI that warns
  /// before rather than after.
  int get downloadSizeBytes;
}

class GemmaRepositoryImpl implements GemmaRepository {
  const GemmaRepositoryImpl({required this.gemmaService});

  final GemmaService gemmaService;

  @override
  Future<bool> isInstalled() => gemmaService.isInstalled();

  @override
  bool get isLoaded => gemmaService.isLoaded;

  @override
  Future<JsonResponse> download({
    required void Function(int percent) onProgress,
  }) =>
      gemmaService.install(onProgress: onProgress);

  @override
  Future<JsonResponse> load() => gemmaService.load();

  @override
  Future<void> unload() => gemmaService.unload();

  @override
  Future<JsonResponse> remove() => gemmaService.uninstall();

  @override
  Future<JsonResponse> generate(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens = 256,
  }) =>
      gemmaService.generate(
        prompt,
        systemInstruction: systemInstruction,
        maxOutputTokens: maxOutputTokens,
      );

  @override
  bool get isConfigured => GemmaService.huggingFaceToken.isNotEmpty;

  @override
  int get downloadSizeBytes => GemmaService.modelSizeBytes;
}
