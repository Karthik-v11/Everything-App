import SwiftUI
import WidgetKit

// The iOS home screen widgets (Requirement 13).
//
// A WidgetKit extension is a separate process with no Flutter engine and no
// access to the SQLCipher database — it has no key, which is the whole point of
// Phase 2. Everything drawn here comes out of the App Group's UserDefaults, where
// the app published it through `home_widget` (see HomeWidgetService.swift's
// counterpart in Dart, `HomeWidgetService`).
//
// Nothing here formats anything. The amount arrives as a finished string from
// `Helpers.formatMoney`, because a NumberFormatter here — and its twin in Kotlin —
// would be three implementations of the same `en_IN` grouping rule and three
// chances for the home screen to disagree with the Finance tab.

// MARK: - Shared container

/// The App Group both the app and this extension are members of.
///
/// Must match `Runner.entitlements`, `EverythingWidget.entitlements`, and
/// `HomeWidgetService.appGroupId` in Dart. A mismatch does not error: the widget
/// draws its placeholder forever, which is the most common way this feature ships
/// broken.
private let appGroupId = "group.com.karthik.everythingApp"

/// Reads a value the app published.
///
/// The key is **bare** — `home_widget` does `setValue(data, forKey: id)` with no
/// prefix at all (`HomeWidgetPlugin.swift`), and the Android side does the same
/// into `HomeWidgetPreferences`. A prefix here would return nil for every key and
/// the widget would draw its empty state forever, with nothing anywhere reporting
/// an error.
///
/// Everything is stored as a String because `HomeWidgetPayload.toWidgetData`
/// sends strings — including the counts, which is why `readInt` parses rather
/// than calling `integer(forKey:)`.
private func readString(_ key: String) -> String? {
    UserDefaults(suiteName: appGroupId)?.string(forKey: key)
}

private func readInt(_ key: String) -> Int {
    Int(readString(key) ?? "") ?? 0
}

// MARK: - Model

struct WidgetTask: Identifiable {
    let id: String
    let title: String
    let dueLabel: String
    let isCompleted: Bool
    let isOverdue: Bool
}

struct EverythingEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTask]
    let openCount: Int
    let overdueCount: Int
    let spentLabel: String
    let spentCaption: String
    let updatedAtLabel: String

    /// What a widget shows before the app has ever published — in the gallery
    /// preview, and on a device where the widget was placed first. It is sample
    /// data rather than an empty state, because an empty card in the widget
    /// gallery tells the user nothing about what they are about to add.
    static let placeholder = EverythingEntry(
        date: Date(),
        tasks: [
            WidgetTask(id: "1", title: "Pay rent", dueLabel: "5:00 PM",
                       isCompleted: false, isOverdue: false),
            WidgetTask(id: "2", title: "Book flights", dueLabel: "",
                       isCompleted: false, isOverdue: false),
        ],
        openCount: 2,
        overdueCount: 0,
        spentLabel: "₹15,000",
        spentCaption: "Spent in July",
        updatedAtLabel: ""
    )

    /// Reads what the app last published.
    static func current() -> EverythingEntry {
        EverythingEntry(
            date: Date(),
            tasks: decodeTasks(readString("tasks")),
            openCount: readInt("openCount"),
            overdueCount: readInt("overdueCount"),
            spentLabel: readString("spentLabel") ?? "",
            spentCaption: readString("spentCaption") ?? "",
            updatedAtLabel: readString("updatedAtLabel") ?? ""
        )
    }

    /// The task list travels as one JSON string so it cannot go stale in part —
    /// see `HomeWidgetPayload.toWidgetData`. A malformed blob draws an empty
    /// widget rather than trapping.
    private static func decodeTasks(_ raw: String?) -> [WidgetTask] {
        guard let raw, let data = raw.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  let title = item["title"] as? String
            else { return nil }

            return WidgetTask(
                id: id,
                title: title,
                dueLabel: item["dueLabel"] as? String ?? "",
                isCompleted: item["isCompleted"] as? Bool ?? false,
                isOverdue: item["isOverdue"] as? Bool ?? false
            )
        }
    }
}

// MARK: - Timeline

struct EverythingProvider: TimelineProvider {
    func placeholder(in context: Context) -> EverythingEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (EverythingEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .current())
    }

    /// One entry, refreshed in 30 minutes (Requirement 13).
    ///
    /// A single entry rather than a series, because WidgetKit's timeline model
    /// assumes the app can predict the future and this app cannot: the next
    /// change is a task the user has not typed yet. So there is nothing to
    /// pre-compute — the app calls `HomeWidget.updateWidget` on every write (see
    /// `HomeWidgetBloc`), which reloads this immediately, and the 30-minute policy
    /// is only the backstop for the case where the app has not run at all.
    func getTimeline(in context: Context, completion: @escaping (Timeline<EverythingEntry>) -> Void) {
        let entry = EverythingEntry.current()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date)!

        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Theme

