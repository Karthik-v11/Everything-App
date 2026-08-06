package com.karthik.everything_app

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

/**
 * Binds the tasks widget's scrolling list (Requirement 13).
 *
 * The launcher cannot scroll a `LinearLayout` of pre-declared rows — it lays
 * them out into the widget's actual height and clips whatever does not fit. A
 * `ListView` inside a widget is only fillable through a `RemoteViewsService`,
 * which is what this is: the launcher binds to it across processes and asks for
 * one row at a time.
 *
 * Like every other widget class here it runs with no Flutter engine and no
 * SQLCipher key, so its only source is the `SharedPreferences` the app published
 * through `home_widget`. See `EverythingWidgetProvider`.
 */
class TodayTasksWidgetService : RemoteViewsService() {

    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        TodayTasksRemoteViewsFactory(applicationContext)
}

private class TodayTasksRemoteViewsFactory(
    private val context: Context,
) : RemoteViewsService.RemoteViewsFactory {

    /**
     * The published list, re-read on every [onDataSetChanged].
     *
     * Held rather than re-parsed per row: [getViewAt] is called once per visible
     * row and again on every scroll, and the launcher guarantees it does not run
     * concurrently with [onDataSetChanged].
     */
    private var tasks: List<Task> = emptyList()

    override fun onCreate() = Unit

    /**
     * Called by the launcher on bind and whenever the provider calls
     * `notifyAppWidgetViewDataChanged`, which is every publish.
     */
    override fun onDataSetChanged() {
        tasks = parseTasks(HomeWidgetPlugin.getData(context).getString("tasks", null))
    }

    override fun onDestroy() {
        tasks = emptyList()
    }

    override fun getCount() = tasks.size

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_task_row)

        // The launcher can ask for a position the list no longer has, between a
        // publish and the redraw that follows it. An empty row is a frame of
        // nothing; an index out of bounds takes the launcher's process down.
        val task = tasks.getOrNull(position) ?: return views

        views.setTextViewText(R.id.row_title, task.title)
        views.setTextViewText(R.id.row_due, task.dueLabel)
        views.setViewVisibility(
            R.id.row_due,
            if (task.dueLabel.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE,
        )

        // "Overdue" in the dim colour reads as a timestamp; it is the one due
        // label that is not one.
        views.setTextColor(
            R.id.row_due,
            context.getColor(
                if (task.isOverdue) R.color.widget_overdue else R.color.widget_text_dim,
            ),
        )

        val priority = Priority.of(task.priority)
        views.setImageViewResource(R.id.row_marker, priority.marker)
        // The marker's colour is the only thing carrying priority, which makes
        // it invisible to a screen reader and to anyone who cannot separate four
        // hues. The label is what the row says instead.
        views.setContentDescription(R.id.row_marker, context.getString(priority.label))

        // A collection item does not inherit the widget root's click handler, so
        // without this a row is dead to the touch. The intent is empty because
        // every row goes to the same place — the template in
        // TodayTasksWidgetProvider carries the destination.
        views.setOnClickFillInIntent(R.id.row_root, Intent())

        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount() = 1

    override fun getItemId(position: Int) = position.toLong()

    override fun hasStableIds() = true

    /**
     * Reads the published list. A malformed blob draws an empty list rather than
     * throwing — which here would kill the launcher's process, taking every other
     * widget on the home screen with it.
     */
    private fun parseTasks(raw: String?): List<Task> {
        if (raw.isNullOrEmpty()) return emptyList()

        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { index ->
                val item = array.optJSONObject(index) ?: return@mapNotNull null
                Task(
                    title = item.optString("title"),
                    dueLabel = item.optString("dueLabel"),
                    isOverdue = item.optBoolean("isOverdue"),
                    priority = item.optString("priority"),
                )
            }
        } catch (error: Exception) {
            emptyList()
        }
    }

    private data class Task(
        val title: String,
        val dueLabel: String,
        val isOverdue: Boolean,
        val priority: String,
    )

    /**
     * The published priority name mapped to what draws it.
     *
     * The names are `TaskPriority`'s enum names, matched as strings across the
     * process boundary with nothing to check them at compile time — so an
     * unrecognised one falls back to [MEDIUM] rather than throwing, which is also
     * what happens to a widget left over from a build before priority was
     * published. `Task.priority` defaults to medium in Dart too, so the fallback
     * agrees with the app.
     */
    private enum class Priority(
        val key: String,
        val marker: Int,
        val label: Int,
    ) {
        LOW("low", R.drawable.widget_check_low, R.string.widget_priority_low),
        MEDIUM("medium", R.drawable.widget_check_medium, R.string.widget_priority_medium),
        HIGH("high", R.drawable.widget_check_high, R.string.widget_priority_high),
        CRITICAL("critical", R.drawable.widget_check_critical, R.string.widget_priority_critical);

        companion object {
            fun of(key: String): Priority = entries.firstOrNull { it.key == key } ?: MEDIUM
        }
    }
}
