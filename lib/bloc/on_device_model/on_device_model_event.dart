part of 'on_device_model_bloc.dart';

/// [OnDeviceModelEvent] is the base class for every on-device model event.
abstract class OnDeviceModelEvent extends Equatable {
  const OnDeviceModelEvent();

  @override
  List<Object?> get props => [];
}

/// [InitOnDeviceModelEvent] reads whether the weights are already on disk, and
/// loads them if the feature is on. Fired once, at launch.
class InitOnDeviceModelEvent extends OnDeviceModelEvent {
  const InitOnDeviceModelEvent();
}

/// [ConfigureOnDeviceModelEvent] is the user's switch, pushed by [SettingsBloc]
/// (CLAUDE.md §4.4 — never a cross-bloc state read).
///
/// It does not set a flag the assistant consults; it loads or unloads the model,
/// which is the only thing [ModelBackedAiRepository] looks at.
class ConfigureOnDeviceModelEvent extends OnDeviceModelEvent {
  const ConfigureOnDeviceModelEvent({required this.isEnabled});

  final bool isEnabled;

  @override
  List<Object?> get props => [isEnabled];
}

/// [DownloadOnDeviceModelEvent] fetches the weights.
class DownloadOnDeviceModelEvent extends OnDeviceModelEvent {
  const DownloadOnDeviceModelEvent();
}

/// [DownloadProgressEvent] carries one progress tick from the plugin's callback
/// back into the bloc.
///
/// It exists because the callback fires outside the download handler's emitter,
/// and emitting from a callback after its handler has returned is an error.
/// Dispatched by [DownloadOnDeviceModelEvent]'s handler, never from outside.
class DownloadProgressEvent extends OnDeviceModelEvent {
  const DownloadProgressEvent({required this.percent});

  final int percent;

  @override
  List<Object?> get props => [percent];
}

/// [RemoveOnDeviceModelEvent] unloads the model and deletes the weights.
class RemoveOnDeviceModelEvent extends OnDeviceModelEvent {
  const RemoveOnDeviceModelEvent();
}
