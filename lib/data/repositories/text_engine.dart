import 'package:everything_app/data/models/json_response.dart';

/// [TextEngine] is the two things [ModelBackedAiRepository] actually needs from
/// a generator: whether it can answer now, and prose when it can.
///
/// It exists because the engine changed and the decorator did not. Phase 13
/// typed the decorator to `GemmaRepository`, which also carries a download and
/// load lifecycle — `isInstalled`, `download`, `load`, `unload`, `remove` —
/// none of which a cloud call has, and none of which the decorator ever used.
/// Naming the smaller surface lets [GeminiRepository] satisfy it without
/// inventing a download step it does not have, and lets `GemmaRepository` keep
/// its lifecycle for the settings screen that still drives it.
abstract class TextEngine {
  /// [isLoaded] is whether the engine can answer **now**.
  ///
  /// For an on-device model that means weights in memory. For a cloud call it
  /// means a key exists — reachability is only knowable by calling, so a
  /// `true` here is a claim about configuration, not connectivity. Both are
  /// honest for the same reason: a `false` sends the caller to the rule-based
  /// engine, and so does a failed [generate].
  bool get isLoaded;

  /// [generate] returns prose, or a failure the caller reads as "fall back".
  Future<JsonResponse> generate(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens,
  });
}
