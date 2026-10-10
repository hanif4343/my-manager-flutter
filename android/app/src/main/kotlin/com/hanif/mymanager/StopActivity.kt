package com.hanif.mymanager

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * "থামো!" স্ক্রিন — অপচয়ের অ্যাপের উপরে ওঠে। তিনটা পথ: পড়তে যাই / হোমে যাই / কয়েক মিনিট
 * দরকার (সীমিত বার, ১০ সেকেন্ড অপেক্ষার পর — যাতে "অভ্যাসে আঙুল চলে যাওয়া" ঠেকে)।
 */
class StopActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun label(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) { pkg }

    private fun roundBg(color: Int, radius: Int = 14) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radius).toFloat()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val pkg = intent.getStringExtra("pkg") ?: ""
        val reason = intent.getStringExtra("reason") ?: "limit"
        val windowText = intent.getStringExtra("windowText") ?: ""
        val waste = intent.getLongExtra("waste", 0)
        val study = intent.getLongExtra("study", 0)
        val limit = intent.getLongExtra("limit", 0)
        val goal = intent.getLongExtra("goal", 0)
        val graceLeft = intent.getIntExtra("graceLeft", 0)
        val graceMin = intent.getIntExtra("graceMin", 5)
        val need = intent.getLongExtra("need", 0)
        val preview = intent.getBooleanExtra("preview", false)
        val app = intent.getStringExtra("label") ?: label(pkg)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.parseColor("#0E0E12"))
            setPadding(dp(28), dp(64), dp(28), dp(32))
        }

        fun text(t: String, size: Float, color: String = "#FFFFFF", bold: Boolean = false, top: Int = 0): TextView =
            TextView(this).apply {
                text = t
                textSize = size
                setTextColor(Color.parseColor(color))
                gravity = Gravity.CENTER
                if (bold) setTypeface(typeface, Typeface.BOLD)
                setLineSpacing(0f, 1.25f)
                layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                    .apply { topMargin = dp(top) }
            }

        root.addView(text("✋", 64f))
        root.addView(text("থামো!", 34f, "#FFFFFF", true, 4))
        root.addView(text(
            when (reason) {
                "window" -> "এখন তোমার পড়ার সময় ($windowText)\n$app এখন বন্ধ"
                "studyfirst" -> "আগে পড়ো, তারপর $app\nআজ পড়েছ ${ScreenTimeBridge.dur(study)} — আরও ${ScreenTimeBridge.dur((need - study).coerceAtLeast(60_000L))} বাকি"
                else -> "আজ অপচয়ে ${ScreenTimeBridge.dur(waste)} গেছে\n(সীমা ${ScreenTimeBridge.dur(limit)}) — $app আর নয়"
            },
            17f, "#F87171", true, 14))
        root.addView(text("আজ পড়া: ${ScreenTimeBridge.dur(study)} / লক্ষ্য ${ScreenTimeBridge.dur(goal)}", 15f, "#A8A8B3", false, 20))
        root.addView(text("সরকারি চাকরি তাদেরই হয়, যারা আজ পড়েছে।\nমাত্র ২৫ মিনিট পড়ে এসো — তারপর সিদ্ধান্ত নিও 📚", 14.5f, "#D4D4DC", false, 18))

        val spacer = android.view.View(this).apply {
            layoutParams = LinearLayout.LayoutParams(1, 0, 1f)
        }
        root.addView(spacer)

        fun button(t: String, bg: String, fg: String = "#FFFFFF"): Button = Button(this).apply {
            text = t
            isAllCaps = false
            textSize = 16f
            setTextColor(Color.parseColor(fg))
            background = roundBg(Color.parseColor(bg))
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(54))
                .apply { topMargin = dp(10) }
        }

        val study_b = button("📚 পড়তে যাই", "#15803D")
        study_b.setOnClickListener {
            val i = packageManager.getLaunchIntentForPackage("com.hanif.smartstudy")
                ?: packageManager.getLaunchIntentForPackage(packageName)
            if (i != null) {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(i)
            }
            finish()
        }
        root.addView(study_b)

        val home_b = button("🏠 হোমে যাই", "#2A2A33")
        home_b.setOnClickListener { goHome() }
        root.addView(home_b)

        if (graceLeft > 0) {
            val grace = button("", "#1C1C22", "#6B6B76")
            grace.isEnabled = false
            root.addView(grace)
            var left = 10
            val tick = object : Runnable {
                override fun run() {
                    if (left > 0) {
                        grace.text = "⏳ ${ScreenTimeBridge.bn(left.toLong())} সেকেন্ড ভাবো..."
                        left--
                        handler.postDelayed(this, 1000)
                    } else {
                        grace.isEnabled = true
                        grace.setTextColor(Color.parseColor("#A8A8B3"))
                        grace.text = "${ScreenTimeBridge.bn(graceMin.toLong())} মিনিট লাগবেই (আজ বাকি ${ScreenTimeBridge.bn(graceLeft.toLong())}টা)"
                    }
                }
            }
            handler.post(tick)
            grace.setOnClickListener {
                if (preview) { finish(); return@setOnClickListener } // নমুনা দেখার সময় ছাড়পত্র খরচ হয় না
                val sp = getSharedPreferences(ScreenTimeBridge.PREFS, Context.MODE_PRIVATE)
                sp.edit()
                    .putLong("grace_until", System.currentTimeMillis() + graceMin * 60_000L)
                    .putInt("grace_used", sp.getInt("grace_used", 0) + 1)
                    .apply()
                finish()
            }
        } else {
            root.addView(text("আজকের ছাড়পত্র শেষ।", 12.5f, "#6B6B76", false, 12))
        }

        setContentView(root)
    }

    /** নতুন করে থামাতে হলে পুরনো সংখ্যা/কারণ নয়, নতুন ইনটেন্ট দিয়ে স্ক্রিন আবার বানানো। */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        recreate()
    }

    /** হোম/রিসেন্টে গেলে স্ক্রিনটা পড়ে থাকে না — পরের বার তাজা হয়ে ওঠে। */
    override fun onStop() {
        super.onStop()
        if (!isChangingConfigurations) finish()
    }

    private fun goHome() {
        startActivity(Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        })
        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        goHome()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
