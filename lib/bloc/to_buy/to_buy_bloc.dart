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
/// Reminders (Requirement 7.3) are **reconciled, never written directly**:
/// [ToBuyPlan.build] is a pure function of the list, settings and clock describing
/// what should be pending, and the service arms or withdraws only the difference —
/// so a purchased or deleted item loses its alarm with no cancel call anywhere.
///
/// It reconciles only [NotificationKind.toBuyKinds]: task reminders share the
/// same OS queue and a reconciler claiming the whole queue would cancel them.
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
        // Every write returns through this stream, so this is the one place that
        // asks for a reschedule. Queued as an event because onData cannot await.
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
  /// It deliberately does not cancel the reminder: the write returns through the
  /// stream, which triggers a resync, and the plan excludes purchased items.
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
  /// Idempotent — over-running it costs one query of the pending queue.
  ///
  /// It does nothing until [SettingsBloc] reports the user's configuration:
  /// scheduling against defaults would fire reminders at a user who turned them off.
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
