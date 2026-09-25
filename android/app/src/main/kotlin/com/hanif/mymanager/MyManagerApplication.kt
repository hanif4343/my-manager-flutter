package com.hanif.mymanager

import android.app.Application
import android.content.Context
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
 * AutofillService (including one merged in from a plugin's own library
 * manifest, e.g. flutter_autofill_service's "Flutter Autofill Service"
 * entry) — gets written to a plain text file first. Read from a Settings
 * screen in the Flutter app (not an automatic popup, since a crash
 * severe/early enough might happen before Flutter's engine can boot to
 * show one), since the person using this build has no PC/adb to pull
 * logcat with.
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

    // attachBaseContext runs before onCreate() and before any
    // ContentProvider or other component in this process is created —
    // the earliest point our own code can run at all. Installing the
    // handler here (rather than in onCreate) narrows the window in
    // which an early native-service crash could happen before we're
    // watching for it.
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        installCrashHandler()
    }

    private fun installCrashHandler() {
        val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val sw = StringWriter()
                throwable.printStackTrace(PrintWriter(sw))
                val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
                val entry = "সময়: $timestamp\nপ্রসেস: ${android.os.Process.myPid()}\nথ্রেড: ${thread.name}\n\n$sw\n" +
                    "----------------------------------------\n"
                // Append, don't overwrite — if several different crashes
                // happen (e.g. one from the autofill service process,
                // one later from the main UI) none of them get lost
                // before the person has a chance to look.
                val f = File(filesDir, CRASH_LOG_FILE)
                f.appendText(entry)
            } catch (_: Throwable) {
                // Writing the crash log itself must never throw past this
                // point — if it fails, we still want the real crash to
                // proceed to the previous handler below.
            }
            previousHandler?.uncaughtException(thread, throwable)
        }
    }

    override fun onCreate() {
        super.onCreate()
        // Re-installed here too in case something between
        // attachBaseContext and onCreate replaced the handler (some
        // libraries do this in their own initializers) — cheap and
        // harmless to set twice.
        installCrashHandler()
    }
}
