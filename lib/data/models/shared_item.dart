import 'package:equatable/equatable.dart';
import 'package:everything_app/data/models/bookmark.dart';
import 'package:flutter/material.dart';

/// [SharedKind] is what another app handed us (Requirement 12.1).
///
/// The OS reports a type, but it is not trustworthy enough to route on alone:
/// Android's share sheet sends a bare URL as `text/plain` from most apps, so a
/// link arrives indistinguishable from a note until something looks at it. The
/// mapping in [SharedItem.fromText] is where that is settled.
enum SharedKind {
  url,
  text,
  file;

  String get label => switch (this) {
        SharedKind.url => 'Link',
        SharedKind.text => 'Text',
        SharedKind.file => 'File',
      };
}

/// [ShareDestination] is where a shared item can be filed (Requirement 12.2).
///
/// Not every destination fits every kind — a photo is not a bookmark, and a link
/// is not a project file — so the chooser offers only what [isAvailableFor]
/// allows rather than showing options that would fail on tap.
enum ShareDestination {
  bookmark,
  task,
  document,
  projectFile;

  String get label => switch (this) {
        ShareDestination.bookmark => 'Bookmark',
        ShareDestination.task => 'Task',
        ShareDestination.document => 'Document',
        ShareDestination.projectFile => 'Project file',
      };

  String get description => switch (this) {
        ShareDestination.bookmark => 'Save the link to your Library',
        ShareDestination.task => 'Make something to do out of it',
        ShareDestination.document => 'Start a note with it',
        ShareDestination.projectFile => 'Attach it to a project',
      };

  IconData get icon => switch (this) {
        ShareDestination.bookmark => Icons.bookmark_outline_rounded,
        ShareDestination.task => Icons.check_circle_outline_rounded,
        ShareDestination.document => Icons.description_outlined,
        ShareDestination.projectFile => Icons.folder_outlined,
      };

  /// [isAvailableFor] is whether this destination can accept [kind].
  ///
  /// A file goes to a project and nowhere else: the other three destinations
  /// store text, and there is nothing useful to put in them from a PDF. A link
  /// and a note can each become any of the three text destinations — a link's
  /// obvious home is a bookmark, but "read this later" is a task, and that is a
  /// choice only the user can make, which is the entire reason for the chooser.
  bool isAvailableFor(SharedKind kind) => switch (this) {
        ShareDestination.projectFile => kind == SharedKind.file,
        ShareDestination.bookmark => kind == SharedKind.url,
        ShareDestination.task ||
        ShareDestination.document =>
          kind == SharedKind.url || kind == SharedKind.text,
      };

  /// [forKind] is the chooser's option list, in the order it renders them — the
  /// most likely destination first, because the top option is the one a user
  /// filing a link taps without reading.
  static List<ShareDestination> forKind(SharedKind kind) => [
        for (final destination in ShareDestination.values)
          if (destination.isAvailableFor(kind)) destination,
      ];
}

/// [SharedItem] is one piece of content another app shared into this one
/// (Requirement 12).
///
/// It is the app's own type, not the plugin's: `ShareService` maps
/// `SharedMediaFile` into this at the boundary, so nothing above the service
/// layer imports `receive_sharing_intent` and the chooser sheet can be built and
/// tested with no plugin at all.
class SharedItem extends Equatable {
  const SharedItem({
    required this.kind,
    required this.value,
    this.fileName,
    this.mimeType,
  });

  final SharedKind kind;

  /// The URL, the shared text, or the absolute path of the shared file —
  /// whichever [kind] says.
  final String value;

  final String? fileName;
  final String? mimeType;

  /// [fromText] decides whether a shared string is a link or a note.
  ///
  /// This is the mapping the OS will not do for us. Android sends a URL shared
  /// from Chrome as `text/plain`, and iOS is inconsistent between apps, so a
  /// share that is obviously a link would otherwise arrive as text and be offered
  /// Document and Task but not Bookmark — the one destination the user wanted.
  ///
  /// Many apps share a link *with* a title ("Some Article\nhttps://…"), so the
  /// text is scanned for a URL rather than tested as one, and the URL wins: the
  /// link is the part that can be reopened.
  factory SharedItem.fromText(String raw) {
    final trimmed = raw.trim();
    final url = _firstUrlIn(trimmed);

    return url == null
        ? SharedItem(kind: SharedKind.text, value: trimmed)
        : SharedItem(kind: SharedKind.url, value: UrlMetadata.normalize(url));
  }

  /// [title] is what the chooser shows as the thing being filed.
  String get title => switch (kind) {
        SharedKind.url => UrlMetadata.read(value).title,
        SharedKind.file => fileName ?? 'File',
        SharedKind.text => value.length <= 80
            ? value
            : '${value.substring(0, 80).trimRight()}…',
      };

  /// [subtitle] is the second line — the host, the path, or nothing.
  String get subtitle => switch (kind) {
        SharedKind.url => UrlMetadata.hostOf(value) ?? value,
        SharedKind.file => mimeType ?? 'File',
        SharedKind.text => '${value.length} characters',
      };

  /// [destinations] is where this item may be filed.
  List<ShareDestination> get destinations => ShareDestination.forKind(kind);

  /// [_firstUrlIn] finds the first http(s) URL in [text], if there is one.
  ///
  /// Scheme-less hosts are deliberately not matched: "meet me at 5 p.m." should
  /// not become a bookmark to `m.`, and a bare `github.com/flutter` shared as
  /// plain text is rare enough not to be worth that class of false positive. The
  /// user can still choose Bookmark from the chooser, which normalizes it.
  static String? _firstUrlIn(String text) {
    final match = RegExp(r'https?://\S+').firstMatch(text);
    if (match == null) return null;

    // Trailing punctuation is part of the sentence, not of the link.
    return match.group(0)!.replaceAll(RegExp(r'[),.\]]+$'), '');
  }

  @override
  List<Object?> get props => [kind, value, fileName, mimeType];
}
