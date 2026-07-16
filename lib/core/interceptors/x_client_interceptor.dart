import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// [XClientInterceptor] stamps every outbound request with client metadata.
///
/// Added to every service (CLAUDE.md §5). There is no [AuthInterceptor] in this
/// app: it is offline-first with no backend of its own, and its only two remote
/// services (Weather, News) authenticate with a query-string API key rather than
/// a bearer token.
///
/// DO NOT MODIFY.
class XClientInterceptor extends Interceptor {
  static String? _cachedVersion;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    _cachedVersion ??= await _appVersion();

    options.headers.addAll(<String, String>{
      'x-client-platform': Platform.operatingSystem,
      'x-client-version': _cachedVersion ?? 'unknown',
      'x-client-app': 'everything-app',
    });

    handler.next(options);
  }

  Future<String?> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } on Exception {
      return null;
    }
  }
}