// The app's palette (docs/plan.md §4), restated because a widget process has no
// Flutter engine to ask. The accent is fixed rather than following the user's
// chosen accent: the app would have to republish on every accent change, and this
// is right for almost every install.
private extension Color {
    static let widgetCard = Color(red: 0.11, green: 0.11, blue: 0.11)
    static let widgetAccent = Color(red: 1.0, green: 0.70, blue: 0.0)
    static let widgetText = Color(white: 0.96)
    static let widgetDim = Color(white: 0.62)
    static let widgetOverdue = Color(red: 0.90, green: 0.22, blue: 0.21)
}

// MARK: - Views

struct TodayTasksView: View {
    var entry: EverythingEntry
    @Environment(\.widgetFamily) private var family

    /// Small shows three rows, medium four, large eight. The app publishes the
    /// longest list once and each size takes what it has room for, which is why
    /// `HomeWidgetPayload.maxTasks` is 8 rather than per-size.
    private var rowLimit: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 4
        default: return 8
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.widgetText)
                Spacer()
                if entry.overdueCount > 0 {
                    Text("\(entry.overdueCount) overdue")
                        .font(.system(size: 11))
                        .foregroundColor(.widgetOverdue)
                }
            }

            if entry.tasks.isEmpty {
                Text("Nothing due. Tap to add something.")
                    .font(.system(size: 12))
                    .foregroundColor(.widgetDim)
            } else {
                ForEach(entry.tasks.prefix(rowLimit)) { task in
                    HStack(spacing: 8) {
                        Circle()
                            .strokeBorder(
                                task.isCompleted ? Color.clear : Color.widgetDim,
                                lineWidth: 1.5
                            )
                            .background(
                                Circle().fill(
                                    task.isCompleted ? Color.widgetAccent : Color.clear
                                )
                            )
                            .frame(width: 10, height: 10)

                        // strikethrough is called on Text, before lineLimit.
                        // Text has its own overload from iOS 13; the View-level
                        // one is iOS 16+, and lineLimit returns `some View` — so
                        // reordering these two lines silently raises the
                        // deployment target this file needs.
                        Text(task.title)
                            .strikethrough(task.isCompleted, color: .widgetDim)
                            .font(.system(size: 12))
                            .foregroundColor(.widgetText)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if !task.dueLabel.isEmpty {
                            Text(task.dueLabel)
                                .font(.system(size: 10))
                                .foregroundColor(
                                    task.isOverdue ? .widgetOverdue : .widgetDim
                                )
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .widgetURL(URL(string: "everything://tasks"))
    }

    private var headline: String {
        switch entry.openCount {
        case 0: return "Nothing due today"
        case 1: return "1 task today"
        default: return "\(entry.openCount) tasks today"
        }
    }
}

struct FinanceView: View {
    var entry: EverythingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.spentCaption.isEmpty ? "Spending" : entry.spentCaption)
                .font(.system(size: 11))
                .foregroundColor(.widgetDim)

            Spacer(minLength: 0)

            // The em dash rather than "₹0": a widget placed before the app has
            // published says it has nothing to show, rather than asserting that
            // nothing has been spent.
            Text(entry.spentLabel.isEmpty ? "—" : entry.spentLabel)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.widgetText)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Spacer(minLength: 0)

            if !entry.updatedAtLabel.isEmpty {
                Text(entry.updatedAtLabel)
                    .font(.system(size: 9))
                    .foregroundColor(.widgetDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .widgetURL(URL(string: "everything://finance"))
    }
}

struct QuickAddView: View {
    private let actions: [(String, String)] = [
        ("Task", "task/new"),
        ("Expense", "transaction/new"),
        ("Ask", "ai"),
        ("Search", "search"),
    ]

    var body: some View {
        // Each pill is its own Link rather than one widgetURL, because the point
        // of this widget is landing on the right screen in one tap.
        HStack(spacing: 6) {
            ForEach(actions, id: \.0) { action in
                Link(destination: URL(string: "everything://\(action.1)")!) {
                    Text(action.0)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(action.0 == "Ask" ? .widgetAccent : .widgetText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(10)
    }
}

// MARK: - Widgets

/// Applies the app's card colour as the widget background.
///
/// `containerBackground` is **required** on iOS 17+ — a widget without it is not
/// merely unstyled, it fails to render on the Home Screen — and does not exist
/// before it, hence the availability check rather than an unconditional modifier.
private extension View {
    @ViewBuilder
    func widgetCardBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(Color.widgetCard, for: .widget)
        } else {
            background(Color.widgetCard)
        }
    }
}

struct TodayTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EverythingWidget", provider: EverythingProvider()) { entry in
            TodayTasksView(entry: entry).widgetCardBackground()
        }
        .configurationDisplayName("Today")
        .description("Today's tasks and what's overdue.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct FinanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EverythingFinanceWidget", provider: EverythingProvider()) { entry in
            FinanceView(entry: entry).widgetCardBackground()
        }
        .configurationDisplayName("Spending")
        .description("What you've spent this month.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EverythingQuickAddWidget", provider: EverythingProvider()) { _ in
            QuickAddView().widgetCardBackground()
        }
        .configurationDisplayName("Quick add")
        .description("Add a task or expense, ask, or search.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct EverythingWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayTasksWidget()
        FinanceWidget()
        QuickAddWidget()
    }
}
