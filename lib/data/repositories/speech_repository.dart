import 'package:everything_app/data/services/speech_service.dart';

/// [SpeechRepository] is dictation, behind an interface the bloc can be tested
/// against without a microphone.
abstract class SpeechRepository {
  /// [initialize] asks for the mic and the recogniser, and reports whether
  /// dictation can run at all. Calling it is what prompts for permission.
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String error) onError,
  });

  /// [listen] starts a session. [onResult] fires repeatedly with the text so far,
  /// with `isFinal` true on the last. [onLevel] is the mic's live amplitude.
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required void Function(double level) onLevel,
  });

  /// [stop] ends the session, keeping what was heard.
  Future<void> stop();

  /// [cancel] ends the session, discarding it.
  Future<void> cancel();
}

class SpeechRepositoryImpl implements SpeechRepository {
  const SpeechRepositoryImpl({required this.speechService});

  final SpeechService speechService;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String error) onError,
  }) =>
      speechService.initialize(onStatus: onStatus, onError: onError);

  @override
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required void Function(double level) onLevel,
  }) =>
      speechService.listen(onResult: onResult, onLevel: onLevel);

  @override
  Future<void> stop() => speechService.stop();

  @override
  Future<void> cancel() => speechService.cancel();
}
