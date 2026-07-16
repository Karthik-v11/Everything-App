part of 'settings_bloc.dart';

/// [SettingsState] holds every non-theme setting (Requirement 25).
///
/// [notifications] is the user's configuration and is persisted.
/// [isPermissionGranted] and [isExactAlarmAllowed] are the OS's answer, read at
/// launch and after every request. They are **not** persisted: the user can
/// revoke either from system settings while the app is closed, so a remembered
/// value would be a guess where a fresh one is a fact.
class SettingsState extends Equatable {
  const SettingsState({
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.userName = '',
    this.notifications = const NotificationSettings(),
    this.isPermissionGranted = false,
    this.isExactAlarmAllowed = false,
    this.areWidgetsEnabled = true,
    this.aiConfidence = kAiConfidenceThreshold,
    this.isOnDeviceAiEnabled = false,
    this.appVersion = '',
    this.packageName = '',
  });

  final bool isLoading;
  final String error;
  final String message;

  /// The name the Dashboard greets (Requirement 3.1). Empty until the user gives
  /// one, and the greeting simply drops the name rather than inventing one.
  final String userName;

  final NotificationSettings notifications;
  final bool isPermissionGranted;
  final bool isExactAlarmAllowed;

  /// Whether the home screen widgets publish (Requirement 13).
  ///
  /// Owned here rather than by [HomeWidgetBloc] for the same reason the
  /// notification configuration is: it is a user choice that has to survive a
  /// restart, and one owner of a value is one value that cannot disagree with
  /// itself. It is pushed to [HomeWidgetBloc] by event dispatch.
  ///
  /// On by default, and it is the switch that decides whether task titles and a
  /// spend figure leave the encrypted database for a container the OS lets a
  /// widget process read — see [HomeWidgetService].
  final bool areWidgetsEnabled;

  /// The score a parsed AI intent must reach before the assistant acts on it
  /// rather than asking a clarifying question (Requirements 16.7, 25.3).
  ///
  /// This is the assistant's one real knob today, and a real one: raise it and
  /// the assistant asks more and guesses less; lower it and it acts on shakier
  /// input. It is pushed to [AiBloc], which applies it to the next parse — which
  /// is Requirement 25.3's "subsequent interactions", exactly.
  final double aiConfidence;

  /// Whether the assistant's prose is backed by the on-device model (Phase 13).
  ///
  /// **Off by default, and it stays off until asked**, for three reasons that are
  /// all the user's to weigh rather than ours: it costs a 584 MB download, it
  /// costs hundreds of MB of RAM while loaded, and it changes a document summary
  /// from extractive — lifting the document's own sentences, which can never
  /// misstate it — to generated, which can. The parsers are never affected either
  /// way (see [ModelBackedAiRepository]).
  ///
  /// Owned here for the same reason [areWidgetsEnabled] is: it is a user choice
  /// that has to survive a restart, and one owner of a value is one value that
  /// cannot disagree with itself. It is pushed to [OnDeviceModelBloc] by event
  /// dispatch, which loads or unloads the model — the switch has no other
  /// mechanism.
  final bool isOnDeviceAiEnabled;

  /// The About section's version, as `1.2.0 (14)`, and the package id
  /// (Requirement 25.1).
  ///
  /// Read from the platform at launch and **not persisted**, for the same reason
  /// the notification permissions are not: the value changes underneath a stored
  /// copy on every app update, so a remembered one would be a guess that is wrong
  /// exactly when someone is reading it to check which build they are on. Empty
  /// until the read lands, and the section omits the line rather than showing a
  /// placeholder.
  final String appVersion;
  final String packageName;

  /// [isDelivering] is true only when notifications are both switched on in the
  /// app and permitted by the OS — the one condition under which the user will
  /// actually receive anything.
  bool get isDelivering => notifications.isEnabled && isPermissionGranted;

  /// [isExactAlarmWarningVisible] is true when reminders will be delivered late
  /// because the OS has not granted exact alarms (Android 14+).
  bool get isExactAlarmWarningVisible => isDelivering && !isExactAlarmAllowed;

  SettingsState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    String? userName,
    NotificationSettings? notifications,
    bool? isPermissionGranted,
    bool? isExactAlarmAllowed,
    bool? areWidgetsEnabled,
    double? aiConfidence,
    bool? isOnDeviceAiEnabled,
    String? appVersion,
    String? packageName,
  }) =>
      SettingsState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        userName: userName ?? this.userName,
        notifications: notifications ?? this.notifications,
        isPermissionGranted: isPermissionGranted ?? this.isPermissionGranted,
        isExactAlarmAllowed: isExactAlarmAllowed ?? this.isExactAlarmAllowed,
        areWidgetsEnabled: areWidgetsEnabled ?? this.areWidgetsEnabled,
        aiConfidence: aiConfidence ?? this.aiConfidence,
        isOnDeviceAiEnabled: isOnDeviceAiEnabled ?? this.isOnDeviceAiEnabled,
        appVersion: appVersion ?? this.appVersion,
        packageName: packageName ?? this.packageName,
      );

  /// [fromJson] restores only the user's choices. The OS permissions are re-read
  /// on every launch.
  factory SettingsState.fromJson(Map<String, dynamic> json) => SettingsState(
        userName: json['HydratedUserName']?.toString() ?? '',
        notifications: json['HydratedNotifications'] == null
            ? const NotificationSettings()
            : NotificationSettings.fromJson(
                json['HydratedNotifications'] as Map<String, dynamic>,
              ),
        areWidgetsEnabled: json['HydratedWidgetsEnabled'] as bool? ?? true,
        // Clamped on the way in, not merely defaulted: a threshold outside 0–1
        // read from a corrupt or downgraded store would make the assistant
        // either act on everything or refuse everything, with no way for the
        // user to see why.
        aiConfidence: _clampConfidence(json['HydratedAiConfidence']),
        // Defaults to false rather than to its stored value's truthiness: a store
        // written before Phase 13 has no such key, and the safe reading of "the
        // user has never been asked" is that they have not opted into a 584 MB
        // download.
        isOnDeviceAiEnabled: json['HydratedOnDeviceAiEnabled'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'HydratedUserName': userName,
        'HydratedNotifications': notifications.toJson(),
        'HydratedWidgetsEnabled': areWidgetsEnabled,
        'HydratedAiConfidence': aiConfidence,
        'HydratedOnDeviceAiEnabled': isOnDeviceAiEnabled,
      };

  static double _clampConfidence(Object? raw) {
    final value = raw is num ? raw.toDouble() : null;
    if (value == null || value.isNaN) return kAiConfidenceThreshold;
    return value.clamp(kMinAiConfidence, kMaxAiConfidence);
  }

  @override
  List<Object?> get props => [
        isLoading,
        error,
        message,
        userName,
        notifications,
        isPermissionGranted,
        isExactAlarmAllowed,
        areWidgetsEnabled,
        aiConfidence,
        isOnDeviceAiEnabled,
        appVersion,
        packageName,
      ];
}
