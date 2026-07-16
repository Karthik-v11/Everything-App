import 'package:dio/dio.dart';
import 'package:everything_app/core/exceptions/dio_exception.dart';
import 'package:everything_app/core/interceptors/x_client_interceptor.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// [GeminiService] is the assistant's cloud generation boundary.
///
/// It replaces `GemmaService` as the engine behind the assistant's two prose
/// paths. The reason is the device, not the model: a 1B model at q4 needs
/// roughly 1.5 GB resident, and the target phone has ~1 GB free, so the weights
/// downloaded but never loaded. A cloud call costs no device memory at all.
///
/// ## What this costs, and what it costs the user
///
/// `gemini-3.1-flash-lite` is free-tier eligible, and the prompts are small —
/// [AiPrompt.answer] caps grounding at 8 result titles — so personal use fits
/// inside the free quota. The real price is privacy: the titles of tasks and
/// transactions leave the device. The settings copy says so; see
/// [ModelBackedAiRepository] for why the vault never reaches a prompt.
///
/// ## Every failure is a degradation
///
/// Same contract `GemmaService` held: no key, no network, a 429 over quota, or
/// a malformed body all return a [JsonResponse.failure], and the caller falls
/// back to the rule-based engine. None of them are errors the user must act on.
class GeminiService {
  GeminiService({required this.dio}) {
    dio.options
      ..baseUrl = _baseUrl
      ..connectTimeout = const Duration(seconds: 10)
      ..sendTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 10)
      ..responseType = ResponseType.json
      ..headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
    dio.interceptors.add(XClientInterceptor());
  }

  final Dio dio;

  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  /// The model, and why this one rather than a Pro tier.
  ///
  /// Both prompts are easy: one reads back rows the app's own FTS index already
  /// returned, the other shortens a single document. Neither needs frontier
  /// reasoning, and the lite tier is free-tier eligible and the fastest to
  /// first token — which matters on a path the user waits on.
  static const String model = 'gemini-3.1-flash-lite';

  /// [apiKey] gates every call, and is read here rather than added to
  /// `core/utils/constants.dart` alongside the weather and news keys because
  /// that file is protected (CLAUDE.md §0). Moving it there is a one-line
  /// developer change and the natural home for it.
  static String get apiKey => dotenv.get('GEMINI_API_KEY', fallback: '');

  /// [isConfigured] is whether a key exists — not whether the network works.
  /// Reachability is only knowable by calling, which is why [generate] degrades
  /// rather than throws.
  bool get isConfigured => apiKey.isNotEmpty;

  /// [generate] returns the model's prose, or a failure the caller reads as
  /// "use the rule-based engine".
  Future<JsonResponse> generate(
    String prompt, {
    String? systemInstruction,
    int maxOutputTokens = 256,
  }) async {
    final key = apiKey;
    if (key.isEmpty) {
      return JsonResponse.failure(
        statusCode: 401,
        message: 'No Gemini key. Add GEMINI_API_KEY to .env.',
      );
    }

    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/models/$model:generateContent',
        // The key rides a header rather than the documented `?key=` query
        // parameter: a URL is logged by proxies and crash reports, a header is
        // not.
        options: Options(headers: <String, String>{'x-goog-api-key': key}),
        data: <String, dynamic>{
          'contents': <dynamic>[
            <String, dynamic>{
              'parts': <dynamic>[
                <String, String>{'text': prompt},
              ],
            },
          ],
          if (systemInstruction != null)
            'systemInstruction': <String, dynamic>{
              'parts': <dynamic>[
                <String, String>{'text': systemInstruction},
              ],
            },
          'generationConfig': <String, dynamic>{
            'maxOutputTokens': maxOutputTokens,
          },
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final text = _textFrom(response.data!);
        if (text == null || text.trim().isEmpty) {
          // A 200 with no text is a real outcome, not a parse bug: the model
          // can stop on a safety block or hit maxOutputTokens mid-thought and
          // return a candidate with no parts.
          return JsonResponse.failure(
            statusCode: 200,
            message: 'Error: the model returned no text.',
          );
        }
        return JsonResponse.success(
          message: 'Generated successfully.',
          data: text.trim(),
        );
      }

      return JsonResponse.failure(
        statusCode: response.statusCode ?? 500,
        message: response.data?['error']?['message']?.toString() ??
            'Error: the model could not answer.',
      );
    } on DioException catch (error) {
      return JsonResponse.failure(
        statusCode: error.response?.statusCode ?? 500,
        message: DioExceptionOf.exceptionFromDioError(error).errorMessage,
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: the model could not answer.',
      );
    }
  }

  /// [_textFrom] digs the prose out of `candidates[0].content.parts[0].text`,
  /// null-safe at every hop because a blocked or truncated response drops the
  /// levels below it rather than sending an empty string.
  String? _textFrom(Map<String, dynamic> json) {
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return null;
    final content = (candidates.first as Map?)?['content'] as Map?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) return null;
    return (parts.first as Map?)?['text']?.toString();
  }
}
