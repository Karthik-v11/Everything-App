import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/data/models/attachment.dart';
import 'package:everything_app/data/models/bookmark.dart';
import 'package:everything_app/data/models/document.dart';
import 'package:everything_app/data/models/shared_item.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/data/repositories/attachments_repository.dart';
import 'package:everything_app/data/repositories/bookmarks_repository.dart';
import 'package:everything_app/data/repositories/documents_repository.dart';
import 'package:everything_app/data/repositories/share_repository.dart';
import 'package:everything_app/data/repositories/tasks_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

part 'share_event.dart';
part 'share_state.dart';

/// [ShareBloc] receives content shared into the app and files it
/// (Requirement 12).
///
/// The share layer routes but never persists: it files through the same
/// repositories the in-app sheets use, so a share and an in-app entry are
/// identical downstream (same validation, enrichment and DAO streams).
class ShareBloc extends Bloc<ShareEvent, ShareState> {
  ShareBloc({
    required this.repository,
    required this.bookmarksRepository,
    required this.tasksRepository,
    required this.documentsRepository,
    required this.attachmentsRepository,
  }) : super(const ShareState()) {
    on<WatchSharesEvent>(_onWatchSharesEvent);
    on<SharesReceivedEvent>(_onSharesReceivedEvent);
    on<ShareDestinationChosen>(_onShareDestinationChosen);
    on<ShareDismissed>(_onShareDismissed);
  }

  final ShareRepository repository;
  final BookmarksRepository bookmarksRepository;
  final TasksRepository tasksRepository;
  final DocumentsRepository documentsRepository;
  final AttachmentsRepository attachmentsRepository;

  static const Uuid _uuid = Uuid();

