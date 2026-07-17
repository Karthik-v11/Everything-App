import 'package:everything_app/data/models/json_response.dart';

/// [TextEngine] is the two things [ModelBackedAiRepository] needs from a
/// generator: whether it can answer now, and prose when it can.
///
/// Deliberately narrow: no download/load lifecycle, which a cloud engine has no
/// equivalent for — [GeminiRepository] satisfies this without inventing a
/// download step.
abstract class TextEngine {
  /// [isLoaded] is whether the engine can answer **now** — for the cloud engine,
  /// a key being present (reachability is only knowable by calling). A `false` —
  /// or a failed [generate] — sends the caller to the rule-based engine.
  bool get isLoaded;

  /// [generate] returns prose, or a failure the caller reads as "fall back".
  Future<JsonResponse> generate(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens,
  });
}
