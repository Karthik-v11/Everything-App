import 'package:everything_app/data/models/home_widget_payload.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:home_widget/home_widget.dart';

/// [HomeWidgetService] pushes the app's data onto the home screen
/// (Requirement 13).
///
/// A widget is a different process with no SQLCipher key, so it can only render
/// what the app copies into a shared container — an App Group on iOS,
/// `SharedPreferences` on Android — and that container is **not encrypted**.
/// Every field written here has therefore left the encrypted database, and the
/// set is kept to the minimum a glanceable widget needs:
///
/// - **The vault is never written here, in any form** — not a name, not a count.
///   Requirement 9 puts it behind a second layer of encryption and a fresh auth
///   challenge; a plaintext container readable on a lock screen undoes both.
/// - No per-transaction amounts, account names, or note/document bodies. The
///   spend figure is one month's total.
/// - [clear] removes the data when the widgets are switched off rather than
///   orphaning the last copy in the container.
class HomeWidgetService {
  HomeWidgetService();

  /// The App Group both the app and the iOS widget extension are members of.
  ///
  /// Must match the `com.apple.security.application-groups` entitlement on both
  /// the Runner and the widget target. A mismatch does not error — the widget
  /// just draws its placeholder forever.
  static const String appGroupId = 'group.com.karthik.everythingApp';

  /// The two widgets that draw published data. Android matches the provider's
  /// fully-qualified class, iOS the `kind` string in `StaticConfiguration`; both
  /// are string-matched with no compile-time check, so a rename in Kotlin or
  /// Swift silently stops the redraw.
  ///
  /// The quick-add widget is absent: it draws no data, so there is nothing to
  /// reload.
  static const List<({String android, String iOS})> _dataWidgets = [
    (
      android: 'com.karthik.everything_app.TodayTasksWidgetProvider',
      iOS: 'EverythingWidget',
    ),
    (
      android: 'com.karthik.everything_app.FinanceWidgetProvider',
      iOS: 'EverythingFinanceWidget',
    ),
  ];

  /// [initialize] registers the App Group. iOS-only in effect; a no-op on
  /// Android, where `SharedPreferences` needs no such handshake.
  Future<JsonResponse> initialize() async {
    try {
      await HomeWidget.setAppGroupId(appGroupId);
      return JsonResponse.success(message: 'Ready.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not set up home screen widgets.',
      );
    }
  }

  /// [initialTap] is the widget tap that launched the app, if one did.
  ///
  /// A tap on a cold app and one on a running app ([taps]) are different paths,
  /// as with [ShareService]; handling only this one makes the widget work once
  /// and then appear dead.
  Future<JsonResponse> initialTap() async {
    try {
      return JsonResponse.success(
        message: 'Loaded successfully.',
        data: await HomeWidget.initiallyLaunchedFromHomeWidget(),
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not read the widget tap.',
      );
    }
  }

  /// [taps] is every widget tap while the app is running.
  Stream<Uri?> taps() => HomeWidget.widgetClicked;

  /// [push] writes [payload] and asks both platforms to redraw.
  ///
  /// Every key is rewritten on every push. Unlike the OS alarm queue that
  /// `NotificationService.applyPlan` must diff against, this container is a
  /// key/value store the app solely writes, so overwriting is the cheapest
  /// correct thing.
  Future<JsonResponse> push(HomeWidgetPayload payload) async {
    try {
      for (final entry in payload.toWidgetData().entries) {
        await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
      }

      await _redraw();

      return JsonResponse.success(message: 'Updated.', data: payload);
    } on Exception {
      // A failed widget update must never surface: the app is fine and the home
      // screen keeps its last good draw. Reported, not shown.
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not update the home screen widgets.',
      );
    }
  }

  /// [clear] empties the shared container when the widgets are switched off, so
  /// the data leaves the unencrypted container. The redraw drops any widget
  /// still on the home screen back to its empty state rather than a frozen
  /// snapshot of data the user asked the app to stop publishing.
  Future<JsonResponse> clear() async {
    try {
      for (final key in _keys) {
        await HomeWidget.saveWidgetData<String>(key, null);
      }

      await _redraw();

      return JsonResponse.success(message: 'Home screen widgets turned off.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not clear the home screen widgets.',
      );
    }
  }

  Future<void> _redraw() async {
    for (final widget in _dataWidgets) {
      await HomeWidget.updateWidget(
        qualifiedAndroidName: widget.android,
        iOSName: widget.iOS,
      );
    }
  }

  /// The keys [clear] erases. Derived from an empty payload so a field added to
  /// [HomeWidgetPayload.toWidgetData] cannot be left behind here.
  static Iterable<String> get _keys => const HomeWidgetPayload(
        tasks: [],
        openCount: 0,
        completedCount: 0,
        overdueCount: 0,
        spentLabel: '',
        spentCaption: '',
        updatedAtLabel: '',
      ).toWidgetData().keys;
}
