package com.karthik.everything_app

import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews

/**
 * This month's spending on the home screen (Requirement 13).
 *
 * Both strings are drawn exactly as Dart published them. The amount is already
 * formatted by `Helpers.formatMoney` and the caption already names the month —
 * there is no `NumberFormat` here and there must not be one, or the home screen
 * would eventually round a lakh differently from the Finance tab.
 */
class FinanceWidgetProvider : EverythingWidgetProvider() {

    override val layoutId = R.layout.widget_finance

    override fun render(context: Context, views: RemoteViews, data: SharedPreferences) {
        // The em dash rather than "₹0": a widget placed before the app has ever
        // published says it has nothing to show, instead of asserting that nothing
        // has been spent this month.
        views.setTextViewText(
            R.id.widget_amount,
            data.getString("spentLabel", null).orEmpty().ifEmpty { "—" },
        )
        views.setTextViewText(
            R.id.widget_caption,
            data.getString("spentCaption", null).orEmpty().ifEmpty { "Spending" },
        )

        // No "updated at" here: at 2x1 the layout has no room for a footer, so the
        // view it was written to no longer exists. `updatedAtLabel` is still
        // published — the tasks widget draws it.

        openOnTap(context, views, R.id.widget_add, "transaction/new")
    }
}
