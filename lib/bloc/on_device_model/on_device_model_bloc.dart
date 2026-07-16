import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/data/repositories/gemma_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'on_device_model_event.dart';
part 'on_device_model_state.dart';

/// [OnDeviceModelBloc] owns the on-device LLM's lifecycle (Phase 13).
///
/// ## This bloc *is* the switch
///
/// There is no "use the model" flag anywhere in the AI layer.
/// [ModelBackedAiRepository] asks one question — is a model loaded right now? —
/// and this bloc is the only thing that loads or unloads one. So switching the
/// feature off in Settings does not set a boolean the assistant has to remember
/// to check; it **unloads the model**, and the assistant falls back to the
/// rule-based engine because there is genuinely nothing to fall forward to. The
/// setting's effect is structural rather than a condition that can be forgotten
/// at one call site, which is the same shape as Phase 12's widget switch erasing
/// its container rather than merely ceasing to publish.
///
/// [SettingsBloc] owns the user's choice and pushes it here with
/// [ConfigureOnDeviceModelEvent] — never a cross-bloc state read (CLAUDE.md
/// §4.4), the same rule the notification configuration and the widget switch
/// follow.
///
/// ## Style A, and hydrated for one field only
///
/// [OnDeviceModelState.isEnabled] is the user's setting and lives in
/// [SettingsBloc]; nothing here is persisted. `isInstalled` is re-read from disk
/// at launch rather than remembered, for the reason Phase 11 re-read its backup
/// list: the OS can reclaim a 584 MB file, and a remembered "installed" would be
/// a lie that surfaces as a failed load.
///
/// Events:
/// 1) [InitOnDeviceModelEvent] — read whether the model is on disk. Fired once.
/// 2) [ConfigureOnDeviceModelEvent] — the user's switch, pushed by [SettingsBloc].
/// 3) [DownloadOnDeviceModelEvent] — fetch the weights, reporting progress.
/// 4) [RemoveOnDeviceModelEvent] — unload and delete the weights.
class OnDeviceModelBloc extends Bloc<OnDeviceModelEvent, OnDeviceModelState> {
  OnDeviceModelBloc({required this.repository})
      : super(const OnDeviceModelState()) {
    on<InitOnDeviceModelEvent>(_onInitOnDeviceModelEvent);
    on<ConfigureOnDeviceModelEvent>(_onConfigureOnDeviceModelEvent);
    on<DownloadOnDeviceModelEvent>(_onDownloadOnDeviceModelEvent);
    on<DownloadProgressEvent>(_onDownloadProgressEvent);
    on<RemoveOnDeviceModelEvent>(_onRemoveOnDeviceModelEvent);
  }

  final GemmaRepository repository;

  FutureOr<void> _onInitOnDeviceModelEvent(
    InitOnDeviceModelEvent event,
    Emitter<OnDeviceModelState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: '', message: ''));

    final isInstalled = await repository.isInstalled();

    emit(
      state.copyWith(
        isLoading: false,
        isInstalled: isInstalled,
        isConfigured: repository.isConfigured,
        downloadSizeBytes: repository.downloadSizeBytes,
      ),
    );

    // A model already on disk and a switch already on is the returning user's
    // normal case, and loading is what makes the assistant model-backed. The
    // switch arrives by its own event, so this only covers a model installed in
    // an earlier session.
    if (isInstalled && state.isEnabled) await _load(emit);
  }

  /// [_onConfigureOnDeviceModelEvent] applies the user's switch by loading or
  /// unloading the model — which is the entire mechanism, see the class comment.
  FutureOr<void> _onConfigureOnDeviceModelEvent(
    ConfigureOnDeviceModelEvent event,
    Emitter<OnDeviceModelState> emit,
  ) async {
    emit(state.copyWith(isEnabled: event.isEnabled, error: '', message: ''));

    if (!event.isEnabled) {
      await repository.unload();
      emit(state.copyWith(isLoaded: false));
      return;
    }

    // Switching it on with no weights on disk is not an error — the Settings
    // section offers the download and says what it costs. Nothing to load yet.
    if (!state.isInstalled) return;

    await _load(emit);
  }

  FutureOr<void> _onDownloadOnDeviceModelEvent(
    DownloadOnDeviceModelEvent event,
    Emitter<OnDeviceModelState> emit,
  ) async {
    if (state.isDownloading) return;

    emit(
      state.copyWith(
        isDownloading: true,
        progress: 0,
        error: '',
        message: '',
      ),
    );

    // Progress arrives on the plugin's own callback, which is not this handler's
    // emitter — emitting from it directly would be an emit after the handler has
    // returned. It goes back through the bloc as an event instead, which is the
    // one legal way to move a callback into state.
    final response = await repository.download(
      onProgress: (percent) => add(DownloadProgressEvent(percent: percent)),
    );

    if (!response.success) {
      emit(
        state.copyWith(
          isDownloading: false,
          progress: 0,
          error: response.message,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        isDownloading: false,
        progress: 100,
        isInstalled: true,
        message: response.message,
      ),
    );

    if (state.isEnabled) await _load(emit);
  }

  FutureOr<void> _onDownloadProgressEvent(
    DownloadProgressEvent event,
    Emitter<OnDeviceModelState> emit,
  ) {
    // A tick arriving after the download finished or failed has nothing to
    // report — and would otherwise resurrect a progress bar the handler has
    // already torn down.
    if (state.isDownloading) emit(state.copyWith(progress: event.percent));
  }

  FutureOr<void> _onRemoveOnDeviceModelEvent(
    RemoveOnDeviceModelEvent event,
    Emitter<OnDeviceModelState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: '', message: ''));

    final response = await repository.remove();

    emit(
      response.success
          ? state.copyWith(
              isLoading: false,
              isInstalled: false,
              isLoaded: false,
              progress: 0,
              message: response.message,
            )
          : state.copyWith(isLoading: false, error: response.message),
    );
  }

  /// [_load] brings the model into memory.
  ///
  /// A failure here is reported but is not a broken app: the assistant is the
  /// rule-based engine until it succeeds, which is the app's shipped behaviour
  /// rather than a fault state.
  Future<void> _load(Emitter<OnDeviceModelState> emit) async {
    emit(state.copyWith(isLoading: true, error: ''));

    final response = await repository.load();

    emit(
      response.success
          ? state.copyWith(isLoading: false, isLoaded: true)
          : state.copyWith(
              isLoading: false,
              isLoaded: false,
              error: response.message,
            ),
    );
  }
}
