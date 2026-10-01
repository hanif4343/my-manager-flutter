package com.hanif.mymanager

import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * ক্যাশবুক উইজেট থেকে খোলে: স্বচ্ছ উইন্ডো, তার উপর Flutter-এর এন্ট্রি-শিট
 * (জমা/খরচ)। মূল অ্যাপের টাস্ক টেনে আনে না।
 */
class CashbookQuickAddActivity : FlutterFragmentActivity() {
    override fun getDartEntrypointFunctionName(): String = "cashbookQuickAddEntryPoint"

    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode =
        FlutterActivityLaunchConfigs.BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Dart-এর entrypoint সরাসরি Intent পড়তে পারে না — তাই ছোট একটা চ্যানেল।
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hanif.mymanager/quickadd")
            .setMethodCallHandler { call, result ->
                if (call.method == "initialType") {
                    result.success(intent?.getStringExtra("type") ?: "out")
                } else {
                    result.notImplemented()
                }
            }
    }
}
