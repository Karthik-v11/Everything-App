import 'package:dio/dio.dart';
import 'package:everything_app/core/exceptions/dio_exception.dart';
import 'package:everything_app/core/interceptors/x_client_interceptor.dart';
import 'package:everything_app/data/models/bookmark.dart';
import 'package:everything_app/data/models/json_response.dart';

/// [MetadataService] fetches a page's real title and preview image
/// (Requirement 6.1).
///
/// Its failure is uninteresting: the bookmark is already saved from
/// [UrlMetadata.read], which needs no network, before this is ever called.
///
/// It reads the Open Graph tags with a regex over the head of the document
/// rather than parsing HTML — a real parser is a large dependency for the sake
/// of two `<meta>` tags — and gives up quietly on anything unrecognised.
class MetadataService {
  MetadataService({required this.dio}) {
    dio.options
      ..sendTimeout = _timeout
      ..receiveTimeout = _timeout
      ..connectTimeout = _timeout
      ..responseType = ResponseType.plain
      ..followRedirects = true
      // Dio should hand back a non-2xx page rather than throw; there is just no
      // title to read out of it.
      ..validateStatus = (status) => status != null && status < 500;

    dio.interceptors.add(XClientInterceptor());
  }

  final Dio dio;

  /// Short on purpose: this runs after the bookmark is saved and on screen, so a
  /// slow page must not hold a request open to improve a title nobody awaits.
  static const Duration _timeout = Duration(seconds: 5);

  /// How much of the document to read. Open Graph tags live in `<head>`, so a
  /// megabyte of article body need not be downloaded to find them.
  static const int _maxBytes = 64 * 1024;

  /// [fetch] returns a [UrlMetadata] enriched with what the page says about
  /// itself, falling back to the derived values field by field — a page with an
  /// `og:image` and no `og:title` still contributes its image.
  Future<JsonResponse> fetch(String url) async {
    final derived = UrlMetadata.read(url);

    try {
      final response = await dio.get<String>(
        UrlMetadata.normalize(url),
        options: Options(
          headers: {
            // Some sites serve a stub to anything that does not look like a
            // browser, and the stub has no Open Graph tags in it.
            'Accept': 'text/html,application/xhtml+xml',
          },
        ),
        onReceiveProgress: (received, _) {
          if (received > _maxBytes) throw _TooLarge();
        },
      );

      final html = response.data;
      if (response.statusCode != 200 || html == null || html.isEmpty) {
        return JsonResponse.success(message: 'Nothing to add.', data: derived);
      }

      final head = html.length > _maxBytes ? html.substring(0, _maxBytes) : html;

      final title = _meta(head, 'og:title') ?? _title(head);
      final image = _meta(head, 'og:image');

      return JsonResponse.success(
        message: 'Loaded successfully.',
        data: UrlMetadata(
          title: title ?? derived.title,
          source: derived.source,
          // The derived thumbnail wins: YouTube's `og:image` is the same picture
          // this already knows how to name without a request.
          thumbnailUrl: derived.thumbnailUrl ?? _absolute(image, url),
        ),
      );
    } on DioException catch (error) {
      // Every network failure is fine and never shown: the bookmark already
      // exists with what was derived from its URL.
      return JsonResponse.failure(
        statusCode: 502,
        message: DioExceptionOf.exceptionFromDioError(error).errorMessage,
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not read that page.',
      );
    }
  }

  static final Map<String, List<RegExp>> _patternCache = {};

  /// [_meta] reads one Open Graph tag. The attribute order is not fixed in the
  /// wild — `content` before `property` is common — so both orders are matched.
  static String? _meta(String html, String property) {
    // Keyed by property because the pattern interpolates it; the set of
    // properties read is small and fixed.
    final patterns = _patternCache.putIfAbsent(
      property,
      () => [
        RegExp(
          '''<meta[^>]+(?:property|name)=["']$property["'][^>]*content=["']([^"']*)["']''',
          caseSensitive: false,
        ),
        RegExp(
          '''<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']$property["']''',
          caseSensitive: false,
        ),
      ],
    );

    for (final pattern in patterns) {
      final value = pattern.firstMatch(html)?.group(1)?.trim();
      if (value != null && value.isNotEmpty) return _unescape(value);
    }

    return null;
  }

  /// [_title] is the `<title>` element, the fallback when a page carries no Open
  /// Graph tags at all.
  static String? _title(String html) {
    final value = RegExp(
      r'<title[^>]*>([^<]*)</title>',
      caseSensitive: false,
    ).firstMatch(html)?.group(1)?.trim();

    return value == null || value.isEmpty ? null : _unescape(value);
  }

  /// [_absolute] resolves a protocol-relative or root-relative `og:image` against
  /// its page. Many sites serve `/images/card.png`, which no image widget loads.
  static String? _absolute(String? image, String pageUrl) {
    if (image == null || image.isEmpty) return null;
    if (image.startsWith('http')) return image;

    final page = Uri.tryParse(UrlMetadata.normalize(pageUrl));
    if (page == null) return null;

    return page.resolve(image).toString();
  }

  /// [_unescape] handles the five entities that actually turn up in a title.
  static String _unescape(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}

/// Thrown to abandon a response that is larger than [MetadataService._maxBytes].
class _TooLarge implements Exception {}
