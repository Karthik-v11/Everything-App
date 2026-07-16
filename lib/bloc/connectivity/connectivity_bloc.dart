import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'connectivity_event.dart';
part 'connectivity_state.dart';

/// [ConnectivityBloc] tracks whether the device is online.
///
/// Connectivity never gates a read or a write: every module works fully offline
/// (Requirement 21.2). It is read only by the two online-only features (Weather
/// and News), to choose between a fetch and their cached payload, and by the Sync
/// service to know when to run (Requirement 21.4).
///
/// Style A: a single persistent state that many listeners read.
///
/// Events:
/// 1) [WatchConnectivityEvent] — subscribes to the platform connectivity stream.
///    Dispatched once at startup with `lazy: false`.
class ConnectivityBloc extends Bloc<ConnectivityEvent, ConnectivityState> {
  ConnectivityBloc({required this.connectivity})
      : super(const ConnectivityState()) {
    on<WatchConnectivityEvent>(_onWatchConnectivityEvent);
  }

  final Connectivity connectivity;

  FutureOr<void> _onWatchConnectivityEvent(
    WatchConnectivityEvent event,
    Emitter<ConnectivityState> emit,
  ) async {
    try {
      emit(state.copyWith(isOnline: _isOnline(await connectivity.checkConnectivity())));

      await emit.forEach<List<ConnectivityResult>>(
        connectivity.onConnectivityChanged,
        onData: (results) => state.copyWith(isOnline: _isOnline(results)),
      );
    } on Exception {
      // A failed probe assumes online, leaving the individual request to fail with
      // its own error rather than blocking the app.
      emit(state.copyWith(isOnline: true));
    }
  }

  /// [_isOnline] treats any non-`none` transport as online. `connectivity_plus`
  /// reports link-layer reachability, not internet access, so a captive portal
  /// reads as online; the Dio call then fails and the feature falls back to cache.
  bool _isOnline(List<ConnectivityResult> results) =>
      results.isNotEmpty &&
      results.any((result) => result != ConnectivityResult.none);
}
