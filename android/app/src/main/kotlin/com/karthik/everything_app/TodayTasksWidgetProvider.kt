package com.karthik.everything_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * Today's tasks on the home screen (Requirement 13).
 *
 * The rows are a **collection**, bound through [TodayTasksWidgetService]. They
 * used to be four static rows in the layout, which is cheaper but cannot scroll:
 * the launcher lays a `LinearLayout` out into whatever height the user resized
 * the widget to and clips the overflow, so a two-cell-tall widget holding four
 * tasks drew three and part of a fourth with no way to reach it. Only an
 * adapter-backed `ListView` scrolls inside a widget, and an adapter inside a
 * widget means a `RemoteViewsService`.
 *
 * The task list arrives as one JSON string rather than as `task_0_title`,
 * `task_1_title`, … precisely so that shrinking from four tasks to two cannot
 * leave rows three and four behind: the whole key is rewritten each publish, so
 * it cannot go stale in part. See `HomeWidgetPayload.toWidgetData`.
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

        bindList(context, views)

        openOnTap(context, views, R.id.widget_add, "task/new")
    }

    /**
     * Points the list at [TodayTasksWidgetService] and gives its rows somewhere
     * to go.
     *
     * The service intent carries no widget id, so every placement of this widget
     * shares one factory. That is deliberate: the factory reads the single
     * published list and there is nothing per-placement to tell them apart.
     */
    private fun bindList(context: Context, views: RemoteViews) {
        views.setRemoteAdapter(
            R.id.widget_task_list,
            Intent(context, TodayTasksWidgetService::class.java),
        )

        // Shown by the launcher whenever the adapter reports zero rows, so
        // "nothing due" needs no branch here.
        views.setEmptyView(R.id.widget_task_list, R.id.widget_empty)

        // A row's own click is a fill-in intent against this template — see
        // TodayTasksRemoteViewsFactory.getViewAt. Without a template the rows are
        // inert: a collection item cannot inherit the widget root's handler, so
        // the one place on this widget a tap is most likely to land would be the
        // one place that did nothing.
        views.setPendingIntentTemplate(
            R.id.widget_task_list,
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("everything://tasks"),
            ),
        )
    }

    /**
     * Tells the launcher to re-ask the factory for rows.
     *
     * `updateAppWidget` alone redraws the frame around the list and leaves the
     * list holding whatever it last fetched, so without this a publish would
     * update the header's count and not the tasks under it.
     */
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)

        appWidgetManager.notifyAppWidgetViewDataChanged(
            appWidgetIds,
            R.id.widget_task_list,
        )
    }
}
