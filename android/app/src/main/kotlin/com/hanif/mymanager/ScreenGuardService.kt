package com.hanif.mymanager

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.accessibility.AccessibilityEvent
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * স্ক্রিন প্রহরী: অপচয়ের অ্যাপ (ফেসবুক, ইউটিউব, গেম...) সামনে এলে নিয়ম মেলাতে গিয়ে
 * মিললে "থামো" স্ক্রিন (StopActivity) তোলে।
 *
 * নিয়ম (যেকোনো একটা মিললেই থামে; এই ক্রমে দেখা হয়):
 *   ১. এখন "পড়ার সময়"-এর জানালার ভেতরে      → reason = window
 *   ২. আজ ন্যূনতম পড়া ("আগে পড়ো") হয়নি       → reason = studyfirst
 *   ৩. আজকের অপচয় সীমা পেরিয়েছে               → reason = limit
 * ছাড়পত্র ("মিনিট দরকার") চললে কিছুই থামে না।
 *
 * AccessibilityService শুধু "কোন অ্যাপের উইন্ডো সামনে এলো" খবরটা নেয়
 * (canRetrieveWindowContent=false) — স্ক্রিনের লেখা পড়ে না, সারাক্ষণ পোলিংও নেই।
 */
class ScreenGuardService : AccessibilityService() {
    private var lastLaunch = 0L

    // আজকের অপচয়/পড়ার হিসাব — ২০ সেকেন্ড ক্যাশ (প্রতি ইভেন্টে UsageStats ঘাঁটা ভারী)
    private var cacheAt = 0L
    private var cacheWaste = 0L
    private var cacheStudy = 0L

    private class Stop(val reason: String, val windowText: String = "")

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName || pkg == "com.android.systemui") return

        val sp = getSharedPreferences(ScreenTimeBridge.PREFS, Context.MODE_PRIVATE)
        val cfg = try { JSONObject(sp.getString("cfg", null) ?: return) } catch (e: Exception) { return }
        if (!cfg.optBoolean("blockEnabled", false)) return
        if (!has(cfg.optJSONArray("waste"), pkg)) return

        val now = System.currentTimeMillis()
        if (now - lastLaunch < 2500) return                  // একই খোলায় বারবার নয়
        if (now < sp.getLong("grace_until", 0L)) return      // ছাড়পত্র চলছে

        val stop = whyStop(cfg, now) ?: return

        val graceLeft = countBlockAndGraceLeft(sp, cfg)
        lastLaunch = now
        val i = Intent(this, StopActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NO_ANIMATION)
            putExtra("pkg", pkg)
            putExtra("reason", stop.reason)
            putExtra("windowText", stop.windowText)
            putExtra("need", cfg.optLong("studyFirstMin", 0) * 60_000)
            putExtra("waste", cacheWaste)
            putExtra("study", cacheStudy)
            putExtra("limit", cfg.optLong("limitMin", 120) * 60_000)
            putExtra("goal", cfg.optLong("studyGoalMin", 180) * 60_000)
            putExtra("graceLeft", graceLeft)
            putExtra("graceMin", cfg.optInt("graceMin", 5))
        }
        // "অন্য অ্যাপের উপরে দেখানো" অনুমতি না থাকলে ব্যাকগ্রাউন্ড থেকে খুলতে নাও পারে।
        try { startActivity(i) } catch (e: Exception) { }
    }

    override fun onInterrupt() {}

    /** থামাতে হবে কি? হলে কেন; না হলে null। */
    private fun whyStop(cfg: JSONObject, now: Long): Stop? {
        // ১. পড়ার সময়ের জানালা (Usage Access লাগে না)
        val cal = Calendar.getInstance()
        val minNow = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        val windows = cfg.optJSONArray("windows")
        if (windows != null) {
            for (i in 0 until windows.length()) {
                val w = windows.getJSONObject(i)
                val s = w.optInt("s")
                val e = w.optInt("e")
                val inside = if (s <= e) minNow in s until e else (minNow >= s || minNow < e) // রাত পেরোনো জানালাও
                if (inside) return Stop("window", "${hm(s)} – ${hm(e)}")
            }
        }

        // বাকি দুই নিয়ম আজকের ব্যবহারের হিসাব চায়। Usage Access না থাকলে হিসাব সবসময় ০ আসে,
        // তখন "আজ পড়া হয়নি" ভেবে ভুলভাবে সবসময় থামাত — তাই এই দুই নিয়ম বাদ।
        if (!ScreenTimeBridge.hasAccess(this)) return null
        refreshUsage(cfg, now)

        // ২. আগে পড়ো
        val studyFirstMs = cfg.optLong("studyFirstMin", 0) * 60_000
        if (studyFirstMs > 0 && cacheStudy < studyFirstMs) return Stop("studyfirst")

        // ৩. অপচয়ের সীমা
        val limitMs = cfg.optLong("limitMin", 120) * 60_000
        if (limitMs > 0 && cacheWaste >= limitMs) return Stop("limit")

        return null
    }

    private fun refreshUsage(cfg: JSONObject, now: Long) {
        if (now - cacheAt <= 20_000) return
        val usage = try {
            ScreenTimeBridge.usageMap(this, ScreenTimeBridge.dayStartMs(), now)
        } catch (e: Exception) { emptyMap() }
        cacheWaste = sum(cfg.optJSONArray("waste"), usage)
        cacheStudy = sum(cfg.optJSONArray("study"), usage)
        val manual = cfg.optJSONObject("manual") // হাতে যোগ করা পড়ার সময়
        if (manual != null && manual.optString("day") == ScreenTimeBridge.todayKey()) {
            cacheStudy += manual.optLong("min", 0) * 60_000
        }
        cacheAt = now
    }

    /** আজকের "থামানো" গুনে রাখে (নতুন দিনে ০ থেকে) আর ছাড়পত্র কতবার বাকি তা ফেরত দেয়। */
    private fun countBlockAndGraceLeft(sp: SharedPreferences, cfg: JSONObject): Int {
        val today = ScreenTimeBridge.todayKey()
        val e = sp.edit()
        if (sp.getString("guard_day", "") != today) {
            e.putString("guard_day", today).putInt("grace_used", 0).putInt("blocked", 0)
            e.putInt("blocked", 1)
        } else {
            e.putInt("blocked", sp.getInt("blocked", 0) + 1)
        }
        e.apply()
        val used = if (sp.getString("guard_day", "") == today) sp.getInt("grace_used", 0) else 0
        return (cfg.optInt("graceMax", 2) - used).coerceAtLeast(0)
    }

    private fun has(a: JSONArray?, p: String): Boolean {
        if (a == null) return false
        for (i in 0 until a.length()) if (a.optString(i) == p) return true
        return false
    }

    private fun sum(a: JSONArray?, usage: Map<String, Long>): Long {
        if (a == null) return 0
        var s = 0L
        for (i in 0 until a.length()) s += usage[a.optString(i)] ?: 0L
        return s
    }

    private fun hm(m: Int): String = "%02d:%02d".format(m / 60, m % 60)
}
