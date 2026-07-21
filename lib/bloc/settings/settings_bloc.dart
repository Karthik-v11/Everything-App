import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/bloc/ai/ai_bloc.dart';
import 'package:everything_app/bloc/budget/budget_bloc.dart';
import 'package:everything_app/bloc/home_widget/home_widget_bloc.dart';
import 'package:everything_app/bloc/tasks/tasks_bloc.dart';
import 'package:everything_app/bloc/to_buy/to_buy_bloc.dart';
import 'package:everything_app/data/entity/ai_intent.dart';
import 'package:everything_app/data/models/notification_settings.dart';
import 'package:everything_app/data/repositories/app_info_repository.dart';
import 'package:everything_app/data/repositories/notifications_repository.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'settings_event.dart';
part 'settings_state.dart';

/// [SettingsBloc] owns every setting that is not the theme (Requirement 25).
///
/// Single source of truth for [NotificationSettings], pushed to [TasksBloc] and
/// [BudgetBloc] by event dispatch, never a cross-bloc state read (CLAUDE.md §3.6).
/// Pushed on every change, which is what makes a changed setting apply
/// immediately (Requirement 25.2).
class SettingsBloc extends HydratedBloc<SettingsEvent, SettingsState> {
  SettingsBloc({
    required this.repository,
    required this.tasksBloc,
    required this.budgetBloc,
    required this.toBuyBloc,
    required this.homeWidgetBloc,
    required this.aiBloc,
    required this.appInfoRepository,
  }) : super(const SettingsState()) {
    on<InitSettingsEvent>(_onInitSettingsEvent);
    on<RequestNotificationPermissionEvent>(
      _onRequestNotificationPermissionEvent,
    );
    on<ToggleNotificationsEvent>(_onToggleNotificationsEvent);
    on<ToggleNotificationKindEvent>(_onToggleNotificationKindEvent);
    on<ChangeSummaryTimeEvent>(_onChangeSummaryTimeEvent);
    on<ChangeSummaryWeekdayEvent>(_onChangeSummaryWeekdayEvent);
    on<ChangeUserNameEvent>(_onChangeUserNameEvent);
    on<ToggleHomeWidgetsEvent>(_onToggleHomeWidgetsEvent);
    on<ChangeAiConfidenceEvent>(_onChangeAiConfidenceEvent);
  }

  final NotificationsRepository repository;
  final TasksBloc tasksBloc;
  final BudgetBloc budgetBloc;
  final ToBuyBloc toBuyBloc;
  final HomeWidgetBloc homeWidgetBloc;
  final AiBloc aiBloc;
  final AppInfoRepository appInfoRepository;

