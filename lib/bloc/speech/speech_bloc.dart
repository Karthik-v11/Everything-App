import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/data/repositories/speech_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'speech_event.dart';
part 'speech_state.dart';

/// [SpeechBloc] owns one dictation session at a time (Requirement 16).
///
/// Every plugin callback is turned into an event and added back to this bloc,
/// which is what serialises the mic's three asynchronous callbacks through one
/// handler queue instead of racing to `emit` from the platform channel's thread.
class SpeechBloc extends Bloc<SpeechEvent, SpeechState> {
  SpeechBloc({required this.repository}) : super(const SpeechState()) {
    on<StartDictationEvent>(_onStartDictationEvent);
    on<StopDictationEvent>(_onStopDictationEvent);
    on<CancelDictationEvent>(_onCancelDictationEvent);
    on<DictationHeardEvent>(_onDictationHeardEvent);
    on<DictationLevelEvent>(_onDictationLevelEvent);
    on<DictationFailedEvent>(_onDictationFailedEvent);
    on<DictationStatusEvent>(_onDictationStatusEvent);
  }

  final SpeechRepository repository;

  /// Brackets the raw amplitude. Android and iOS report different RMS ranges, so
  /// both are clamped into this band rather than trusted.
  static const double _kMinLevelDb = -2;
  static const double _kMaxLevelDb = 10;

  FutureOr<void> _onStartDictationEvent(
    StartDictationEvent event,
    Emitter<SpeechState> emit,
  ) async {
    emit(state.copyWith(error: '', transcript: '', level: 0));

    try {
      final isAvailable = await repository.initialize(
        onStatus: (status) {
          if (isClosed) return;
          // 'done' and 'notListening' are the plugin's two ways of saying the mic
          // closed without anyone asking it to.
          if (status == 'done' || status == 'notListening') {
            add(const DictationStatusEvent(isListening: false));
          }
        },
        onError: (message) {
          if (isClosed) return;
          add(DictationFailedEvent(message: message));
        },
      );

      if (!isAvailable) {
        emit(
          state.copyWith(
            isUnavailable: true,
            isListening: false,
            error: 'Dictation needs microphone access. Turn it on for '
                'Everything in your phone’s settings.',
          ),
        );
        return;
      }

      await repository.listen(
        onResult: (text, isFinal) {
          if (isClosed) return;
          add(DictationHeardEvent(text: text, isFinal: isFinal));
        },
        onLevel: (level) {
          if (isClosed) return;
          add(DictationLevelEvent(level: level));
        },
      );

      emit(state.copyWith(isListening: true, isUnavailable: false));
    } catch (error) {
      emit(
        state.copyWith(
          isListening: false,
          error: 'The microphone could not be started.',
        ),
      );
    }
  }

  FutureOr<void> _onStopDictationEvent(
    StopDictationEvent event,
    Emitter<SpeechState> emit,
  ) async {
    // Emitted before the await: the mic button must stop pulsing on the tap, not
    // once the platform has finished tearing the session down.
    emit(state.copyWith(isListening: false, level: 0));

    try {
      await repository.stop();
    } catch (error) {
      // A stop that throws has still left the UI correct: recorded, not shown.
      addError(error, StackTrace.current);
    }
  }

  FutureOr<void> _onCancelDictationEvent(
    CancelDictationEvent event,
    Emitter<SpeechState> emit,
  ) async {
    emit(state.copyWith(isListening: false, level: 0, transcript: ''));

    try {
      await repository.cancel();
    } catch (error) {
      addError(error, StackTrace.current);
    }
  }

  FutureOr<void> _onDictationHeardEvent(
    DictationHeardEvent event,
    Emitter<SpeechState> emit,
  ) {
    emit(
      state.copyWith(
        transcript: event.text,
        // A final result means the recogniser has closed the session itself.
        isListening: event.isFinal ? false : state.isListening,
        level: event.isFinal ? 0 : state.level,
      ),
    );
  }

  FutureOr<void> _onDictationLevelEvent(
    DictationLevelEvent event,
    Emitter<SpeechState> emit,
  ) {
    // A level arriving after the mic closed would restart the waveform over a
    // dead session; the platform sends a few on the way down.
    if (!state.isListening) return null;

    final normalised =
        ((event.level - _kMinLevelDb) / (_kMaxLevelDb - _kMinLevelDb))
            .clamp(0.0, 1.0);

    emit(state.copyWith(level: normalised));
  }

  FutureOr<void> _onDictationFailedEvent(
    DictationFailedEvent event,
    Emitter<SpeechState> emit,
  ) {
    // `error_no_match` and `error_speech_timeout` mean the recogniser heard
    // nothing usable — silence, not a failure worth showing.
    final isSilence = event.message == 'error_no_match' ||
        event.message == 'error_speech_timeout';

    emit(
      state.copyWith(
        isListening: false,
        level: 0,
        error: isSilence ? '' : 'Dictation stopped. Try again.',
      ),
    );
  }

  FutureOr<void> _onDictationStatusEvent(
    DictationStatusEvent event,
    Emitter<SpeechState> emit,
  ) {
    if (event.isListening || !state.isListening) return null;
    emit(state.copyWith(isListening: false, level: 0));
  }

  @override
  Future<void> close() async {
    // The plugin holds the platform session, so the mic outlives this bloc
    // unless it is cancelled here.
    await repository.cancel().catchError((_) {});
    return super.close();
  }
}
