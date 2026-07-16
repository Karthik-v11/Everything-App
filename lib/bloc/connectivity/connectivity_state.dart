part of 'connectivity_bloc.dart';

/// [ConnectivityState] holds the device's current reachability.
///
/// [isOnline] defaults to true: the app assumes connectivity until the platform
/// tells it otherwise, so a slow first probe never makes the Dashboard flash an
/// "offline" banner it will immediately retract.
class ConnectivityState extends Equatable {
  const ConnectivityState({this.isOnline = true});

  final bool isOnline;

  bool get isOffline => !isOnline;

  ConnectivityState copyWith({bool? isOnline}) =>
      ConnectivityState(isOnline: isOnline ?? this.isOnline);

  @override
  List<Object> get props => [isOnline];
}
