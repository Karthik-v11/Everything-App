part of 'ai_bloc.dart';

/// [AiEvent] is the base class for AI assistant events.
abstract class AiEvent extends Equatable {
  const AiEvent();

  @override
  List<Object?> get props => [];
}

/// [AiOpened] resets the sheet to a clean session. The bloc is app-scoped, so
/// without this the sheet reopens showing the last session's results.
class AiOpened extends AiEvent {
  const AiOpened();
}

/// [AiInputChanged] reports the field's text. Debounced: a burst of keystrokes
/// re-classifies and re-previews once on the settled line, not once per character.
class AiInputChanged extends AiEvent {
  const AiInputChanged({required this.input});

  final String input;

  @override
  List<Object?> get props => [input];
}

/// [AiModeSelected] is the user overriding the guessed mode, which pins it against
/// further re-classification.
class AiModeSelected extends AiEvent {
  const AiModeSelected({required this.mode});

  final AiIntent mode;

  @override
  List<Object?> get props => [mode];
}

/// [AiSubmitted] runs the current mode's action over [input]. It carries the
/// field's live text rather than the debounced state, so a fast "type and send"
/// never acts on a line one keystroke behind.
class AiSubmitted extends AiEvent {
  const AiSubmitted({required this.input});

  final String input;

  @override
  List<Object?> get props => [input];
}

/// [ConfigureAiEvent] sets the confidence threshold the assistant acts at,
/// pushed by [SettingsBloc] (Requirement 25.3). The assistant is told, never
/// reads it — cross-bloc configuration goes by event dispatch (CLAUDE.md §4.4).
class ConfigureAiEvent extends AiEvent {
  const ConfigureAiEvent({required this.confidence});

  final double confidence;

  @override
  List<Object?> get props => [confidence];
}
