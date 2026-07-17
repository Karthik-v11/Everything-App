part of 'briefing_bloc.dart';

/// [BriefingState] is the line on the Dashboard's briefing card, and when it was
/// written.
class BriefingState extends Equatable {
  const BriefingState({
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.text = '',
    this.generatedAt,
    this.isFallback = false,
  });

  final bool isLoading;
  final String error;
  final String message;

  /// The briefing itself — generated prose, or [BriefingFallback]'s line.
  final String text;

  final DateTime? generatedAt;

  /// Whether [text] came from [BriefingFallback] rather than the engine. Not
  /// rendered as a warning; it exists so the regeneration policy can tell a real
  /// generation from a placeholder worth upgrading.
  final bool isFallback;

  bool get hasText => text.isNotBlank;

  /// [isStale] reuses the app's one definition of an out-of-date cache.
  bool get isStale {
    final at = generatedAt;
    if (at == null) return true;
    return clock.now().difference(at) > kStaleCacheThreshold;
  }

  /// [age] is how long ago the briefing was written.
  String get age {
    final at = generatedAt;
    if (at == null) return '';

    final elapsed = clock.now().difference(at);
    if (elapsed.inDays > 0) return '${elapsed.inDays}d ago';
    if (elapsed.inHours > 0) return '${elapsed.inHours}h ago';
    if (elapsed.inMinutes > 0) return '${elapsed.inMinutes}m ago';
    return 'just now';
  }

  BriefingState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    String? text,
    DateTime? generatedAt,
    bool? isFallback,
  }) =>
      BriefingState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        text: text ?? this.text,
        generatedAt: generatedAt ?? this.generatedAt,
        isFallback: isFallback ?? this.isFallback,
      );

  /// Restores yesterday's line so the card is populated on the first frame of a
  /// cold launch. Only the text and its timestamp persist — the loading flag and
  /// error belong to a request that did not survive the restart.
  factory BriefingState.fromJson(Map<String, dynamic> json) => BriefingState(
        text: json['HydratedText']?.toString() ?? '',
        generatedAt: DateTime.tryParse('${json['HydratedGeneratedAt']}'),
        isFallback: json['HydratedIsFallback'] == true,
      );

  Map<String, dynamic> toJson() => {
        'HydratedText': text,
        'HydratedGeneratedAt': generatedAt?.toIso8601String(),
        'HydratedIsFallback': isFallback,
      };

  @override
  List<Object?> get props => [
        isLoading,
        error,
        message,
        text,
        generatedAt,
        isFallback,
      ];
}
