part of 'settings_bloc.dart';

/// [SettingsEvent] is the base class for every settings event.
abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

/// [InitSettingsEvent] sets up the notification plugin, reads the current OS
/// permission and arms the schedule. Fired once, at launch.
class InitSettingsEvent extends SettingsEvent {
  const InitSettingsEvent();
}

/// [RequestNotificationPermissionEvent] asks the OS for permission to post
/// notifications, and on Android 14+ for the exact-alarm permission.
class RequestNotificationPermissionEvent extends SettingsEvent {
  const RequestNotificationPermissionEvent();
}

/// [ToggleNotificationsEvent] is the master switch. Off means nothing is
/// scheduled, whatever the individual kinds say.
class ToggleNotificationsEvent extends SettingsEvent {
  const ToggleNotificationsEvent({required this.isEnabled});

  final bool isEnabled;

  @override
  List<Object?> get props => [isEnabled];
}

/// [ToggleNotificationKindEvent] switches one [NotificationKind] on or off.
class ToggleNotificationKindEvent extends SettingsEvent {
  const ToggleNotificationKindEvent({
    required this.kind,
    required this.isEnabled,
  });

  final NotificationKind kind;
  final bool isEnabled;

  @override
  List<Object?> get props => [kind, isEnabled];
}

/// [ChangeSummaryTimeEvent] moves a digest to a different time of day.
///
/// [minutes] is minutes past midnight. [kind] must be one of the two summaries.
class ChangeSummaryTimeEvent extends SettingsEvent {
  const ChangeSummaryTimeEvent({required this.kind, required this.minutes});

  final NotificationKind kind;
  final int minutes;

  @override
  List<Object?> get props => [kind, minutes];
}

/// [ChangeUserNameEvent] sets the name the Dashboard greets (Requirement 3.1).
///
/// [name] is empty to go back to an unnamed greeting.
class ChangeUserNameEvent extends SettingsEvent {
  const ChangeUserNameEvent({required this.name});

  final String name;

  @override
  List<Object?> get props => [name];
}

/// [ChangeSummaryWeekdayEvent] moves the weekly digest to a different day.
///
/// [weekday] is `DateTime.monday` … `DateTime.sunday`.
class ChangeSummaryWeekdayEvent extends SettingsEvent {
  const ChangeSummaryWeekdayEvent({required this.weekday});

  final int weekday;

  @override
  List<Object?> get props => [weekday];
}

/// [ToggleHomeWidgetsEvent] switches the home screen widgets on or off
/// (Requirement 13).
///
/// Off empties the shared container rather than merely stopping the refresh —
/// the switch exists so the data can leave the one store in this app that is
/// readable without the database key.
class ToggleHomeWidgetsEvent extends SettingsEvent {
  const ToggleHomeWidgetsEvent({required this.isEnabled});

  final bool isEnabled;

  @override
  List<Object?> get props => [isEnabled];
}

/// [ToggleOnDeviceAiEvent] switches the on-device model on or off (Phase 13).
///
/// Off unloads the model rather than setting a flag the assistant consults, so
/// the assistant falls back to the rule-based engine because there is genuinely
/// nothing loaded — see [OnDeviceModelBloc]. It never downloads: switching on
/// with no weights on disk offers the download and states its cost.
class ToggleOnDeviceAiEvent extends SettingsEvent {
  const ToggleOnDeviceAiEvent({required this.isEnabled});

  final bool isEnabled;

  @override
  List<Object?> get props => [isEnabled];
}

/// [ChangeAiConfidenceEvent] moves the score the assistant acts at
/// (Requirement 25.3).
///
/// [confidence] is clamped to `kMinAiConfidence`…`kMaxAiConfidence` by the
/// handler; the ends of that range are an assistant that acts on everything or
/// asks about everything.
class ChangeAiConfidenceEvent extends SettingsEvent {
  const ChangeAiConfidenceEvent({required this.confidence});

  final double confidence;

  @override
  List<Object?> get props => [confidence];
}
