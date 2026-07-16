package com.karthik.everything_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Base for every home screen widget (Requirement 13).
 *
 * ## What this can and cannot do
 *
 * A widget runs in the launcher's process, not the app's. It has **no** access to
 * the SQLCipher database — it has no key, and Phase 2 went to some trouble to make
 * sure of that — so everything drawn here comes from the `SharedPreferences` the
 * Dart side wrote through `home_widget` (see `HomeWidgetService`).
 *
 * That has a consequence worth being explicit about: **this code cannot refresh
 * data, only redraw it.** `updatePeriodMillis` in each widget's XML brings us back
 * every 30 minutes, and all we can do then is re-render whatever the app last
 * published. Recomputing "today's tasks" against a new day needs the database, and
 * the database needs the app. In practice the app republishes on every write
 * (`HomeWidgetBloc` watches the same DAO streams the screens do), so the widget is
 * current the moment anything changes and goes at most one app-open stale.
 *
 * No formatting happens here either. Amounts arrive pre-formatted from Dart
 * (`Helpers.formatMoney`), because a second implementation of the `en_IN`
 * lakh/crore grouping in Kotlin — and a third in Swift — is three chances for the
 * home screen to disagree with the Finance tab about what the month cost.
 */
abstract class EverythingWidgetProvider : AppWidgetProvider() {

    /** The layout this widget draws into. */
    abstract val layoutId: Int

    /** Fills [views] from the data the app published. */
    abstract fun render(context: Context, views: RemoteViews, data: SharedPreferences)

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val data = HomeWidgetPlugin.getData(context)

        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, layoutId)

            render(context, views, data)

            // Tapping anywhere opens the app. Set on the root of every widget so
            // a tap that misses a button is still a tap that does the obvious
            // thing rather than nothing.
            views.setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("everything://widget"),
                ),
            )

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /**
     * Opens the app at [route] when [viewId] is tapped.
     *
     * The URI is read on the Dart side by the deep-link handler; a widget button
     * that opened the Dashboard and left the user to navigate would be slower than
     * not having the button.
     */
    protected fun openOnTap(
        context: Context,
        views: RemoteViews,
        viewId: Int,
        route: String,
    ) {
        views.setOnClickPendingIntent(
            viewId,
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("everything://$route"),
            ),
        )
    }
}
