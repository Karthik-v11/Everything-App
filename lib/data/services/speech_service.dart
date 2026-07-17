import 'package:everything_app/data/services/dictation_normaliser.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// [SpeechService] is the microphone boundary for dictation into the assistant.
///
/// No [JsonResponse]: there is no request or response body here, only a plugin
/// that calls back.
///
/// **Nothing is recorded** — the OS recogniser is handed the mic and gives back
/// text; no audio file is written. Whether that text is recognised on-device or
/// on Apple's or Google's servers is the OS's decision, which is why the sheet
/// says "your keyboard's dictation" rather than claiming it is local.
class SpeechService {
  SpeechService({SpeechToText? speech}) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  /// [_isInitialised] guards against a second `initialize`, which the plugin
  /// treats as an error rather than a no-op.
  bool _isInitialised = false;

  bool get isListening => _speech.isListening;

  /// [initialize] asks for the mic and the recogniser, returning whether both are
  /// available.
  ///
  /// This triggers the OS permission prompt, so it is called when the mic is
  /// first tapped rather than when the sheet opens.
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String error) onError,
  }) async {
    if (_isInitialised) return _speech.isAvailable;

    _isInitialised = await _speech.initialize(
      onStatus: onStatus,
      onError: (SpeechRecognitionError error) => onError(error.errorMsg),
      // Off: the plugin logs recognised text to the console, and the assistant
      // sees tasks, amounts and vault names.
      debugLogging: false,
    );
    return _isInitialised;
  }

  /// [listen] starts a dictation session, reporting partial text as it is heard.
  ///
  /// [onLevel] is a live amplitude read off the mic, so the waveform answers to
  /// the room rather than to a timer.
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required void Function(double level) onLevel,
  }) {
    return _speech.listen(
      // Normalised here rather than in the bloc: the recogniser's number
      // formatting is this boundary's quirk, and nothing above it should have to
      // know that "need 2 buy milk" was ever a possible transcript.
      onResult: (SpeechRecognitionResult result) => onResult(
        normaliseDictation(result.recognizedWords),
        result.finalResult,
      ),
      onSoundLevelChange: onLevel,
      listenOptions: SpeechListenOptions(
        // The field fills in as the user speaks, so a misheard word shows before
        // they stop talking.
        partialResults: true,
        // The assistant's input is one line, never a paragraph, so the recogniser
        // expects a phrase and finalises at its end.
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        // Bound the session: without these the mic sits open on a pocketed phone
        // until the OS times it out.
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  /// [stop] ends the session and keeps what was heard.
  Future<void> stop() => _speech.stop();

  /// [cancel] ends the session and discards it.
  Future<void> cancel() => _speech.cancel();
}
