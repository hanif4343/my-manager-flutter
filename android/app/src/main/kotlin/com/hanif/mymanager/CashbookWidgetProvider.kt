package com.hanif.mymanager

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar

/**
 * ক্যাশবুক হোম-স্ক্রিন উইজেট। ডাটা আসে Dart-এর CashbookWidgetService থেকে
 * (home_widget-এর SharedPreferences-এ)।
 *
 *  • ব্যালেন্স ডিফল্টে লুকানো (ক্যাশবুকের লক আছে, হোম স্ক্রিনে সবার সামনে
 *    টাকার অংক না দেখানোই নিরাপদ)। "👁 দেখাও" ট্যাপ করলে অ্যাপ না খুলেই
 *    দেখায়/লুকায়।
 *  • "＋ জমা" / "− খরচ" ট্যাপ করলে অন্য অ্যাপের উপরেই ছোট এন্ট্রি-শিট ওঠে
 *    (CashbookQuickAddActivity), মূল অ্যাপ খুলতে হয় না।
 *  • উপরের নাম/ব্যালেন্সে ট্যাপ করলে মূল অ্যাপ খোলে।
 */
class CashbookWidgetProvider : HomeWidgetProvider() {

    companion object {
        const val ACTION_TOGGLE = "com.hanif.mymanager.CASHBOOK_WIDGET_TOGGLE"
        private const val PREFS = "HomeWidgetPreferences" // home_widget-এর ডিফল্ট ফাইল
        private const val KEY_HIDDEN = "cb_hidden"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val hidden = prefs.getString(KEY_HIDDEN, "1") != "0"
            prefs.edit().putString(KEY_HIDDEN, if (hidden) "0" else "1").apply()
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, CashbookWidgetProvider::class.java))
            onUpdate(context, mgr, ids, prefs)
            return
        }
        super.onReceive(context, intent)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val hidden = widgetData.getString(KEY_HIDDEN, "1") != "0"
        val title = widgetData.getString("cb_title", "") ?: ""
        val balance = widgetData.getString("cb_balance", "") ?: ""
        val income = widgetData.getString("cb_income", "") ?: ""
        val expense = widgetData.getString("cb_expense", "") ?: ""
        val monthKey = widgetData.getString("cb_month_key", "") ?: ""

        // মাস বদলে গেছে অথচ অ্যাপ খোলা হয়নি → পুরোনো সংখ্যা বোঝাতে চিহ্ন।
        val cal = Calendar.getInstance()
        val nowKey = String.format("%04d-%02d", cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1)
        val stale = monthKey.isNotEmpty() && monthKey != nowKey

        val hasData = balance.isNotEmpty()

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.cashbook_widget).apply {
                setTextViewText(
                    R.id.cb_title,
                    if (hasData) "📒 $title${if (stale) " · পুরোনো, অ্যাপ খোলো" else ""}" else "📒 ক্যাশবুক"
                )
                if (!hasData) {
                    setTextViewText(R.id.cb_balance, "অ্যাপ একবার খোলো")
                    setTextViewText(R.id.cb_income, "")
                    setTextViewText(R.id.cb_expense, "")
                    setTextViewText(R.id.cb_eye, "")
                } else if (hidden) {
                    setTextViewText(R.id.cb_balance, "৳ ••••")
                    setTextViewText(R.id.cb_income, "জমা ••••")
                    setTextViewText(R.id.cb_expense, "খরচ ••••")
                    setTextViewText(R.id.cb_eye, "👁 দেখাও")
                } else {
                    setTextViewText(R.id.cb_balance, balance)
                    setTextViewText(R.id.cb_income, "জমা $income")
                    setTextViewText(R.id.cb_expense, "খরচ $expense")
                    setTextViewText(R.id.cb_eye, "🙈 লুকাও")
                }

                val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

                // মূল অ্যাপ খোলা
                val openApp = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.cb_root, openApp)
                setOnClickPendingIntent(R.id.cb_balance, openApp)

                // দেখাও/লুকাও
                val toggle = PendingIntent.getBroadcast(
                    context, 101,
                    Intent(context, CashbookWidgetProvider::class.java).setAction(ACTION_TOGGLE),
                    flags
                )
                setOnClickPendingIntent(R.id.cb_eye, toggle)

                // দ্রুত এন্ট্রি (জমা / খরচ)
                setOnClickPendingIntent(R.id.cb_btn_in, quickAdd(context, "in", 102, flags))
                setOnClickPendingIntent(R.id.cb_btn_out, quickAdd(context, "out", 103, flags))
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun quickAdd(context: Context, type: String, requestCode: Int, flags: Int): PendingIntent {
        val i = Intent(context, CashbookQuickAddActivity::class.java).apply {
            putExtra("type", type)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        }
        return PendingIntent.getActivity(context, requestCode, i, flags)
    }
}
