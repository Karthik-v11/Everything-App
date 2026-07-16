package com.karthik.everything_app

import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews

/**
 * The quick-add launcher (Requirement 13).
 *
 * It draws **no data at all**, which is the point: it is four routes into the app,
 * so it never goes stale, never needs a redraw, and — unlike the other two — puts
 * nothing from the encrypted database into the shared container. `HomeWidgetService`
 * deliberately does not include it in its redraw for that reason: there is nothing
 * to redraw.
 */
class QuickAddWidgetProvider : EverythingWidgetProvider() {

    override val layoutId = R.layout.widget_quick_add

    override fun render(context: Context, views: RemoteViews, data: SharedPreferences) {
        openOnTap(context, views, R.id.action_task, "task/new")
        openOnTap(context, views, R.id.action_expense, "transaction/new")
        openOnTap(context, views, R.id.action_ai, "ai")
        openOnTap(context, views, R.id.action_search, "search")
    }
}
