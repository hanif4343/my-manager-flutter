package com.hanif.mymanager

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * স্ক্রিন প্রহরী: অপচয়ের অ্যাপ (ফেসবুক, ইউটিউব, গেম...) খোলা হলে — যদি আজকের অপচয়ের সীমা
 * পেরিয়ে থাকে বা এখন "পড়ার সময়" হয় — সামনে "থামো" স্ক্রিন (StopActivity) তোলে।
 *
 * AccessibilityService শুধু "কোন অ্যাপের উইন্ডো সামনে এলো" সেই খবর নেয় (canRetrieveWindowContent=false)
 * — স্ক্রিনের লেখা/বিষয়বস্তু পড়ে না। ব্যাকগ্রাউন্ডে সারাক্ষণ পোলিং নেই, তাই ব্যাটারি প্রায় লাগে না।
 */
class ScreenGuardService : AccessibilityService() {
    private var lastLaunch = 0L
    private var cacheAt = 0L
    private var cacheWaste = 0L
    private var cacheStudy = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName || pkg == "com.android.systemui") return

        val sp = getSharedPreferences(ScreenTimeBridge.PREFS, Context.MODE_PRIVATE)
        val cfg = try { JSONObject(sp.getString("cfg", null) ?: return) } catch (e: Exception) { return }
        if (!cfg.optBoolean("blockEnabled", false)) return
        val waste = cfg.optJSONArray("waste") ?: return
        if (!contains(waste, pkg)) return

        val now = System.currentTimeMillis()
        if (now - lastLaunch < 2500) return
        if (now < sp.getLong("grace_until", 0L)) return // "মিনিট দরকার" ছাড়পত্র চলছে

        // ── শর্ত ১: এখন পড়ার সময়? ──
        val cal = Calendar.getInstance()
        val minNow = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        var windowText: String? = null
        val windows = cfg.optJSONArray("windows")
        if (windows != null) {
            for (i in 0 until windows.length()) {
                val w = windows.getJSONObject(i)
                val s = w.optInt("s"); val e = w.optInt("e")
                val inside = if (s <= e) minNow in s until e else (minNow >= s || minNow < e)
                if (inside) { windowText = "${hm(s)} – ${hm(e)}"; break }
            }
        }

        // ── আজকের অপচয়/পড়া (২০ সেকেন্ড ক্যাশ) ──
        if (now - cacheAt > 20_000) {
            val dayCal = Calendar.getInstance()
            val dayKey = "%04d-%02d-%02d".format(dayCal.get(Calendar.YEAR), dayCal.get(Calendar.MONTH) + 1, dayCal.get(Calendar.DAY_OF_MONTH))
            dayCal.set(Calendar.HOUR_OF_DAY, 0); dayCal.set(Calendar.MINUTE, 0); dayCal.set(Calendar.SECOND, 0); dayCal.set(Calendar.MILLISECOND, 0)
            val usage = try { ScreenTimeBridge.usageMap(this, dayCal.timeInMillis, now) } catch (e: Exception) { emptyMap() }
            cacheWaste = sumOf(cfg.optJSONArray("waste"), usage)
            cacheStudy = sumOf(cfg.optJSONArray("study"), usage)
            val manual = cfg.optJSONObject("manual")
            if (manual != null && manual.optString("day") == dayKey) cacheStudy += manual.optLong("min", 0) * 60_000
            cacheAt = now
        }
        val limitMs = cfg.optLong("limitMin", 120) * 60_000

        // ── শর্ত ২: সীমা পেরিয়েছে? ──
        val overLimit = limitMs > 0 && cacheWaste >= limitMs

        // ── শর্ত ৩: "আগে পড়ো" — আজ ন্যূনতম এতটুকু না পড়লে অপচয়ের অ্যাপ বন্ধ ──
        val studyFirstMs = cfg.optLong("studyFirstMin", 0) * 60_000
        val needStudy = studyFirstMs > 0 && cacheStudy < studyFirstMs

        if (windowText == null && !overLimit && !needStudy) return
        val reasonStr = when {
            windowText != null -> "window"
            needStudy -> "studyfirst"
            else -> "limit"
        }

        // দিনের হিসাব (ছাড়পত্র + কতবার থামানো হলো)
        val today = "%04d-%02d-%02d".format(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH))
        if (sp.getString("guard_day", "") != today) {
            sp.edit().putString("guard_day", today).putInt("grace_used", 0).putInt("blocked", 0).apply()
        }
        sp.edit().putInt("blocked", sp.getInt("blocked", 0) + 1).apply()
        val graceMax = cfg.optInt("graceMax", 2)
        val graceLeft = (graceMax - sp.getInt("grace_used", 0)).coerceAtLeast(0)

        lastLaunch = now
        val i = Intent(this, StopActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NO_ANIMATION)
            putExtra("pkg", pkg)
            putExtra("reason", reasonStr)
            putExtra("need", studyFirstMs)
            putExtra("windowText", windowText ?: "")
            putExtra("waste", cacheWaste)
            putExtra("study", cacheStudy)
            putExtra("limit", limitMs)
            putExtra("goal", cfg.optLong("studyGoalMin", 180) * 60_000)
            putExtra("graceLeft", graceLeft)
            putExtra("graceMin", cfg.optInt("graceMin", 5))
        }
        try { startActivity(i) } catch (e: Exception) { /* Overlay অনুমতি না থাকলে ব্যাকগ্রাউন্ড থেকে খুলতে নাও পারে */ }
    }

    override fun onInterrupt() {}

    private fun contains(a: JSONArray, p: String): Boolean {
        for (i in 0 until a.length()) if (a.optString(i) == p) return true
        return false
    }

    private fun sumOf(a: JSONArray?, usage: Map<String, Long>): Long {
        if (a == null) return 0
        var s = 0L
        for (i in 0 until a.length()) s += usage[a.optString(i)] ?: 0L
        return s
    }

    private fun hm(m: Int): String = "%02d:%02d".format(m / 60, m % 60)
}
