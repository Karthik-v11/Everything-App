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

        renderRows(views, parseTasks(data.getString("tasks", null)))

        openOnTap(context, views, R.id.widget_add, "task/new")
    }

    private fun renderRows(views: RemoteViews, tasks: List<Task>) {
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

            views.setImageViewResource(
                rowId.marker,
                if (task.isCompleted) R.drawable.widget_check_done
                else R.drawable.widget_check_open,
            )
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
                    isCompleted = item.optBoolean("isCompleted"),
                )
            }
        } catch (error: Exception) {
            emptyList()
        }
    }

    private data class Task(
        val title: String,
        val dueLabel: String,
        val isCompleted: Boolean,
    )

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
