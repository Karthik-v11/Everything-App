import 'package:everything_app/data/models/home_widget_payload.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:home_widget/home_widget.dart';

/// [HomeWidgetService] pushes the app's data onto the home screen
/// (Requirement 13).
///
/// ## What crosses the boundary, and why it is narrow
///
/// A home screen widget is a **different process**. It cannot open the app's
/// SQLCipher database — it has no key, and Phase 2 went to some trouble to make
/// sure of that — so the only way it can render anything is if the app copies
/// what it needs into a container both processes can read: an App Group on iOS,
/// `SharedPreferences` on Android.
///
/// **That container is not encrypted.** Nothing the OS offers makes it so while
/// still being readable by a widget process at draw time. So every field written
/// here is one that has left the encrypted database, and the set is kept to the
/// minimum a glanceable widget needs: task titles, three counts, and a
/// pre-formatted spend figure. Concretely, and permanently:
///
/// - **The vault is never written here, at any size, in any form** — not a name,
///   not a count. Requirement 9 puts vault contents behind a second layer of
///   encryption *and* a fresh auth challenge; copying any of it into a plaintext
///   container readable with the phone locked would undo both, and a widget is
///   drawn on a lock screen.
/// - No amounts per transaction, no account names, no note or document bodies.
///   The spend figure is one month's total, which is the least specific thing
///   that still answers the question the widget exists to answer.
/// - [clear] exists so switching the widgets off actually removes the data rather
///   than orphaning the last copy of it in the container forever.
///
/// This is the trade the requirement asks for and it is worth stating plainly
/// rather than discovering later: a user who wants nothing legible outside the
/// encrypted database should leave the widgets off, and the Settings toggle is
/// what makes that a real choice.
class HomeWidgetService {
  HomeWidgetService();

  /// The App Group both the app and the iOS widget extension are members of.
  ///
  /// Must match the `com.apple.security.application-groups` entitlement on both
  /// the Runner and the widget target. If it does not, nothing errors — the
  /// widget simply draws its placeholder forever, which is the single most
  /// common way this feature "works" in development and ships broken.
  static const String appGroupId = 'group.com.karthik.everythingApp';

  /// The two widgets that draw published data, named on each platform.
  ///
  /// Android matches the provider's fully-qualified class; iOS matches the
  /// `kind` string in `StaticConfiguration`. Both are string-matched at the
  /// platform boundary with no compile-time check on either side, so a rename in
  /// Kotlin or Swift silently stops the redraw — which is why they are stated
  /// once here rather than at each call.
  ///
  /// The quick-add widget is deliberately absent: it draws no data, so there is
  /// nothing to reload and waking it would be cost with no effect.
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
  /// Two APIs again, exactly as with the share intent ([ShareService]): a tap on
  /// a cold app and a tap on a running one are different paths, and handling only
  /// the first is why a widget works once and then appears to do nothing.
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
  /// Every key is rewritten on every push. There is no diff here — unlike
  /// `NotificationService.applyPlan`, which must diff because the OS alarm queue
  /// is authoritative state that outlives the app. A widget container is a dumb
  /// key/value store the app is the sole writer of, so the cheapest correct thing
  /// is to overwrite it, and a diff would only be a way for the container to fall
  /// out of step with the database.
  Future<JsonResponse> push(HomeWidgetPayload payload) async {
    try {
      for (final entry in payload.toWidgetData().entries) {
        await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
      }

      await _redraw();

      return JsonResponse.success(message: 'Updated.', data: payload);
    } on Exception {
      // A widget that fails to update is not an error the user can act on and
      // must never surface: the app itself is fine, and the home screen simply
      // keeps showing its last good draw. It is reported, not shown (CLAUDE.md §0).
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not update the home screen widgets.',
      );
    }
  }

  /// [clear] empties the shared container.
  ///
  /// Called when the widgets are switched off, so the data actually leaves the
  /// unencrypted container rather than lingering as the last copy of it. The
  /// redraw afterwards is what makes any widget still on the home screen fall
  /// back to its empty state instead of showing a frozen snapshot of data the
  /// user has just asked the app to stop publishing.
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

  /// The keys [clear] has to erase. Derived from an empty payload so that a field
  /// added to [HomeWidgetPayload.toWidgetData] cannot be left behind here — the
  /// one bug this list would otherwise be guaranteed to grow.
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
