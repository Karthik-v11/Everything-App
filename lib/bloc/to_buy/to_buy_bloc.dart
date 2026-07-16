import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/models/notification_settings.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/data/models/to_buy_item.dart';
import 'package:everything_app/data/repositories/notifications_repository.dart';
import 'package:everything_app/data/repositories/to_buy_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'to_buy_event.dart';
part 'to_buy_state.dart';

/// [ToBuyBloc] owns the To Buy list (Requirement 7).
///
/// Style A: it holds the list, the filters and the search query.
///
/// Reminders (Requirement 7.3) are scheduled from here, and they are **reconciled
/// rather than written** — the same rule Phase 4 established for tasks, for the same
/// reason. [ToBuyPlan.build] is a pure function of the list, the settings and the
/// clock, describing every reminder that *should* be pending; the service diffs it
/// against the OS queue and arms or withdraws only the difference. So an item that
/// is purchased, deleted, or has its reminder cleared loses its alarm without a
/// single cancel call existing anywhere in this file — including from code that has
/// not been written yet.
///
/// It reconciles only [NotificationKind.toBuyKinds]. The task reminders share the
/// same OS queue, and a reconciler that claimed the whole thing would cancel them
/// (see [NotificationService.applyPlan]).
///
/// Events:
/// 1) [WatchToBuyEvent] — subscribe to the list. Fired once.
/// 2) [FilterToBuyEvent] — purchased / priority narrowing.
/// 3) [SearchToBuyEvent] — in-module search.
/// 4) [SaveToBuyItemEvent] / [DeleteToBuyItemEvent] — the sheet and the swipe.
/// 5) [ToggleToBuyPurchasedEvent] — the checkbox (Requirement 7.2).
/// 6) [SyncToBuyRemindersEvent] — rebuild the reminder schedule.
class ToBuyBloc extends Bloc<ToBuyEvent, ToBuyState> {
  ToBuyBloc({
    required this.repository,
    required this.notificationsRepository,
  }) : super(const ToBuyState()) {
    on<WatchToBuyEvent>(_onWatchToBuyEvent);
    on<FilterToBuyEvent>(_onFilterToBuyEvent);
    on<SearchToBuyEvent>(_onSearchToBuyEvent);
    on<SaveToBuyItemEvent>(_onSaveToBuyItemEvent);
    on<ToggleToBuyPurchasedEvent>(_onToggleToBuyPurchasedEvent);
    on<DeleteToBuyItemEvent>(_onDeleteToBuyItemEvent);
    on<SyncToBuyRemindersEvent>(_onSyncToBuyRemindersEvent);
  }

  final ToBuyRepository repository;
  final NotificationsRepository notificationsRepository;

  FutureOr<void> _onWatchToBuyEvent(
    WatchToBuyEvent event,
    Emitter<ToBuyState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: '', message: ''));

    await emit.forEach<List<ToBuyItem>>(
      repository.watchAll(),
      onData: (items) {
        // Every write to the list comes back through this stream, so this is the
        // one place that has to ask for a reschedule. onData cannot await, so the
        // work is queued as an event rather than done inline.
        add(const SyncToBuyRemindersEvent());

        return state.copyWith(isLoading: false, items: items, error: '');
      },
      onError: (_, _) => state.copyWith(
        isLoading: false,
        error: 'Could not load your list.',
      ),
    );
  }

  FutureOr<void> _onFilterToBuyEvent(
    FilterToBuyEvent event,
    Emitter<ToBuyState> emit,
  ) {
    emit(
      state.copyWith(
        showPurchased: event.showPurchased,
        priority: event.priority,
        clearPriority: event.priority == null,
      ),
    );
  }

  FutureOr<void> _onSearchToBuyEvent(
    SearchToBuyEvent event,
    Emitter<ToBuyState> emit,
  ) {
    emit(state.copyWith(query: event.query));
  }

  FutureOr<void> _onSaveToBuyItemEvent(
    SaveToBuyItemEvent event,
    Emitter<ToBuyState> emit,
  ) async {
    try {
      final response = event.isEditing
          ? await repository.update(event.item)
          : await repository.create(event.item);

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not save the item.'));
    }
  }

  /// [_onToggleToBuyPurchasedEvent] ticks an item off (Requirement 7.2).
  ///
  /// It does not cancel the item's reminder. It does not have to: the write returns
  /// through the stream, the stream asks for a resync, and the plan does not include
  /// a purchased item — so the alarm is withdrawn by the reconciliation rather than
  /// by anything here remembering to withdraw it.
  FutureOr<void> _onToggleToBuyPurchasedEvent(
    ToggleToBuyPurchasedEvent event,
    Emitter<ToBuyState> emit,
  ) async {
    try {
      final response = await repository.setPurchased(
        item: event.item,
        isPurchased: event.isPurchased,
      );

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not update the item.'));
    }
  }

  FutureOr<void> _onDeleteToBuyItemEvent(
    DeleteToBuyItemEvent event,
    Emitter<ToBuyState> emit,
  ) async {
    try {
      final response = await repository.delete(event.id);

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not delete the item.'));
    }
  }

  /// [_onSyncToBuyRemindersEvent] rebuilds the reminder schedule (Requirement 7.3).
  ///
  /// Idempotent, so running it more often than strictly necessary costs one query of
  /// the pending queue and nothing else.
  ///
  /// It does nothing until [SettingsBloc] has reported the user's configuration.
  /// Scheduling against the defaults first would fire a burst of reminders at a user
  /// who had switched them off, and cancel them a moment later.
  FutureOr<void> _onSyncToBuyRemindersEvent(
    SyncToBuyRemindersEvent event,
    Emitter<ToBuyState> emit,
  ) async {
    final settings = event.settings ?? state.notificationSettings;
    if (settings == null) return;

    if (settings != state.notificationSettings) {
      emit(state.copyWith(notificationSettings: settings));
    }

    try {
      final plan = ToBuyPlan.build(
        items: state.items,
        settings: settings,
        now: DateTime.now(),
      );

      final response = await notificationsRepository.applyPlan(
        plan,
        owns: NotificationKind.toBuyKinds,
      );

      if (!response.success) emit(state.copyWith(error: response.message));
    } on Exception {
      emit(state.copyWith(error: 'Could not update your reminders.'));
    }
  }
}
