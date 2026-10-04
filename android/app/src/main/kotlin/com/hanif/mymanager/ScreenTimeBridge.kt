package com.hanif.mymanager

import android.app.AppOpsManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Process
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * স্ক্রিন টাইম: UsageStatsManager থেকে অ্যাপ-ভিত্তিক ফোরগ্রাউন্ড সময় পড়ে, আর
 * ব্যাকগ্রাউন্ডে (WorkManager, প্রতি ১৫ মিনিট) অপচয়ের সীমা পেরোলে নোটিফিকেশন দেয়।
 * কনটেন্ট পড়া হয় না, কিছু ফোনের বাইরে যায় না — শুধু "কোন অ্যাপে কত সময়"।
 */
object ScreenTimeBridge {
    private const val CHANNEL = "com.hanif.mymanager/screentime"
    const val PREFS = "screen_time_cfg"
    private const val WORK_NAME = "screen_time_check"

    fun register(engine: FlutterEngine, ctx: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "hasAccess" -> result.success(hasAccess(ctx))
                    "openAccessSettings" -> {
                        startActivity(ctx, Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(true)
                    }
                    "usage" -> {
                        val start = (call.argument<Number>("start") ?: 0).toLong()
                        val end = (call.argument<Number>("end") ?: 0).toLong()
                        result.success(usageList(ctx, start, end))
                    }
                    "saveConfig" -> {
                        val json = call.argument<String>("json") ?: "{}"
                        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("cfg", json).apply()
                        val enabled = try { JSONObject(json).optBoolean("enabled", false) } catch (e: Exception) { false }
                        schedule(ctx, enabled)
                        result.success(true)
                    }
                    "openWellbeing" -> result.success(openWellbeing(ctx))
                    "guardStatus" -> result.success(guardStatus(ctx))
                    "openAccessibilitySettings" -> {
                        startActivity(ctx, Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "openOverlaySettings" -> {
                        startActivity(ctx, Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${ctx.packageName}")))
                        result.success(true)
                    }
                    "openAppNotifications" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        startActivity(ctx, Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, pkg))
                        result.success(true)
                    }
                    "openAppDetails" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        startActivity(ctx, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg")))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ST_ERR", e.message, null)
            }
        }
    }

