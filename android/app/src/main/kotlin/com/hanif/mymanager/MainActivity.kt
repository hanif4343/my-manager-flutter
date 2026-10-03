package com.hanif.mymanager

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity) is required by the
// local_auth plugin for its biometric/PIN prompt to work.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ScreenTimeBridge.register(flutterEngine, applicationContext)
        // চাকরি হাব থেকে SmartStudyBD খোলা / সার্কুলারের লিংক খোলা।
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hanif.mymanager/launcher")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchApp" -> {
                        val pkg = call.argument<String>("package")
                        val intent = pkg?.let { packageManager.getLaunchIntentForPackage(it) }
                        if (intent != null) {
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "dial" -> {
                        val number = call.argument<String>("number")
                        try {
                            val i = Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + Uri.encode(number ?: "")))
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        try {
                            val i = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
