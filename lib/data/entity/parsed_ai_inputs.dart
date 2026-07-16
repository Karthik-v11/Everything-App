import 'package:everything_app/data/entity/ai_intent.dart';
import 'package:everything_app/data/models/vault_item.dart';
import 'package:everything_app/data/models/watchlist_item.dart';

/// [ParsedBookmarkInput] holds the bookmark URL extracted from natural language.
class ParsedBookmarkInput {
  const ParsedBookmarkInput({required this.url, required this.confidence});

  final String url;
  final double confidence;

  /// Gated against the user's threshold (Requirement 25.3); the emptiness check
  /// holds at every threshold, because a bookmark with no URL is not a bookmark.
  bool isConfidentAt(double threshold) =>
      confidence >= threshold && url.isNotEmpty;

  bool get isConfident => isConfidentAt(kAiConfidenceThreshold);
}

/// [ParsedToBuyInput] holds the to-buy item name parsed from input.
class ParsedToBuyInput {
  const ParsedToBuyInput({
    required this.name,
    required this.confidence,
    this.store,
    this.estimatedPriceMinor,
  });

  final String name;
  final String? store;
  final int? estimatedPriceMinor;
  final double confidence;

  bool isConfidentAt(double threshold) =>
      confidence >= threshold && name.isNotEmpty;

  bool get isConfident => isConfidentAt(kAiConfidenceThreshold);
}

/// [ParsedWatchInput] holds the watchlist entry parsed from input.
class ParsedWatchInput {
  const ParsedWatchInput({
    required this.title,
    required this.mediaType,
    required this.confidence,
  });

  final String title;
  final MediaType mediaType;
  final double confidence;

  bool isConfidentAt(double threshold) =>
      confidence >= threshold && title.isNotEmpty;

  bool get isConfident => isConfidentAt(kAiConfidenceThreshold);
}

/// [ParsedVaultInput] holds the vault item parsed from input.
class ParsedVaultInput {
  const ParsedVaultInput({
    required this.name,
    required this.type,
    required this.confidence,
  });

  final String name;
  final VaultItemType type;
  final double confidence;

  bool isConfidentAt(double threshold) =>
      confidence >= threshold && name.isNotEmpty;

  bool get isConfident => isConfidentAt(kAiConfidenceThreshold);
}

/// [ParsedProjectInput] holds the project name parsed from input.
class ParsedProjectInput {
  const ParsedProjectInput({
    required this.name,
    required this.confidence,
    this.description,
  });

  final String name;
  final String? description;
  final double confidence;

  bool isConfidentAt(double threshold) =>
      confidence >= threshold && name.isNotEmpty;

  bool get isConfident => isConfidentAt(kAiConfidenceThreshold);
}
