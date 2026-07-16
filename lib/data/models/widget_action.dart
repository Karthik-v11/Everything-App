/// [WidgetAction] is what tapping a home screen widget does (Requirement 13).
///
/// The native side hands over an `everything://<path>` URI — Android as the launch
/// intent's data, iOS through `widgetURL` / `Link`. This enum is the closed set of
/// paths the app answers to, so a URI that does not match one of them opens the
/// app and nothing else, rather than being interpreted loosely.
///
/// That matters more than it looks: on iOS the custom scheme is registered in
/// `Info.plist`, which means **any** app on the device can open
/// `everything://something`. Parsing it as a closed set of navigation targets —
/// never as data, never as an id to look up, never as anything that writes — is
/// what keeps that from being an entry point. Every action here opens a screen the
/// user could have reached by tapping the app icon and navigating.
enum WidgetAction {
  /// Open the task sheet, ready for a new task.
  addTask('task/new'),

  /// Open the transaction sheet, ready for a new expense.
  addTransaction('transaction/new'),

  /// Open the AI assistant sheet.
  assistant('ai'),

  /// Open Global Search.
  search('search'),

  /// Open the Tasks tab.
  tasks('tasks'),

  /// Open the Finance tab.
  finance('finance');

  const WidgetAction(this.path);

  /// The path in `everything://<path>`.
  final String path;

  /// [fromUri] reads a tap into an action, or null if it is not one.
  ///
  /// The path is taken from `host + path` because `everything://ai` parses with
  /// `ai` as the *host* and an empty path, while `everything://task/new` parses
  /// with `task` as the host and `/new` as the path — a URI quirk that would
  /// otherwise make single-segment actions silently unmatchable.
  static WidgetAction? fromUri(Uri? uri) {
    if (uri == null) return null;

    final combined = '${uri.host}${uri.path}';
    for (final action in WidgetAction.values) {
      if (action.path == combined) return action;
    }
    return null;
  }
}