  FutureOr<void> _onInitSettingsEvent(
    InitSettingsEvent event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final initialized = await repository.initialize();
      if (!initialized.success) emit(state.copyWith(error: initialized.message));

      await _refreshPermissions(emit);

      // Hydrated settings are in [state] by now, so this first push arms the
      // schedule with the user's own choices — TasksBloc schedules nothing until
      // it hears from here, so a launch cannot briefly arm notifications the user
      // had switched off.
      if (initialized.success) _publish(state.notifications);

      // Unconditional: only the reminder schedule needs the notification plugin.
      // Returning on a failed initialize left HomeWidgetBloc's `isEnabled` null
      // for the whole session, so the home screen published nothing for a reason
      // that had nothing to do with it.
      _publishModules();

      await _readAppInfo(emit);
    } on Exception {
      emit(state.copyWith(error: 'Could not set up notifications.'));
    }
  }

  FutureOr<void> _onRequestNotificationPermissionEvent(
    RequestNotificationPermissionEvent event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      emit(state.copyWith(isLoading: true, error: '', message: ''));

      final response = await repository.requestPermission();

      await _refreshPermissions(emit);

      emit(
        response.success
            ? state.copyWith(isLoading: false, message: response.message)
            : state.copyWith(isLoading: false, error: response.message),
      );

      if (response.success) _publish(state.notifications);
    } on Exception {
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Could not turn on notifications.',
        ),
      );
    }
  }

  FutureOr<void> _onToggleNotificationsEvent(
    ToggleNotificationsEvent event,
    Emitter<SettingsState> emit,
  ) async {
    // Turning on is also the moment to ask for permission: a switch that flips to
    // "on" and then delivers nothing is worse than no switch.
    if (event.isEnabled && !state.isPermissionGranted) {
      add(const RequestNotificationPermissionEvent());
    }

    _apply(
      emit,
      state.notifications.copyWith(isEnabled: event.isEnabled),
    );
  }

  FutureOr<void> _onToggleNotificationKindEvent(
    ToggleNotificationKindEvent event,
    Emitter<SettingsState> emit,
  ) {
    _apply(
      emit,
      state.notifications.withKind(event.kind, isOn: event.isEnabled),
    );
  }

  FutureOr<void> _onChangeSummaryTimeEvent(
    ChangeSummaryTimeEvent event,
    Emitter<SettingsState> emit,
  ) {
    _apply(
      emit,
      event.kind == NotificationKind.dailySummary
          ? state.notifications.copyWith(dailySummaryMinutes: event.minutes)
          : state.notifications.copyWith(weeklySummaryMinutes: event.minutes),
    );
  }

  FutureOr<void> _onChangeSummaryWeekdayEvent(
    ChangeSummaryWeekdayEvent event,
    Emitter<SettingsState> emit,
  ) {
    _apply(
      emit,
      state.notifications.copyWith(weeklySummaryWeekday: event.weekday),
    );
  }

  /// [_onChangeUserNameEvent] sets the name the Dashboard greets
  /// (Requirement 3.1). Not published: no schedule depends on it.
  FutureOr<void> _onChangeUserNameEvent(
    ChangeUserNameEvent event,
    Emitter<SettingsState> emit,
  ) {
    emit(state.copyWith(userName: event.name.trim(), error: '', message: ''));
  }

  /// [_onToggleHomeWidgetsEvent] switches the home screen widgets on or off
  /// (Requirement 13).
  ///
  /// Off is not cosmetic: [HomeWidgetBloc] empties the shared container, the one
  /// store in this app readable without the database key.
  FutureOr<void> _onToggleHomeWidgetsEvent(
    ToggleHomeWidgetsEvent event,
    Emitter<SettingsState> emit,
  ) {
    emit(
      state.copyWith(
        areWidgetsEnabled: event.isEnabled,
        error: '',
        message: '',
      ),
    );
    homeWidgetBloc.add(ConfigureHomeWidgetEvent(isEnabled: event.isEnabled));
  }

  /// [_onChangeAiConfidenceEvent] moves the assistant's confidence threshold
  /// (Requirement 25.3).
  ///
  /// Clamped here as well as on rehydration — this is the write path, and an
  /// out-of-bounds value can only come from a caller that is already wrong.
  FutureOr<void> _onChangeAiConfidenceEvent(
    ChangeAiConfidenceEvent event,
    Emitter<SettingsState> emit,
  ) {
    final confidence =
        event.confidence.clamp(kMinAiConfidence, kMaxAiConfidence);

    emit(state.copyWith(aiConfidence: confidence, error: '', message: ''));
    aiBloc.add(ConfigureAiEvent(confidence: confidence));
  }

  /// [_apply] stores a new configuration and reschedules against it.
  void _apply(Emitter<SettingsState> emit, NotificationSettings notifications) {
    emit(state.copyWith(notifications: notifications, error: '', message: ''));
    _publish(notifications);
  }

  /// [_publish] hands the configuration to the three blocs that act on it, on
  /// every change including the first push at launch.
  ///
  /// The two reminder blocs reconcile **different kinds** against the same OS
  /// queue and never touch each other's (see [NotificationService.applyPlan]), so
  /// the order they are told in does not matter.
  void _publish(NotificationSettings notifications) {
    tasksBloc.add(SyncRemindersEvent(settings: notifications));
    budgetBloc.add(ConfigureBudgetAlertsEvent(settings: notifications));
    toBuyBloc.add(SyncToBuyRemindersEvent(settings: notifications));
  }

  /// [_publishModules] hands the non-notification settings to the blocs that act
  /// on them, at launch.
  ///
  /// [HomeWidgetBloc] publishes nothing until it hears from here — its
  /// `isEnabled` starts null, not false — so without this call a user with
  /// widgets on would have a home screen that never updated after a restart.
  void _publishModules() {
    homeWidgetBloc.add(
      ConfigureHomeWidgetEvent(isEnabled: state.areWidgetsEnabled),
    );
    aiBloc.add(ConfigureAiEvent(confidence: state.aiConfidence));
  }

  /// [_readAppInfo] fills in the About section's version (Requirement 25.1).
  ///
  /// A failure is silent by design: the section omits the version rather than
  /// putting an error banner on Settings over a string nobody came here for.
  Future<void> _readAppInfo(Emitter<SettingsState> emit) async {
    final response = await appInfoRepository.read();
    if (!response.success) return;

    final info = response.data! as ({
      String version,
      String buildNumber,
      String packageName,
    });

    emit(
      state.copyWith(
        appVersion: '${info.version} (${info.buildNumber})',
        packageName: info.packageName,
      ),
    );
  }

  Future<void> _refreshPermissions(Emitter<SettingsState> emit) async {
    final response = await repository.permissions();
    if (!response.success) return;

    final permissions =
        response.data! as ({bool isGranted, bool canScheduleExact});

    emit(
      state.copyWith(
        isPermissionGranted: permissions.isGranted,
        isExactAlarmAllowed: permissions.canScheduleExact,
      ),
    );
  }

  @override
  SettingsState? fromJson(Map<String, dynamic> json) =>
      SettingsState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(SettingsState state) => state.toJson();
}
