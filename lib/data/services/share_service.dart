import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/shared_item.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// [ShareService] is the boundary between `receive_sharing_intent` and the app
/// (Requirement 12.1).
///
/// It maps the plugin's `SharedMediaFile` into the app's own [SharedItem], so
/// nothing above this layer imports the plugin and the chooser sheet is testable
/// with no platform channel at all.
///
/// **Two APIs, not one, and both are required.** The plugin reports a share that
/// *launched* the app ([initial]) separately from shares that arrive while it is
/// already running ([stream]). They are different code paths in the plugin and in
/// the OS, and handling only the first is the classic bug here: sharing into a
/// cold app works, the user shares a second link ten seconds later, and nothing
/// happens at all.
class ShareService {
  ShareService({required this.plugin});

  final ReceiveSharingIntent plugin;

  /// [initial] is the share that launched the app, if the app was launched by
  /// one.
  ///
  /// Returns success with an empty list on a normal launch — no share is the
  /// overwhelmingly common case, not a failure.
  Future<JsonResponse> initial() async {
    try {
      final media = await plugin.getInitialMedia();
      return JsonResponse.success(
        message: 'Loaded successfully.',
        data: _map(media),
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not read the shared content.',
      );
    }
  }

  /// [stream] is every share that arrives while the app is already running.
  Stream<List<SharedItem>> stream() => plugin.getMediaStream().map(_map);

  /// [reset] tells the plugin the share has been dealt with.
  ///
  /// Without it the same share is replayed by `getInitialMedia` on the next cold
  /// launch, so a user who shared a link on Monday is offered it again on
  /// Tuesday.
  Future<void> reset() async => plugin.reset();

  /// [_map] converts the plugin's types into the app's.
  ///
  /// `SharedMediaFile.path` carries the *text* for text and URL shares, not a
  /// path — a plugin quirk, and the reason this mapping is a named boundary
  /// rather than a `.map()` at the call site.
  static List<SharedItem> _map(List<SharedMediaFile> media) => [
        for (final file in media) _mapOne(file),
      ];

  static SharedItem _mapOne(SharedMediaFile file) => switch (file.type) {
        // Both arrive as a string in `path`. Which of the two it *is* is decided
        // by looking at it, because Android sends a URL shared from a browser as
        // `text/plain` — see [SharedItem.fromText].
        SharedMediaType.text || SharedMediaType.url => SharedItem.fromText(
            file.path,
          ),
        SharedMediaType.image ||
        SharedMediaType.video ||
        SharedMediaType.file =>
          SharedItem(
            kind: SharedKind.file,
            value: file.path,
            fileName: _nameOf(file.path),
            mimeType: file.mimeType,
          ),
      };

  static String _nameOf(String path) {
    final separator = path.lastIndexOf(RegExp(r'[/\\]'));
    final name = separator < 0 ? path : path.substring(separator + 1);
    return name.isEmpty ? 'File' : name;
  }
}
