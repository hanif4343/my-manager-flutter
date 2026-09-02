package com.hanif.mymanager

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// Renders the "today's overview" home screen widget from data saved by
/// WidgetService.update() on the Dart side (see lib/services/widget_service.dart).
/// Tapping anywhere on the widget opens the app.
class MyManagerWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.my_manager_widget).apply {
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                val pending = widgetData.getString("pending_count", "0") ?: "0"
                val overdue = widgetData.getString("overdue_count", "0") ?: "0"

                val summary = if (overdue != "0") {
                    "$pending টা বাকি · $overdue টা overdue"
                } else {
                    "$pending টা বাকি"
                }
                setTextViewText(R.id.widget_summary, summary)

                bindIdeaLine(this, widgetData, "idea_1", R.id.widget_idea_1)
                bindIdeaLine(this, widgetData, "idea_2", R.id.widget_idea_2)
                bindIdeaLine(this, widgetData, "idea_3", R.id.widget_idea_3)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun bindIdeaLine(
        views: RemoteViews,
        widgetData: SharedPreferences,
        key: String,
        viewId: Int
    ) {
        val text = widgetData.getString(key, "") ?: ""
        if (text.isEmpty()) {
            views.setViewVisibility(viewId, View.GONE)
        } else {
            views.setViewVisibility(viewId, View.VISIBLE)
            views.setTextViewText(viewId, "• $text")
        }
    }
}
