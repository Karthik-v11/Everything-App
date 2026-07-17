import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/repositories/text_engine.dart';
import 'package:everything_app/data/services/gemini_service.dart';

/// [GeminiRepository] is the assistant's cloud engine behind [TextEngine].
/// It has no download, load or unload: a key either exists or it does not.
abstract class GeminiRepository implements TextEngine {
  /// [isConfigured] is whether a key exists — "can this be used at all", the
  /// question the settings screen asks. Identical to [isLoaded] here, but the
  /// two come apart for any engine with a lifecycle.
  bool get isConfigured;
}

class GeminiRepositoryImpl implements GeminiRepository {
  const GeminiRepositoryImpl({required this.geminiService});

  final GeminiService geminiService;

  @override
  bool get isLoaded => geminiService.isConfigured;

  @override
  bool get isConfigured => geminiService.isConfigured;

  @override
  Future<JsonResponse> generate(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens = 256,
  }) =>
      geminiService.generate(
        prompt,
        systemInstruction: systemInstruction,
        maxOutputTokens: maxOutputTokens,
      );
}
