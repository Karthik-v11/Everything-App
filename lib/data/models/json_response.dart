/// [JsonResponse] is the universal result wrapper returned by **every** service
/// method — including the Drift-backed local ones.
///
/// The app is offline-first, so most "responses" come from SQLite rather than
/// HTTP. Keeping one wrapper for both means a bloc's success/failure branching
/// is identical whether the data came from the local database or the network,
/// and a service can be swapped from one to the other without touching the bloc.
///
/// [success] is true for 2xx-equivalent outcomes.
/// [statusCode] is the HTTP code for remote calls, or a synthetic one for local
/// calls (200 read, 201 write, 500 failure).
/// [message] is always human-readable and safe to surface in a SnackBar.
/// [data] is the parsed model, or list of models, or null.
///
/// DO NOT MODIFY.
class JsonResponse {
  const JsonResponse({
    required this.success,
    required this.statusCode,
    required this.message,
    this.data,
  });

  final bool success;
  final int statusCode;
  final String message;
  final Object? data;

  /// [JsonResponse.success] is a successful read or update.
  factory JsonResponse.success({required String message, Object? data}) =>
      JsonResponse(
        success: true,
        statusCode: 200,
        message: message,
        data: data,
      );

  /// [JsonResponse.created] is a successful insert.
  factory JsonResponse.created({required String message, Object? data}) =>
      JsonResponse(
        success: true,
        statusCode: 201,
        message: message,
        data: data,
      );

  /// [JsonResponse.failure] is any unsuccessful outcome. [message] is required —
  /// a failure without an explanation is never acceptable.
  factory JsonResponse.failure({
    required int statusCode,
    required String message,
  }) =>
      JsonResponse(
        success: false,
        statusCode: statusCode,
        message: message,
      );

  @override
  String toString() =>
      'JsonResponse(success: $success, statusCode: $statusCode, '
      'message: $message)';
}
