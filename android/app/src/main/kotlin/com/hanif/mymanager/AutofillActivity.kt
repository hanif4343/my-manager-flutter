package com.hanif.mymanager

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * অন্য অ্যাপের (Chrome, Facebook...) লগইন ফর্মের উপর দিয়ে খুলবে এমন আলাদা
 * Activity। আগে এটা MainActivity-র activity-alias ছিল, কিন্তু alias নিজের
 * launchMode পায় না — target-এর singleTask নেয়, ফলে ব্যবহারকারীকে জোর করে
 * মূল অ্যাপের টাস্কে টেনে নেওয়া হতো আর picker ঠিকমতো দেখাতো না।
 *
 * FlutterFragmentActivity লাগে কারণ picker-এ local_auth-এর
 * ফিঙ্গারপ্রিন্ট/PIN প্রম্পট আছে।
 */
class AutofillActivity : FlutterFragmentActivity() {
    override fun getDartEntrypointFunctionName(): String = "autofillEntryPoint"
}
