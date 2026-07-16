import 'package:dio/dio.dart';

/// [DioExceptionOf] maps a raw [DioException] onto a human-readable message.
///
/// Services call this in their `on DioException` branch and pass the result into
/// `JsonResponse.failure(...)` — a [DioException] must never escape the service
/// layer (CLAUDE.md §12).
///
/// DO NOT MODIFY.
class DioExceptionOf implements Exception {
  DioExceptionOf({required this.errorMessage});

  final String errorMessage;

  /// [exceptionFromDioError] classifies [error] and returns a message safe to
  /// show the user.
  factory DioExceptionOf.exceptionFromDioError(DioException error) {
    final message = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'The connection timed out. Please try again.',
      DioExceptionType.badCertificate =>
        'Could not establish a secure connection.',
      DioExceptionType.badResponse => _fromStatusCode(error),
      DioExceptionType.cancel => 'The request was cancelled.',
      DioExceptionType.connectionError =>
        'No internet connection. Showing saved data.',
      _ => 'Something went wrong. Please try again.',
    };
    return DioExceptionOf(errorMessage: message);
  }

  static String _fromStatusCode(DioException error) {
    final response = error.response;
    final serverMessage = response?.data is Map<String, dynamic>
        ? (response!.data as Map<String, dynamic>)['message']?.toString()
        : null;
    if (serverMessage != null && serverMessage.isNotEmpty) return serverMessage;

    return switch (response?.statusCode ?? 0) {
      400 => 'The request was invalid.',
      401 => 'Your session has expired. Please sign in again.',
      403 => 'You do not have permission to do that.',
      404 => 'We could not find what you were looking for.',
      429 => 'Too many requests. Please slow down.',
      >= 500 => 'The server is having trouble. Please try again later.',
      _ => 'Something went wrong. Please try again.',
    };
  }

  @override
  String toString() => errorMessage;
}