    /** প্রহরীর অবস্থা: Accessibility সেবা চালু? অন্য অ্যাপের উপরে দেখানোর অনুমতি? আজ কতবার থামানো হলো? */
    private fun guardStatus(ctx: Context): Map<String, Any> {
        val enabledList = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
        val accessibility = enabledList.contains(ctx.packageName + "/") && enabledList.contains("ScreenGuardService")
        val sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val cal = Calendar.getInstance()
        val today = "%04d-%02d-%02d".format(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH))
        val sameDay = sp.getString("guard_day", "") == today
        return mapOf(
            "accessibility" to accessibility,
            "overlay" to Settings.canDrawOverlays(ctx),
            "blocked" to (if (sameDay) sp.getInt("blocked", 0) else 0),
            "graceUsed" to (if (sameDay) sp.getInt("grace_used", 0) else 0),
        )
    }

    private fun startActivity(ctx: Context, i: Intent) {
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(i)
    }

    fun hasAccess(ctx: Context): Boolean {
        val ops = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun schedule(ctx: Context, enabled: Boolean) {
        val wm = WorkManager.getInstance(ctx)
        if (!enabled) {
            wm.cancelUniqueWork(WORK_NAME)
            return
        }
        val req = PeriodicWorkRequestBuilder<ScreenTimeWorker>(15, TimeUnit.MINUTES).build()
        wm.enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, req)
    }

    /** Digital Wellbeing যে ফোনে যেভাবে আছে সেভাবে খোলার চেষ্টা; না পেলে সাধারণ সেটিংস। */
    private fun openWellbeing(ctx: Context): String {
        val candidates = listOf(
            "com.google.android.apps.wellbeing",   // Pixel / স্টক অ্যান্ড্রয়েড
            "com.samsung.android.forest",          // Samsung Digital Wellbeing
        )
        for (p in candidates) {
            val i = ctx.packageManager.getLaunchIntentForPackage(p)
            if (i != null) {
                startActivity(ctx, i)
                return "wellbeing"
            }
        }
        startActivity(ctx, Intent(Settings.ACTION_SETTINGS))
        return "settings"
    }

    private fun skipPackages(ctx: Context): Set<String> {
        val skip = hashSetOf("com.android.systemui")
        try {
            val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            for (ri in ctx.packageManager.queryIntentActivities(home, 0)) skip.add(ri.activityInfo.packageName)
        } catch (e: Exception) {
        }
        return skip
    }

    /** [start, end) সীমায় প্রতিটা প্যাকেজের ফোরগ্রাউন্ড সময় (মিলিসেকেন্ড)। */
    fun usageMap(ctx: Context, start: Long, end: Long): Map<String, Long> {
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = usm.queryEvents(start, end)
        val e = UsageEvents.Event()
        val total = HashMap<String, Long>()
        val since = HashMap<String, Long>()
        val count = HashMap<String, Int>()

        fun add(p: String, ms: Long) {
            if (ms > 0) total[p] = (total[p] ?: 0L) + ms
        }

        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            val p = e.packageName ?: continue
            when (e.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    val c = count[p] ?: 0
                    if (c == 0) since[p] = e.timeStamp
                    count[p] = c + 1
                }
                UsageEvents.Event.ACTIVITY_PAUSED -> {
                    val c = (count[p] ?: 0) - 1
                    if (c <= 0) {
                        val s = since.remove(p)
                        if (s != null) add(p, e.timeStamp - s)
                        count[p] = 0
                    } else {
                        count[p] = c
                    }
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE, UsageEvents.Event.KEYGUARD_SHOWN -> {
                    for ((pp, s) in since) add(pp, e.timeStamp - s)
                    since.clear()
                    count.clear()
                }
            }
        }
        val cap = minOf(end, System.currentTimeMillis())
        for ((p, s) in since) add(p, cap - s)

        val skip = skipPackages(ctx)
        return total.filterKeys { it !in skip }
    }

    private fun label(ctx: Context, pkg: String): String = try {
        val pm = ctx.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        pkg
    }

    private fun usageList(ctx: Context, start: Long, end: Long): List<Map<String, Any>> {
        return usageMap(ctx, start, end)
            .filter { it.value >= 30_000L } // আধা মিনিটের কমকে বাদ
            .map { mapOf<String, Any>("package" to it.key, "label" to label(ctx, it.key), "ms" to it.value) }
            .sortedByDescending { it["ms"] as Long }
    }

    // ───────────── নোটিফিকেশন ─────────────

    private val BN = charArrayOf('০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯')
    fun bn(n: Long): String = n.toString().map { if (it in '0'..'9') BN[it - '0'] else it }.joinToString("")

    fun dur(ms: Long): String {
        val m = ms / 60_000
        val h = m / 60
        val r = m % 60
        return when {
            h > 0 && r > 0 -> "${bn(h)} ঘণ্টা ${bn(r)} মিনিট"
            h > 0 -> "${bn(h)} ঘণ্টা"
            else -> "${bn(m)} মিনিট"
        }
    }

    fun notify(ctx: Context, id: Int, title: String, body: String) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val ch = NotificationChannel("screen_time_channel", "স্ক্রিন টাইম সতর্কবার্তা", NotificationManager.IMPORTANCE_DEFAULT)
        nm.createNotificationChannel(ch)
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        val pi = PendingIntent.getActivity(ctx, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = NotificationCompat.Builder(ctx, "screen_time_channel")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build()
        nm.notify(id, n)
    }

    /**
     * Dart থেকে আসা কনফিগ (সীমা + কোন প্যাকেজ অপচয়/পড়াশোনা) দেখে সতর্কবার্তা দেয়।
     *  • অপচয় সীমা ছুঁলে একবার, ১.৫ গুণ হলে আরেকবার (দিনে সর্বোচ্চ ২ বার)
     *  • সন্ধ্যা ৬টার পর পড়া লক্ষ্যের অর্ধেকের কম হলে একবার
     */
    fun checkAndNotify(ctx: Context) {
        val sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val cfgText = sp.getString("cfg", null) ?: return
        val cfg = JSONObject(cfgText)
        if (!cfg.optBoolean("enabled", false) || !hasAccess(ctx)) return

        val cal = Calendar.getInstance()
        val dayKey = "%04d-%02d-%02d".format(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH))
        cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0); cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
        val dayStart = cal.timeInMillis
        val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)

        val usage = usageMap(ctx, dayStart, System.currentTimeMillis())
        fun sumOf(key: String): Long {
            val arr = cfg.optJSONArray(key) ?: return 0
            var s = 0L
            for (i in 0 until arr.length()) s += usage[arr.getString(i)] ?: 0L
            return s
        }
        val wasteMs = sumOf("waste")
        var studyMs = sumOf("study")
        val manual = cfg.optJSONObject("manual")
        if (manual != null && manual.optString("day") == dayKey) studyMs += manual.optLong("min", 0) * 60_000

        val limitMs = cfg.optLong("limitMin", 120) * 60_000
        val goalMs = cfg.optLong("studyGoalMin", 180) * 60_000

        if (sp.getString("state_day", "") != dayKey) {
            sp.edit().putString("state_day", dayKey).putInt("waste_level", 0).putBoolean("study_nudged", false).apply()
        }
        val level = sp.getInt("waste_level", 0)
        val newLevel = when {
            limitMs > 0 && wasteMs >= limitMs * 3 / 2 -> 2
            limitMs > 0 && wasteMs >= limitMs -> 1
            else -> 0
        }
        if (newLevel > level) {
            val body = if (newLevel == 1)
                "আজ ফেসবুক-ইউটিউব-গেম মিলিয়ে ${dur(wasteMs)} গেছে (সীমা ${dur(limitMs)})। পড়া: ${dur(studyMs)}। এবার ফোন রেখে বই ধরো 📚"
            else
                "অপচয়ের সময় ${dur(wasteMs)} ছাড়িয়ে গেছে! আজ পড়া মাত্র ${dur(studyMs)}। এখনই ২৫ মিনিট পড়তে বসো ⏳"
            notify(ctx, 7101, if (newLevel == 1) "⚠️ অপচয়ের সীমা পেরিয়েছে" else "🚨 সময় নষ্ট হচ্ছে", body)
            sp.edit().putInt("waste_level", newLevel).apply()
        }

        if (hour >= 18 && goalMs > 0 && studyMs < goalMs / 2 && !sp.getBoolean("study_nudged", false)) {
            notify(ctx, 7102, "📚 আজ পড়া কম হয়েছে",
                "আজ এখন পর্যন্ত পড়া ${dur(studyMs)} (লক্ষ্য ${dur(goalMs)})। রাতে অন্তত ${dur(goalMs / 2)} পূরণ করো।")
            sp.edit().putBoolean("study_nudged", true).apply()
        }
    }
}

class ScreenTimeWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    override fun doWork(): Result {
        try {
            ScreenTimeBridge.checkAndNotify(applicationContext)
        } catch (e: Exception) {
            // সতর্কবার্তার ত্রুটি যেন কাজ আটকে না রাখে
        }
        return Result.success()
    }
}
