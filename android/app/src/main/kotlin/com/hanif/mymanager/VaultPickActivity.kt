package com.hanif.mymanager

import android.app.Activity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * অন্য অ্যাপ/ব্রাউজারের ফাইল-পিকারে "ডকুমেন্ট ভল্ট" চাপলে VaultDocumentsProvider
 * (AuthenticationRequiredException-এর PendingIntent দিয়ে) এই Activity চালু করে।
 * এখানে ফিঙ্গারপ্রিন্ট/PIN যাচাইয়ের পর ব্যবহারকারী ভল্ট থেকে ফাইল বাছে; বাছা ফাইল
 * আপলোড-ট্রেতে রেখে "done" ডাকলে RESULT_OK দিয়ে বন্ধ হয় — তখন পিকার আবার তালিকা লোড
 * করে বাছা ফাইলগুলো দেখায়। বাতিল করলে RESULT_CANCELED।
 */
class VaultPickActivity : FlutterFragmentActivity() {
    override fun getDartEntrypointFunctionName(): String = "vaultPickEntryPoint"

    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode =
        FlutterActivityLaunchConfigs.BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hanif.mymanager/vaultpick")
            .setMethodCallHandler { call, result ->
                if (call.method == "done") {
                    VaultDocumentsProvider.markUnlocked()
                    setResult(Activity.RESULT_OK)
                    result.success(null)
                    finish()
                } else {
                    result.notImplemented()
                }
            }
    }
}
