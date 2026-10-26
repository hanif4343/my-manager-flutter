package com.hanif.mymanager

import android.app.assist.AssistStructure
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.text.InputType
import android.util.Log
import org.json.JSONArray

/**
 * flutter_autofill_service-এর আসল সার্ভিসের সামনে বসা "ছাঁকনি"।
 *
 * সমস্যা: প্লাগইনের সার্ভিস যেকোনো অ্যাপের যেকোনো টেক্সটবক্সে "My Manager" চিপ দেখায়।
 * এই সার্ভিস আগে দেখে নেয়:
 *   ১. স্ক্রিনে পাসওয়ার্ড ফিল্ড আছে (= লগইন ফর্ম)? থাকলে প্রহরী কিছু আটকায় না — নতুন
 *      লগইন "সেভ করো" প্রস্তাবও এই পথেই আসে।
 *   ২. না থাকলে (সাধারণ টেক্সটবক্স): ফোকাস করা ঘরটা ইউজারনেম/ইমেইল ধরনের এবং এই অ্যাপ/সাইটের
 *      জন্য ভল্টে লগইন সেভ করা আছে — তবেই প্লাগইনকে ডাকে। নইলে কোনো চিপই দেখায় না।
 * ভল্টের পাসওয়ার্ড এখানে আসে না: Dart শুধু সাইট/টাইটেলের তালিকা (af_index) রেখে যায়।
 *
 * নিরাপত্তা: কোনো ধাপে সমস্যা হলে ক্র্যাশ করে না — চুপচাপ "কোনো সাজেশন নেই" বলে।
 * সেটিংসের "শুধু সেভ করা সাইটে" বন্ধ থাকলে (af_only_saved=false) কিছুই আটকায় না।
 */
class FilteredAutofillService : AutofillService() {
    private var delegate: AutofillService? = null

    override fun onCreate() {
        super.onCreate()
        try {
            val probe = Intent(SERVICE_INTERFACE).setPackage(packageName)
            val target = packageManager.queryIntentServices(probe, 0)
                .map { it.serviceInfo.name }
                .firstOrNull { it != FilteredAutofillService::class.java.name }
            if (target == null) {
                Log.w(TAG, "plugin autofill service not found")
                return
            }
            val d = Class.forName(target).getDeclaredConstructor().newInstance() as AutofillService
            ContextWrapper::class.java.getDeclaredMethod("attachBaseContext", Context::class.java)
                .apply { isAccessible = true }
                .invoke(d, this)
            d.onCreate()
            delegate = d
        } catch (e: Throwable) {
            Log.e(TAG, "delegate setup failed", e)
            delegate = null
        }
    }

    override fun onConnected() {
        try { delegate?.onConnected() } catch (e: Throwable) { Log.e(TAG, "onConnected", e) }
    }

    override fun onDisconnected() {
        try { delegate?.onDisconnected() } catch (e: Throwable) { Log.e(TAG, "onDisconnected", e) }
    }

    override fun onDestroy() {
        try { delegate?.onDestroy() } catch (e: Throwable) { Log.e(TAG, "onDestroy", e) }
        super.onDestroy()
    }

    override fun onFillRequest(request: FillRequest, signal: CancellationSignal, callback: FillCallback) {
        val d = delegate
        if (d == null) { callback.onSuccess(null); return }
        val allow = try { shouldHandle(request) } catch (e: Throwable) { Log.e(TAG, "filter failed", e); true }
        if (!allow) { callback.onSuccess(null); return }
        try {
            d.onFillRequest(request, signal, callback)
        } catch (e: Throwable) {
            Log.e(TAG, "delegate fill failed", e)
            callback.onSuccess(null)
        }
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        val d = delegate
        if (d == null) { callback.onSuccess(); return }
        try {
            d.onSaveRequest(request, callback)
        } catch (e: Throwable) {
            Log.e(TAG, "delegate save failed", e)
            callback.onSuccess()
        }
    }

    // ───────────── ছাঁকনির যুক্তি ─────────────

    private class Scan {
        var hasPassword = false
        var focusedLoginLike = false
        var domains = mutableSetOf<String>()
    }

    private fun shouldHandle(request: FillRequest): Boolean {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        // Dart-এ ডিফল্ট true; বন্ধ করলে আগের মতো সবখানে।
        if (!(prefs.getBoolean("flutter.af_only_saved", true))) return true

        val structure = request.fillContexts.last().structure
        val scan = Scan()
        for (i in 0 until structure.windowNodeCount) {
            walk(structure.getWindowNodeAt(i).rootViewNode, scan)
        }
        if (scan.hasPassword) return true      // লগইন ফর্ম: সেভ-প্রস্তাবও এখান দিয়েই
        if (!scan.focusedLoginLike) return false // সাধারণ টেক্সটবক্স: চিপ নয়
        val pkg = structure.activityComponent?.packageName ?: ""
        return hasSavedMatch(prefs.getString("flutter.af_index", null), pkg, scan.domains)
    }

