import 'package:dio/dio.dart';
import 'package:everything_app/core/exceptions/dio_exception.dart';
import 'package:everything_app/core/interceptors/x_client_interceptor.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/data/models/article.dart';
import 'package:everything_app/data/models/json_response.dart';

/// How many headlines a category keeps. Every one is hydrated on every fetch.
const int kNewsPageSize = 20;

/// [NewsService] reads the News_Service (Requirement 3.9).
class NewsService {
  NewsService({required this.dio}) {
    dio.options
      ..baseUrl = kNewsURL
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

  /// [headlines] is one tab of the news section.
  Future<JsonResponse> headlines({required NewsCategory category}) async {
    if (kNewsAPIKey.isEmpty) {
      return JsonResponse.failure(
        statusCode: 401,
        message: 'Error: add NEWS_API_KEY to .env to see the news.',
      );
    }

    try {
      // The path is the category's, not a constant: the India tab is a
      // `/everything` search because NewsAPI has no live Indian source to name
      // on `/top-headlines`. See [NewsCategory].
      final response = await dio.get<Map<String, dynamic>>(
        category.path,
        queryParameters: <String, String>{
          ...category.parameters,
          'apiKey': kNewsAPIKey,
          'pageSize': '$kNewsPageSize',
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final articles = response.data!['articles'] as List?;

        return JsonResponse.success(
          message: 'Loaded successfully.',
          data: [
            for (final article in articles ?? const [])
              if (article is Map<String, dynamic>)
                if (Article.fromJson(article) case final Article parsed)
                  // A pulled article arrives with every field set to `[Removed]`
                  // and an unopenable url.
                  if (parsed.isRenderable) parsed,
          ],
        );
      }

      return JsonResponse.failure(
        statusCode: response.statusCode ?? 500,
        message: response.data?['message']?.toString() ??
            'Error: could not load the news.',
      );
    } on DioException catch (error) {
      return JsonResponse.failure(
        statusCode: error.response?.statusCode ?? 500,
        message: DioExceptionOf.exceptionFromDioError(error).errorMessage,
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not load the news.',
      );
    }
  }
}
