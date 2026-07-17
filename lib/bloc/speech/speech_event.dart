part of 'speech_bloc.dart';

sealed class SpeechEvent extends Equatable {
  const SpeechEvent();

  @override
  List<Object> get props => [];
}

/// [StartDictationEvent] opens the mic, asking for permission the first time.
class StartDictationEvent extends SpeechEvent {
  const StartDictationEvent();
}

/// [StopDictationEvent] closes the mic and keeps what was heard.
class StopDictationEvent extends SpeechEvent {
  const StopDictationEvent();
}

/// [CancelDictationEvent] closes the mic and throws the session away. Distinct
/// from [StopDictationEvent]: only "done" should leave text in the field.
class CancelDictationEvent extends SpeechEvent {
  const CancelDictationEvent();
}

/// [DictationHeardEvent] is the recogniser reporting the text so far.
class DictationHeardEvent extends SpeechEvent {
  const DictationHeardEvent({required this.text, required this.isFinal});

  final String text;
  final bool isFinal;

  @override
  List<Object> get props => [text, isFinal];
}

/// [DictationLevelEvent] is the mic's amplitude, raw and unnormalised.
class DictationLevelEvent extends SpeechEvent {
  const DictationLevelEvent({required this.level});

  final double level;

  @override
  List<Object> get props => [level];
}

/// [DictationFailedEvent] is the recogniser giving up.
class DictationFailedEvent extends SpeechEvent {
  const DictationFailedEvent({required this.message});

  final String message;

  @override
  List<Object> get props => [message];
}

/// [DictationStatusEvent] is the plugin reporting that it stopped on its own —
/// the pause timeout elapsed, or the OS took the mic. Without it the waveform
/// keeps animating over a closed mic.
class DictationStatusEvent extends SpeechEvent {
  const DictationStatusEvent({required this.isListening});

  final bool isListening;

  @override
  List<Object> get props => [isListening];
}
