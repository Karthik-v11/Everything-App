import 'package:everything_app/data/models/shared_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// Content shared in from another app (Phase 12, Requirement 12).
///
/// [SharedItem.fromText] earns a test because it is the one piece of *judgement*
/// in the share flow: the OS does not tell us whether a shared string is a link or
/// a note — Android sends a URL from a browser as `text/plain` — so this decides,
/// and getting it wrong means the chooser silently omits Bookmark, the one
/// destination the user wanted.
///
/// Everything after it is composition through repositories that are already tested
/// (`ShareBloc` files a link through the same `BookmarksRepository.create` the
/// Library sheet uses), so there is nothing there this would not be re-testing.
void main() {
  group('SharedItem.fromText — link or note', () {
    test('a bare URL is a link', () {
      final item = SharedItem.fromText('https://flutter.dev/showcase');

      expect(item.kind, SharedKind.url);
      expect(item.value, 'https://flutter.dev/showcase');
      expect(item.destinations, contains(ShareDestination.bookmark));
    });

    test('a title and a link is a link — the link is the part worth keeping', () {
      // The common shape of an iOS/Android share from a news app or a browser.
      final item = SharedItem.fromText(
        'Why Flutter Scales\nhttps://example.com/blog/why-flutter-scales',
      );

      expect(item.kind, SharedKind.url);
      expect(item.value, 'https://example.com/blog/why-flutter-scales');
    });

    test('trailing sentence punctuation is not part of the link', () {
      final item = SharedItem.fromText('Look at (https://example.com/a).');

      expect(item.value, 'https://example.com/a');
    });

    test('prose is a note, and is never offered as a bookmark', () {
      final item = SharedItem.fromText(
        'Remember to call the plumber about the leak',
      );

      expect(item.kind, SharedKind.text);
      expect(item.destinations, isNot(contains(ShareDestination.bookmark)));
      expect(
        item.destinations,
        containsAll([ShareDestination.task, ShareDestination.document]),
      );
    });

    test('a scheme-less host stays a note', () {
      // Deliberate: matching bare hosts turns "meet me at 5 p.m." into a bookmark
      // for `m.`, and that class of false positive is worse than asking the user
      // to pick Bookmark for the rare bare-domain share.
      final item = SharedItem.fromText('github.com/flutter');

      expect(item.kind, SharedKind.text);
    });
  });

  group('ShareDestination — only what fits', () {
    test('a file goes to a project and nowhere else', () {
      const item = SharedItem(
        kind: SharedKind.file,
        value: '/tmp/report.pdf',
        fileName: 'report.pdf',
        mimeType: 'application/pdf',
      );

      // The other three destinations store text; there is nothing useful to put
      // in them from a PDF, and offering them would be offering a tap that fails.
      expect(item.destinations, [ShareDestination.projectFile]);
    });

    test('a link is never a project file', () {
      final item = SharedItem.fromText('https://example.com');

      expect(
        item.destinations,
        isNot(contains(ShareDestination.projectFile)),
      );
    });

    test('every kind has somewhere to go', () {
      // A share with an empty destination list is a chooser with no options — an
      // app that accepted the share and then had nothing to offer.
      for (final kind in SharedKind.values) {
        expect(
          ShareDestination.forKind(kind),
          isNotEmpty,
          reason: '$kind must have at least one destination',
        );
      }
    });
  });

  group('SharedItem.title — what the chooser shows before it commits', () {
    test('a link is named from its slug, with no network call', () {
      final item = SharedItem.fromText(
        'https://example.com/blog/why-flutter-scales',
      );

      // The same offline derivation the Library's own save uses, so a share on a
      // plane names the bookmark identically to one typed in.
      expect(item.title, 'Why Flutter Scales');
      expect(item.subtitle, 'example.com');
    });

    test('a long note is truncated for the preview but never in the value', () {
      final long = 'a' * 200;
      final item = SharedItem.fromText(long);

      expect(item.title.length, lessThan(long.length));
      expect(item.value, long, reason: 'the preview truncates, the share does not');
    });
  });
}
