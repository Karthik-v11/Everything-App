import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [AppBlocObserver] logs every bloc transition and error.
///
/// This is the app's only sanctioned logging path — `print()` is forbidden
/// (CLAUDE.md §12). Logging is compiled out in release via [kDebugMode].
///
/// DO NOT MODIFY.
class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    if (kDebugMode) {
      developer.log('$event', name: '${bloc.runtimeType} ▸ event');
    }
  }

  @override
  void onTransition(
    Bloc<dynamic, dynamic> bloc,
    Transition<dynamic, dynamic> transition,
  ) {
    super.onTransition(bloc, transition);
    if (kDebugMode) {
      developer.log(
        '${transition.currentState.runtimeType} → '
        '${transition.nextState.runtimeType}',
        name: '${bloc.runtimeType} ▸ state',
      );
    }
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    developer.log(
      'Unhandled bloc error',
      name: '${bloc.runtimeType} ▸ error',
      error: error,
      stackTrace: stackTrace,
    );
    super.onError(bloc, error, stackTrace);
  }
}