  /// Wires both of the plugin's paths: the launch share (read once) and the
  /// stream. Both funnel into [SharesReceivedEvent] so there is exactly one
  /// place a share becomes state.
  FutureOr<void> _onWatchSharesEvent(
    WatchSharesEvent event,
    Emitter<ShareState> emit,
  ) async {
    try {
      final initial = await repository.initial();
      if (initial.success) {
        final items = initial.data! as List<SharedItem>;
        if (items.isNotEmpty) add(SharesReceivedEvent(items: items));
      }

      // `emit.forEach` holds the handler open for the life of the bloc, which is
      // what keeps the subscription alive without a manual `cancel` in `close`.
      await emit.forEach<List<SharedItem>>(
        repository.stream(),
        onData: (items) {
          if (items.isNotEmpty) add(SharesReceivedEvent(items: items));
          return state;
        },
        onError: (error, stackTrace) =>
            state.copyWith(error: 'Could not read the shared content.'),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not read the shared content.'));
    }
  }

  /// Parks the share and opens the chooser. Multiple items are kept together
  /// and filed to one destination — a multi-select share is one intent.
  FutureOr<void> _onSharesReceivedEvent(
    SharesReceivedEvent event,
    Emitter<ShareState> emit,
  ) {
    emit(
      state.copyWith(
        pending: event.items,
        isChooserOpen: true,
        error: '',
        message: '',
      ),
    );
  }

  FutureOr<void> _onShareDestinationChosen(
    ShareDestinationChosen event,
    Emitter<ShareState> emit,
  ) async {
    final items = state.pending;
    if (items.isEmpty) return;

    try {
      emit(state.copyWith(isLoading: true, error: '', message: ''));

      final message = await _file(
        items: items,
        destination: event.destination,
        projectId: event.projectId,
      );

      // Reset either way, or the next cold launch replays a share already filed.
      await repository.reset();

      emit(
        message == null
            ? state.copyWith(
                isLoading: false,
                error: 'Could not save what you shared.',
              )
            : state.copyWith(
                isLoading: false,
                message: message,
                pending: const <SharedItem>[],
                isChooserOpen: false,
              ),
      );
    } on Exception {
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Could not save what you shared.',
        ),
      );
    }
  }

  FutureOr<void> _onShareDismissed(
    ShareDismissed event,
    Emitter<ShareState> emit,
  ) async {
    await repository.reset();
    emit(
      state.copyWith(
        pending: const <SharedItem>[],
        isChooserOpen: false,
        error: '',
        message: '',
      ),
    );
  }

  /// Writes every item to [destination], returning the confirmation to show or
  /// null if nothing could be saved. Partial success still reports success —
  /// the items that did save are real.
  Future<String?> _file({
    required List<SharedItem> items,
    required ShareDestination destination,
    String? projectId,
  }) async {
    var saved = 0;

    for (final item in items) {
      if (!destination.isAvailableFor(item.kind)) continue;

      final success = switch (destination) {
        ShareDestination.bookmark => await _saveBookmark(item),
        ShareDestination.task => await _saveTask(item),
        ShareDestination.document => await _saveDocument(item),
        ShareDestination.projectFile => await _saveProjectFile(item, projectId),
      };

      if (success) saved++;
    }

    if (saved == 0) return null;

    final noun = saved == 1 ? destination.label.toLowerCase() : 'items';
    return 'Saved $saved $noun.';
  }

  /// Files a link exactly as the Library's own sheet does — derived title and
  /// source now, background enrichment after.
  Future<bool> _saveBookmark(SharedItem item) async {
    final url = UrlMetadata.normalize(item.value);
    final metadata = UrlMetadata.read(url);
    final id = _uuid.v4();

    final response = await bookmarksRepository.create(
      Bookmark(
        id: id,
        url: url,
        title: metadata.title,
        thumbnailUrl: metadata.thumbnailUrl,
        sourceType: metadata.source,
        savedAt: DateTime.now(),
      ),
    );

    if (!response.success) return false;

    // Best-effort: the bookmark is already saved, so enrichment failure must not
    // fail the result.
    unawaited(bookmarksRepository.enrich(id));

    return true;
  }

  /// Makes a to-do out of a share. A shared link goes into the notes and its
  /// derived title becomes the task name — a raw URL as a title is unreadable.
  Future<bool> _saveTask(SharedItem item) async {
    final now = DateTime.now();

    final task = switch (item.kind) {
      SharedKind.url => Task(
          id: _uuid.v4(),
          title: UrlMetadata.read(item.value).title,
          notes: item.value,
          createdAt: now,
          updatedAt: now,
        ),
      SharedKind.text || SharedKind.file => Task(
          id: _uuid.v4(),
          title: _titleFrom(item.value),
          notes: item.value.length > _titleLimit ? item.value : null,
          createdAt: now,
          updatedAt: now,
        ),
    };

    final response = await tasksRepository.create(task);
    return response.success;
  }

  Future<bool> _saveDocument(SharedItem item) async {
    final now = DateTime.now();

    final response = await documentsRepository.save(
      Document(
        id: _uuid.v4(),
        title: item.kind == SharedKind.url
            ? UrlMetadata.read(item.value).title
            : _titleFrom(item.value),
        content: item.value,
        createdAt: now,
        updatedAt: now,
      ),
    );

    return response.success;
  }

  Future<bool> _saveProjectFile(SharedItem item, String? projectId) async {
    if (projectId == null || projectId.isEmpty) return false;

    final response = await attachmentsRepository.attach(
      ownerType: AttachmentOwner.project,
      ownerId: projectId,
      sourcePath: item.value,
      fileName: item.fileName ?? 'File',
      mimeType: item.mimeType,
    );

    return response.success;
  }

  static const int _titleLimit = 60;

  /// One-line name for a block of shared text: the first line when short
  /// enough, else a truncation. The full text is kept in the body either way.
  static String _titleFrom(String text) {
    final firstLine = text.trim().split('\n').first.trim();
    if (firstLine.isEmpty) return 'Shared note';
    if (firstLine.length <= _titleLimit) return firstLine;

    return '${firstLine.substring(0, _titleLimit).trimRight()}…';
  }
}
