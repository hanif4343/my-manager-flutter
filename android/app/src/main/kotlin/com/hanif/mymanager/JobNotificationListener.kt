package com.hanif.mymanager

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * শুধু ব্যবহারকারীর বেছে দেওয়া চাকরির অ্যাপগুলোর নোটিফিকেশন ধরে।
 * অন্য কোনো অ্যাপের নোটিফিকেশনের বিষয়বস্তু পড়াই হয় না (প্যাকেজ মিলিয়ে সরাসরি ফিরে যায়)।
 */
class JobNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val n = sbn ?: return
        val pkg = n.packageName ?: return
        val prefs = getSharedPreferences(JobNotifBridge.PREFS, Context.MODE_PRIVATE)
        val allowed = prefs.getStringSet(JobNotifBridge.KEY_PKGS, emptySet()) ?: emptySet()
        if (pkg !in allowed) return
        if (n.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return

        val ex = n.notification.extras
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val text = (ex.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: ex.getCharSequence(Notification.EXTRA_TEXT))?.toString()?.trim().orEmpty()
        if (title.isEmpty() && text.isEmpty()) return

        JobNotifBridge.enqueue(this, pkg, title.take(300), text.take(800), n.postTime)
    }
}
