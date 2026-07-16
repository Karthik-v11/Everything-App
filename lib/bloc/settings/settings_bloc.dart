import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/bloc/ai/ai_bloc.dart';
import 'package:everything_app/bloc/budget/budget_bloc.dart';
import 'package:everything_app/bloc/home_widget/home_widget_bloc.dart';
import 'package:everything_app/bloc/on_device_model/on_device_model_bloc.dart';
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
/// Style A: the settings are independent slices of one persistent object, updated
/// via [copyWith] and persisted by [HydratedBloc]. Today that is the notification
/// configuration; later phases add their sections to the same state.
///
/// It is the **single source of truth** for [NotificationSettings], and it pushes
/// them to the two blocs that turn settings into notifications: [TasksBloc], which
/// owns the task list and therefore the reminder schedule, and [BudgetBloc], which
/// owns the budget and therefore its alerts. Neither can be reached from here by
/// reading its state — the push is an event dispatch (CLAUDE.md §3.6) — and it
/// happens on every change, which is what makes a changed setting apply
/// immediately (Requirement 25.2).
///
/// Events:
/// 1) [InitSettingsEvent] — set up the plugin, read the permission, arm the first
///    schedule. Fired once at launch.
/// 2) [RequestNotificationPermissionEvent] — ask the OS for permission.
/// 3) [ToggleNotificationsEvent] — the master switch.
/// 4) [ToggleNotificationKindEvent] — one of the five kinds.
/// 5) [ChangeSummaryTimeEvent] — when a digest fires.
/// 6) [ChangeSummaryWeekdayEvent] — which day the weekly digest fires.
/// 7) [ChangeUserNameEvent] — the name the Dashboard greets (Requirement 3.1).
class SettingsBloc extends HydratedBloc<SettingsEvent, SettingsState> {
  SettingsBloc({
    required this.repository,
    required this.tasksBloc,
    required this.budgetBloc,
    required this.toBuyBloc,
    required this.homeWidgetBloc,
    required this.aiBloc,
    required this.onDeviceModelBloc,
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
    on<ToggleOnDeviceAiEvent>(_onToggleOnDeviceAiEvent);
  }

  final NotificationsRepository repository;
  final TasksBloc tasksBloc;
  final BudgetBloc budgetBloc;
  final ToBuyBloc toBuyBloc;
  final HomeWidgetBloc homeWidgetBloc;
  final AiBloc aiBloc;
  final OnDeviceModelBloc onDeviceModelBloc;
  final AppInfoRepository appInfoRepository;

  FutureOr<void> _onInitSettingsEvent(
    InitSettingsEvent event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final initialized = await repository.initialize();
      if (!initialized.success) {
        emit(state.copyWith(error: initialized.message));
        return;
      }

      await _refreshPermissions(emit);

      // The hydrated settings are already in [state] by the time the constructor
      // returns, so this first push arms the schedule with what the user actually
      // chose — TasksBloc deliberately schedules nothing until it hears from here,
      // which is what stops a launch from briefly arming notifications the user
      // had switched off.
      _publish(state.notifications);
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
    // Turning them on for the first time is also the moment to ask for the
    // permission — a switch that flips to "on" and then delivers nothing is worse
    // than no switch at all.
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
  /// (Requirement 3.1).
  ///
  /// Nothing is published: no schedule depends on it, and it is the one setting
  /// here that only a screen reads.
  FutureOr<void> _onChangeUserNameEvent(
    ChangeUserNameEvent event,
    Emitter<SettingsState> emit,
  ) {
    emit(state.copyWith(userName: event.name.trim(), error: '', message: ''));
  }

  /// [_onToggleHomeWidgetsEvent] switches the home screen widgets on or off
  /// (Requirement 13).
  ///
  /// Off is not cosmetic: [HomeWidgetBloc] empties the shared container, so the
  /// data actually leaves the one place in this app that is readable without the
  /// database key.
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
  /// Clamped here as well as on rehydration: this is the write path, and a value
  /// outside the slider's bounds could only arrive from a caller that is wrong,
  /// which is exactly when a silent 0 or 1 would be hardest to trace.
  FutureOr<void> _onChangeAiConfidenceEvent(
    ChangeAiConfidenceEvent event,
    Emitter<SettingsState> emit,
  ) {
    final confidence =
        event.confidence.clamp(kMinAiConfidence, kMaxAiConfidence);

    emit(state.copyWith(aiConfidence: confidence, error: '', message: ''));
    aiBloc.add(ConfigureAiEvent(confidence: confidence));
  }

  /// [_onToggleOnDeviceAiEvent] switches the on-device model on or off
  /// (Phase 13).
  ///
  /// Off is not cosmetic, in the same way the widget switch is not:
  /// [OnDeviceModelBloc] unloads the model, and the assistant is model-backed
  /// only for as long as a model is in memory. It frees the RAM immediately
  /// rather than at the next launch.
  FutureOr<void> _onToggleOnDeviceAiEvent(
    ToggleOnDeviceAiEvent event,
    Emitter<SettingsState> emit,
  ) {
    emit(
      state.copyWith(
        isOnDeviceAiEnabled: event.isEnabled,
        error: '',
        message: '',
      ),
    );
    onDeviceModelBloc.add(
      ConfigureOnDeviceModelEvent(isEnabled: event.isEnabled),
    );
  }

  /// [_apply] stores a new configuration and reschedules against it.
  void _apply(Emitter<SettingsState> emit, NotificationSettings notifications) {
    emit(state.copyWith(notifications: notifications, error: '', message: ''));
    _publish(notifications);
  }

  /// [_publish] hands the configuration to the three blocs that act on it.
  ///
  /// [TasksBloc] and [ToBuyBloc] each rebuild their own slice of the OS schedule
  /// from it; [BudgetBloc] re-evaluates its alerts against it. All three are told on
  /// every change, including the first push at launch — a setting that is not
  /// published is a setting that does nothing.
  ///
  /// The two reminder blocs reconcile **different kinds** against the same OS queue
  /// and never touch each other's (see [NotificationService.applyPlan]), so the
  /// order they are told in does not matter.
  void _publish(NotificationSettings notifications) {
    tasksBloc.add(SyncRemindersEvent(settings: notifications));
    budgetBloc.add(ConfigureBudgetAlertsEvent(settings: notifications));
    toBuyBloc.add(SyncToBuyRemindersEvent(settings: notifications));
  }

  /// [_publishModules] hands the non-notification settings to the blocs that act
  /// on them, at launch.
  ///
  /// Separate from [_publish] because these are not notification configuration
  /// and have nothing to do with the schedule — but the rule is the same one, and
  /// it is the rule that matters: a setting that is not published is a setting
  /// that does nothing.
  ///
  /// [HomeWidgetBloc] in particular publishes **nothing** until it hears from
  /// here — its `isEnabled` starts null rather than false — so without this call
  /// a user with widgets switched on would have a home screen that never updated
  /// again after a restart.
  void _publishModules() {
    homeWidgetBloc.add(
      ConfigureHomeWidgetEvent(isEnabled: state.areWidgetsEnabled),
    );
    aiBloc.add(ConfigureAiEvent(confidence: state.aiConfidence));

    // [OnDeviceModelBloc] starts with the model off, so without this push a user
    // who had switched it on would get the rule-based engine forever after a
    // restart — the Phase 12 bug that made `HomeWidgetBloc.isEnabled` start null.
    //
    // This races [InitOnDeviceModelEvent] and does not need to win. Either order
    // converges: if this lands first there is nothing on disk to load yet and
    // Init loads it; if Init lands first it sees the model off and this loads it.
    // Neither can load twice — `load()` is idempotent.
    onDeviceModelBloc.add(
      ConfigureOnDeviceModelEvent(isEnabled: state.isOnDeviceAiEnabled),
    );
  }

  /// [_readAppInfo] fills in the About section's version (Requirement 25.1).
  ///
  /// A failure is silent by design: the About section simply omits the version
  /// rather than putting an error banner on the Settings screen over a string
  /// nobody came here for.
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
