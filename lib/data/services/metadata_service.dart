import 'package:dio/dio.dart';
import 'package:everything_app/core/exceptions/dio_exception.dart';
import 'package:everything_app/core/interceptors/x_client_interceptor.dart';
import 'package:everything_app/data/models/bookmark.dart';
import 'package:everything_app/data/models/json_response.dart';

/// [MetadataService] fetches a page's real title and preview image
/// (Requirement 6.1).
///
/// It is the app's **third and last** networked service, and the only one whose
/// failure is uninteresting. A bookmark is saved from [UrlMetadata.read] — which
/// needs no network — before this is ever called, so what this adds is a nicer
/// title and a picture. Offline, the bookmark is already saved and already
/// correct; this simply never runs, and nothing on screen is waiting for it.
///
/// That is why it does not parse HTML properly. A real parser would be a new
/// dependency and a much larger surface for the sake of two `<meta>` tags, so this
/// reads the Open Graph tags with a regex over the head of the document and gives
/// up quietly on anything it does not recognise. Being wrong here costs a
/// placeholder title; being slow here costs the user's save.
class MetadataService {
  MetadataService({required this.dio}) {
    dio.options
      ..sendTimeout = _timeout
      ..receiveTimeout = _timeout
      ..connectTimeout = _timeout
      ..responseType = ResponseType.plain
      ..followRedirects = true
      // A page that answers with anything else is not one we can read a title out
      // of, and Dio should hand it back rather than throw.
      ..validateStatus = (status) => status != null && status < 500;

    dio.interceptors.add(XClientInterceptor());
  }

  final Dio dio;

  /// Short on purpose. This runs *after* the bookmark is already saved and on
  /// screen, so a slow page must not keep a request alive for ten seconds to
  /// improve a title the user has stopped looking at.
  static const Duration _timeout = Duration(seconds: 5);

  /// How much of the document to read. Open Graph tags live in `<head>`, and a
  /// megabyte of article body would be downloaded to find something in its first
  /// few kilobytes.
  static const int _maxBytes = 64 * 1024;

  /// [fetch] returns a [UrlMetadata] enriched with whatever the page actually says
  /// about itself, falling back to the derived values field by field.
  ///
  /// Field by field, not all-or-nothing: a page with an `og:image` and no `og:title`
  /// should still contribute its image.
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
          // The derived thumbnail wins where there is one: YouTube's `og:image` is
          // the same picture this already knows how to name without asking, and
          // asking is what we are trying to avoid.
          thumbnailUrl: derived.thumbnailUrl ?? _absolute(image, url),
        ),
      );
    } on DioException catch (error) {
      // Every network failure lands here, and every one of them is fine: the
      // bookmark already exists with what could be derived from its URL, and the
      // user is told nothing because nothing has gone wrong for them.
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

  /// [_meta] reads one Open Graph tag. The attribute order is not fixed in the
  /// wild — `content` before `property` is common — so both orders are matched.
  static String? _meta(String html, String property) {
    final patterns = [
      RegExp(
        '''<meta[^>]+(?:property|name)=["']$property["'][^>]*content=["']([^"']*)["']''',
        caseSensitive: false,
      ),
      RegExp(
        '''<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']$property["']''',
        caseSensitive: false,
      ),
    ];

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
  /// the page it came from. Plenty of sites serve `/images/card.png`, which is not
  /// a URL any image widget can load.
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