    private fun walk(node: AssistStructure.ViewNode, scan: Scan) {
        node.webDomain?.takeIf { it.isNotBlank() }?.let { scan.domains.add(it) }
        val kind = classify(node)
        if (kind == Kind.PASSWORD) scan.hasPassword = true
        if (node.isFocused && (kind == Kind.PASSWORD || kind == Kind.USERNAME)) scan.focusedLoginLike = true
        for (i in 0 until node.childCount) walk(node.getChildAt(i), scan)
    }

    private enum class Kind { PASSWORD, USERNAME, OTHER }

    private fun classify(n: AssistStructure.ViewNode): Kind {
        val hints = n.autofillHints?.map { it.lowercase() } ?: emptyList()
        if (hints.any { it.contains("password") }) return Kind.PASSWORD
        if (hints.any { it.contains("username") || it.contains("email") || it == "loginid" }) return Kind.USERNAME

        val it0 = n.inputType
        if ((it0 and InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT) {
            when (it0 and InputType.TYPE_MASK_VARIATION) {
                InputType.TYPE_TEXT_VARIATION_PASSWORD,
                InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
                InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD -> return Kind.PASSWORD
                InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS -> return Kind.USERNAME
            }
        } else if ((it0 and InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_NUMBER &&
            (it0 and InputType.TYPE_MASK_VARIATION) == InputType.TYPE_NUMBER_VARIATION_PASSWORD) {
            return Kind.PASSWORD
        }

        n.htmlInfo?.attributes?.forEach { p ->
            val k = p.first?.lowercase() ?: return@forEach
            val v = p.second?.lowercase() ?: return@forEach
            if (k == "type" && v == "password") return Kind.PASSWORD
            if (k == "type" && v == "email") return Kind.USERNAME
            if (k == "autocomplete" && v.contains("password")) return Kind.PASSWORD
            if (k == "autocomplete" && (v.contains("username") || v.contains("email"))) return Kind.USERNAME
        }

        val name = ((n.idEntry ?: "") + " " + (n.hint ?: "")).lowercase()
        if (name.contains("password") || name.contains("passwd") || name.contains("pwd")) return Kind.PASSWORD
        if (name.contains("username") || name.contains("user_name") || name.contains("login") || name.contains("email")) return Kind.USERNAME
        return Kind.OTHER
    }

    // ───────────── ভল্টের তালিকার সাথে মেলানো (Dart-এর _prepare-এর মতো) ─────────────

    private fun registrable(host: String): String {
        val parts = host.lowercase().split('.')
        if (parts.size <= 2) return parts.joinToString(".")
        val twoLevel = setOf("co", "com", "org", "net", "gov", "edu", "ac")
        return if (twoLevel.contains(parts[parts.size - 2]) && parts.last().length == 2)
            parts.takeLast(3).joinToString(".") else parts.takeLast(2).joinToString(".")
    }

    private fun hostOf(url: String): String {
        var u = url.lowercase().trim()
        u = u.replace(Regex("^[a-z][a-z0-9+.-]*://"), "")
        return u.split('/').first().split('?').first().split(':').first()
    }

    private fun hasSavedMatch(indexJson: String?, pkg: String, webDomains: Set<String>): Boolean {
        if (indexJson.isNullOrBlank()) return false
        val arr = JSONArray(indexJson)
        val wantedDomains = webDomains.map { registrable(it) }.toSet()
        val wantedLabels = wantedDomains.map { it.substringBefore('.') }.toSet()
        val skip = setOf("com", "org", "net", "android", "app", "apps", "mobile", "www",
            "google", "the", "lite", "main", "client", "release", "io", "co")
        val tokens = if (wantedDomains.isEmpty())
            pkg.lowercase().split('.').filter { it.length >= 4 && it !in skip }.toSet() else emptySet()

        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val url = o.optString("u").lowercase()
            val title = o.optString("t").lowercase()
            if (wantedDomains.isNotEmpty()) {
                if (url.isNotEmpty() && registrable(hostOf(url)) in wantedDomains) return true
                if (wantedLabels.any { it.length >= 4 && title.contains(it) }) return true
            } else {
                val p = pkg.lowercase()
                if (p.isNotEmpty() && (url.contains(p) || title.contains(p))) return true
                if (tokens.any { url.contains(it) || title.contains(it) }) return true
            }
        }
        return false
    }

    companion object {
        private const val TAG = "FilteredAutofill"
    }
}
