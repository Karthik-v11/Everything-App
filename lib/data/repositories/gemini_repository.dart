import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/repositories/text_engine.dart';
import 'package:everything_app/data/services/gemini_service.dart';

/// [GeminiRepository] is the assistant's cloud engine behind [TextEngine].
///
/// It has no download, no load, and no unload — the three things
/// `GemmaRepository` needed and the reason the decorator now depends on the
/// narrower [TextEngine] instead. There is nothing to install and nothing to
/// evict: a key either exists or it does not.
abstract class GeminiRepository implements TextEngine {
  /// [isConfigured] is whether a key exists. Identical to [isLoaded] here, and
  /// kept separate because the settings screen asks a different question with
  /// it — "can this be used at all" rather than "can it answer now" — and the
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
