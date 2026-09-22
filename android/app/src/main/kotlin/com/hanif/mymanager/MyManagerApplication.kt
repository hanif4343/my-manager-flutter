package com.hanif.mymanager

import android.app.Application
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Installed as the app's <application android:name>. Its only job is to
 * wrap Android's default crash handler so that whatever kills the app —
 * a bug in the main UI, the autofill picker Activity, or the background
 * AutofillService — gets written to a plain text file first. Read from
 * Dart on the next launch (see main.dart) and shown right in the app,
 * since the person using this build has no PC/adb to pull logcat with.
 *
 * This never swallows or suppresses a crash: the previous handler is
 * always called afterward, so Android's normal "app has stopped"
 * behavior is unchanged — this only adds a side-effect write to disk
 * beforehand.
 */
class MyManagerApplication : Application() {
    companion object {
        const val CRASH_LOG_FILE = "last_crash.txt"
    }

    override fun onCreate() {
        super.onCreate()
        val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val sw = StringWriter()
                throwable.printStackTrace(PrintWriter(sw))
                val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
                val text = "সময়: $timestamp\nথ্রেড: ${thread.name}\n\n${sw}"
                File(filesDir, CRASH_LOG_FILE).writeText(text)
            } catch (_: Throwable) {
                // Writing the crash log itself must never throw past this
                // point — if it fails, we still want the real crash to
                // proceed to the previous handler below.
            }
            previousHandler?.uncaughtException(thread, throwable)
        }
    }
}
