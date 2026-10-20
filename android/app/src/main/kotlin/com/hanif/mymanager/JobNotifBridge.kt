package com.hanif.mymanager

import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/** Flutter ↔ JobNotificationListener সেতু (চ্যানেল: com.hanif.mymanager/jobnotif)। */
object JobNotifBridge {
    const val PREFS = "job_radar_native"
    const val KEY_PKGS = "pkgs"
    private const val KEY_QUEUE = "queue"
    private const val MAX_QUEUE = 100
    private val lock = Any()

    fun enqueue(ctx: Context, pkg: String, title: String, text: String, time: Long) {
        synchronized(lock) {
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val arr = try { JSONArray(prefs.getString(KEY_QUEUE, "[]")) } catch (e: Exception) { JSONArray() }
            // একই নোটিফিকেশন বারবার এলে (আপডেট) ডুপ্লিকেট বাদ
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                if (o.optString("pkg") == pkg && o.optString("title") == title && o.optString("text") == text) return
            }
            arr.put(JSONObject().put("pkg", pkg).put("title", title).put("text", text).put("time", time))
            // পুরনো ছাঁটাই
            val out = JSONArray()
            val start = maxOf(0, arr.length() - MAX_QUEUE)
            for (i in start until arr.length()) out.put(arr.get(i))
            prefs.edit().putString(KEY_QUEUE, out.toString()).apply()
        }
    }

    private fun drain(ctx: Context): String = synchronized(lock) {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val s = prefs.getString(KEY_QUEUE, "[]") ?: "[]"
        prefs.edit().putString(KEY_QUEUE, "[]").apply()
        s
    }

    private fun isEnabled(ctx: Context): Boolean {
        val flat = Settings.Secure.getString(ctx.contentResolver, "enabled_notification_listeners") ?: return false
        return flat.contains(ctx.packageName)
    }

    fun register(engine: FlutterEngine, ctx: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.hanif.mymanager/jobnotif")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isEnabled" -> result.success(isEnabled(ctx))
                        "openSettings" -> {
                            val i = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            ctx.startActivity(i)
                            result.success(true)
                        }
                        "getPackages" -> {
                            val set = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                                .getStringSet(KEY_PKGS, emptySet()) ?: emptySet()
                            result.success(set.toList())
                        }
                        "setPackages" -> {
                            val list = call.argument<List<String>>("packages") ?: emptyList()
                            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                                .edit().putStringSet(KEY_PKGS, list.toSet()).apply()
                            result.success(true)
                        }
                        "drain" -> result.success(drain(ctx))
                        "searchApps" -> {
                            val q = (call.argument<String>("query") ?: "").trim().lowercase()
                            val pm = ctx.packageManager
                            val found = pm.getInstalledApplications(0)
                                .filter { pm.getLaunchIntentForPackage(it.packageName) != null }
                                .map { mapOf("label" to pm.getApplicationLabel(it).toString(), "pkg" to it.packageName) }
                                .filter { q.isEmpty() || it["label"]!!.lowercase().contains(q) || it["pkg"]!!.lowercase().contains(q) }
                                .sortedBy { it["label"]!!.lowercase() }
                                .take(30)
                            result.success(found)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("jobnotif", e.message, null)
                }
            }
    }
}
