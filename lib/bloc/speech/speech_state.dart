part of 'speech_bloc.dart';

/// [SpeechState] is one dictation session: three callbacks — result, level,
/// status — each update their own slice of it.
class SpeechState extends Equatable {
  const SpeechState({
    this.isListening = false,
    this.isUnavailable = false,
    this.level = 0,
    this.transcript = '',
    this.error = '',
  });

  /// [isListening] is whether the mic is open right now.
  final bool isListening;

  /// Set once the recogniser has refused — permission denied, or none on the
  /// device. Separate from [error]: this is permanent for the session and
  /// disables the mic button, while [error] is shown once and cleared.
  final bool isUnavailable;

  /// The mic's amplitude, normalised to 0..1 here rather than in the widget —
  /// the platforms disagree about the raw scale.
  final double level;

  /// [transcript] is everything heard this session, including partials.
  final String transcript;

  final String error;

  SpeechState copyWith({
    bool? isListening,
    bool? isUnavailable,
    double? level,
    String? transcript,
    String? error,
  }) {
    return SpeechState(
      isListening: isListening ?? this.isListening,
      isUnavailable: isUnavailable ?? this.isUnavailable,
      level: level ?? this.level,
      transcript: transcript ?? this.transcript,
      error: error ?? this.error,
    );
  }

  @override
  List<Object> get props => [
        isListening,
        isUnavailable,
        level,
        transcript,
        error,
      ];
}
