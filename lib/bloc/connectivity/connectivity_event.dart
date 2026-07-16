part of 'connectivity_bloc.dart';

/// [ConnectivityEvent] is the base class for connectivity events.
abstract class ConnectivityEvent extends Equatable {
  const ConnectivityEvent();

  @override
  List<Object> get props => [];
}

/// [WatchConnectivityEvent] subscribes to the platform connectivity stream and
/// keeps [ConnectivityState.isOnline] current for the lifetime of the app.
class WatchConnectivityEvent extends ConnectivityEvent {
  const WatchConnectivityEvent();
}
