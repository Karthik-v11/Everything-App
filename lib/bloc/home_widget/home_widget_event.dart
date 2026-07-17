part of 'home_widget_bloc.dart';

/// [HomeWidgetEvent] is the base class for every home widget event.
abstract class HomeWidgetEvent extends Equatable {
  const HomeWidgetEvent();

  @override
  List<Object?> get props => [];
}

/// [WatchHomeWidgetEvent] starts watching the task stream and, through it, the
/// finance stream. Fired once, at launch.
class WatchHomeWidgetEvent extends HomeWidgetEvent {
  const WatchHomeWidgetEvent();
}

/// [WatchHomeWidgetFinanceEvent] starts watching the transaction stream. Its own
/// event because a handler holds one emitter. Dispatched by
/// [WatchHomeWidgetEvent], never from outside.
class WatchHomeWidgetFinanceEvent extends HomeWidgetEvent {
  const WatchHomeWidgetFinanceEvent();
}

/// [WatchHomeWidgetTapsEvent] starts listening for widget taps. Its own event
/// because a handler holds one emitter. Dispatched by [WatchHomeWidgetEvent],
/// never from outside.
class WatchHomeWidgetTapsEvent extends HomeWidgetEvent {
  const WatchHomeWidgetTapsEvent();
}

/// [HomeWidgetTapHandled] clears the pending action once the app has navigated,
/// so a rebuild cannot reopen the same sheet.
class HomeWidgetTapHandled extends HomeWidgetEvent {
  const HomeWidgetTapHandled();
}

/// [SyncHomeWidgetEvent] rebuilds the payload and publishes it
/// (Requirement 13).
///
/// Queued by the streams and coalesced to one per burst. Never dispatched by a
/// feature.
class SyncHomeWidgetEvent extends HomeWidgetEvent {
  const SyncHomeWidgetEvent();
}

/// [ConfigureHomeWidgetEvent] is the user's switch, pushed by [SettingsBloc]
/// (Requirement 25.1).
///
/// Off means the shared container is emptied, not merely left unrefreshed.
class ConfigureHomeWidgetEvent extends HomeWidgetEvent {
  const ConfigureHomeWidgetEvent({required this.isEnabled});

  final bool isEnabled;

  @override
  List<Object?> get props => [isEnabled];
}
