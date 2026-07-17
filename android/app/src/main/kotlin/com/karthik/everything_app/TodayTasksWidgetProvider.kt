package com.karthik.everything_app

import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray

/**
 * Today's tasks on the home screen (Requirement 13).
 *
 * The rows are **static `TextView`s, not a `ListView`**. A collection widget needs
 * a `RemoteViewsService` plus a `RemoteViewsFactory`, bound through a separate
 * manifest entry, to scroll a list nobody scrolls — this widget shows at most four
 * things. Four pre-declared rows shown and hidden is a fraction of the code and
 * has no service to keep alive.
 *
 * The task list arrives as one JSON string rather than as `task_0_title`,
 * `task_1_title`, … precisely so that shrinking from four tasks to two cannot
 * leave rows three and four behind: the whole key is rewritten each publish, so it
 * cannot go stale in part. See `HomeWidgetPayload.toWidgetData`.
 */
class TodayTasksWidgetProvider : EverythingWidgetProvider() {

    override val layoutId = R.layout.widget_today_tasks

    override fun render(context: Context, views: RemoteViews, data: SharedPreferences) {
        val openCount = data.getString("openCount", null)?.toIntOrNull() ?: 0
        val overdueCount = data.getString("overdueCount", null)?.toIntOrNull() ?: 0
        val updatedAt = data.getString("updatedAtLabel", null).orEmpty()

        views.setTextViewText(
            R.id.widget_title,
            when {
                openCount == 0 -> "Nothing due today"
                openCount == 1 -> "1 task today"
                else -> "$openCount tasks today"
            },
        )

        // The overdue count is the one number here worth interrupting for, so it
        // only appears when there is one — a permanent "0 overdue" is a line that
        // teaches the eye to skip the row it lives in.
        views.setTextViewText(R.id.widget_overdue, "$overdueCount overdue")
        views.setViewVisibility(
            R.id.widget_overdue,
            if (overdueCount > 0) View.VISIBLE else View.GONE,
        )

        views.setTextViewText(R.id.widget_updated, updatedAt)

        renderRows(context, views, parseTasks(data.getString("tasks", null)))

        openOnTap(context, views, R.id.widget_add, "task/new")
    }

    private fun renderRows(context: Context, views: RemoteViews, tasks: List<Task>) {
        rowIds.forEachIndexed { index, rowId ->
            val task = tasks.getOrNull(index)

            if (task == null) {
                views.setViewVisibility(rowId.container, View.GONE)
                return@forEachIndexed
            }

            views.setViewVisibility(rowId.container, View.VISIBLE)
            views.setTextViewText(rowId.title, task.title)
            views.setTextViewText(rowId.due, task.dueLabel)
            views.setViewVisibility(
                rowId.due,
                if (task.dueLabel.isEmpty()) View.GONE else View.VISIBLE,
            )

            // "Overdue" in the dim colour reads as a timestamp; it is the one due
            // label that is not one.
            views.setTextColor(
                rowId.due,
                context.getColor(
                    if (task.isOverdue) R.color.widget_overdue else R.color.widget_text_dim,
                ),
            )

            val priority = Priority.of(task.priority)
            views.setImageViewResource(rowId.marker, priority.marker)
            // The marker's colour is the only thing carrying priority, which makes
            // it invisible to a screen reader and to anyone who cannot separate
            // four hues. The label is what the row says instead.
            views.setContentDescription(rowId.marker, context.getString(priority.label))
        }

        val empty = tasks.isEmpty()
        views.setViewVisibility(R.id.widget_empty, if (empty) View.VISIBLE else View.GONE)
    }

    /**
     * Reads the published list. A malformed blob draws an empty widget rather than
     * crashing the launcher's process — which is what an uncaught throw here would
     * do, and it would take every other widget on the home screen down with it.
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

    private data class RowIds(
        val container: Int,
        val marker: Int,
        val title: Int,
        val due: Int,
    )

    private val rowIds = listOf(
        RowIds(R.id.row_0, R.id.row_0_marker, R.id.row_0_title, R.id.row_0_due),
        RowIds(R.id.row_1, R.id.row_1_marker, R.id.row_1_title, R.id.row_1_due),
        RowIds(R.id.row_2, R.id.row_2_marker, R.id.row_2_title, R.id.row_2_due),
        RowIds(R.id.row_3, R.id.row_3_marker, R.id.row_3_title, R.id.row_3_due),
    )
}
