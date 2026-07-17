import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/shared_item.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// [ShareService] is the boundary between `receive_sharing_intent` and the app
/// (Requirement 12.1).
///
/// It maps the plugin's `SharedMediaFile` into the app's own [SharedItem], so
/// nothing above this layer imports the plugin.
///
/// **Both APIs are required.** A share that launched the app ([initial]) and one
/// arriving while it runs ([stream]) are different code paths in the plugin and
/// the OS; handling only the first makes a cold-launch share work and every
/// subsequent one do nothing.
class ShareService {
  ShareService({required this.plugin});

  final ReceiveSharingIntent plugin;

  /// [initial] is the share that launched the app, if one did. A normal launch
  /// returns success with an empty list, not a failure.
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

  /// [reset] tells the plugin the share has been dealt with. Without it,
  /// `getInitialMedia` replays the same share on the next cold launch.
  Future<void> reset() async => plugin.reset();

  /// [_map] converts the plugin's types into the app's.
  ///
  /// Plugin quirk: `SharedMediaFile.path` carries the *text* for text and URL
  /// shares, not a path.
  static List<SharedItem> _map(List<SharedMediaFile> media) => [
        for (final file in media) _mapOne(file),
      ];

  static SharedItem _mapOne(SharedMediaFile file) => switch (file.type) {
        // Both arrive as a string in `path`, and which one it is has to be
        // decided by inspection: Android sends a URL shared from a browser as
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
