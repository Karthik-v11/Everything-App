import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// [NavigationObserver] logs route pushes, pops and replacements.
///
/// Registered on the GoRouter in `app_router.dart`.
///
/// DO NOT MODIFY.
class NavigationObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _log('push', route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _log('pop', route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _log('replace', newRoute, oldRoute);
  }

  void _log(String action, Route<dynamic>? route, Route<dynamic>? previous) {
    if (!kDebugMode) return;
    final to = route?.settings.name ?? route?.settings.arguments ?? '—';
    final from = previous?.settings.name ?? '—';
    developer.log('$from → $to', name: 'Router ▸ $action');
  }
}
