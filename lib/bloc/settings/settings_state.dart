part of 'settings_bloc.dart';

/// [SettingsState] holds every non-theme setting (Requirement 25).
///
/// [notifications] is the user's configuration and is persisted.
/// [isPermissionGranted] and [isExactAlarmAllowed] are read from the OS at launch
/// and after every request, never persisted: either can be revoked from system
/// settings while the app is closed.
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

  /// Whether the home screen widgets publish (Requirement 13). On by default.
  ///
  /// Owned here, not by [HomeWidgetBloc], because it is a user choice that must
  /// survive a restart; pushed to [HomeWidgetBloc] by event dispatch. It decides
  /// whether task titles and a spend figure leave the encrypted database for a
  /// container the OS lets a widget process read — see [HomeWidgetService].
  final bool areWidgetsEnabled;

  /// The score a parsed AI intent must reach before the assistant acts on it
  /// rather than asking a clarifying question (Requirements 16.7, 25.3).
  ///
  /// Pushed to [AiBloc], which applies it to the next parse — Requirement 25.3's
  /// "subsequent interactions".
  final double aiConfidence;

  /// The About section's version, as `1.2.0 (14)`, and the package id
  /// (Requirement 25.1).
  ///
  /// Read from the platform at launch and not persisted: the value changes
  /// underneath a stored copy on every app update. Empty until the read lands,
  /// and the section omits the line rather than showing a placeholder.
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
        // Clamped, not merely defaulted: a threshold outside 0–1 from a corrupt
        // or downgraded store would make the assistant act on everything or
        // refuse everything, with no way for the user to see why.
        aiConfidence: _clampConfidence(json['HydratedAiConfidence']),
      );

  Map<String, dynamic> toJson() => {
        'HydratedUserName': userName,
        'HydratedNotifications': notifications.toJson(),
        'HydratedWidgetsEnabled': areWidgetsEnabled,
        'HydratedAiConfidence': aiConfidence,
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
        appVersion,
        packageName,
      ];
}
