import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/material.dart';
import '../reminder/services/reminder_service.dart';
import '../today/today_service.dart';
import 'settings_service.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId = 'my_manager_channel';
  static const _digestId = 9999; // fixed ID for daily digest

  static Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    // Without this, tz.local silently defaults to UTC and every
    // zonedSchedule below fires 6 hours off in Bangladesh (e.g. an 8pm
    // schedule actually lands at 2am local time).
    try {
      final dynamic tzResult = await FlutterTimezone.getLocalTimezone();
      final String tzName = tzResult is String ? tzResult : (tzResult.identifier as String);
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (_) {
      // Fall back to UTC rather than crashing — reminders will just
      // fire at the wrong time instead of not existing at all.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);

    await _plugin.initialize(
      settings,
      // Same callbacks as ReminderService — the plugin is a singleton and the
      // last initialize() call wins, so every caller must register these or
      // the reminder Done / Not yet buttons stop working.
      onDidReceiveNotificationResponse: (details) {
        debugPrint('Notification tapped: ${details.payload}');
        ReminderService.onForeground(details);
      },
      onDidReceiveBackgroundNotificationResponse: reminderBackgroundHandler,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
    debugPrint('NotificationService initialized');
  }

  static Future<void> scheduleNotification(
      int id, String title, String body, DateTime scheduledTime) async {
    await init();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      'My Manager Reminders',
      channelDescription: 'Project reminder notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
    );

    const details = NotificationDetails(android: androidDetails);
    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzTime,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'project_$id',
    );

    debugPrint('Scheduled notification #$id at $scheduledTime');
  }

  static Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
  }

  static Future<void> showInstant(String title, String body) async {
    await init();
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      'My Manager Reminders',
      channelDescription: 'Project reminder notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    await _plugin.show(0, title, body,
        const NotificationDetails(android: androidDetails));
  }

  /// সকালের "আজকের ম্যানেজার" নোটিফিকেশন: রিমাইন্ডার, চাকরির ডেডলাইন, বিল,
  /// জন্মদিন, বাজেট, প্রজেক্ট — সব মডিউল মিলিয়ে (TodayService)। সময় ও চালু/বন্ধ
  /// সেটিংসের Daily digest থেকে আসে (ডিফল্ট সকাল ৮টা)।
  ///
  /// বিষয়বস্তু শিডিউল করার মুহূর্তে হিসাব করা হয় (ফায়ারের দিনের হিসাবে), তাই এটা
  /// একবারের নোটিফিকেশন — অ্যাপ খুললে, রিজিউম হলে আর প্রতি ৬ ঘণ্টার ব্যাকগ্রাউন্ড
  /// টাস্কে নতুন করে বসে। জরুরি/আসন্ন কিছু না থাকলে কোনো নোটিফিকেশন যায় না।
  static Future<void> scheduleDailyDigest({int? hour, int? minute}) async {
    await init();
    await _plugin.cancel(_digestId);

    if (!SettingsService.getBool('digest_enabled', defaultValue: true)) return;
    final h = hour ?? SettingsService.getInt('digest_hour', defaultValue: 8);
    final m = minute ?? SettingsService.getInt('digest_minute', defaultValue: 0);

    final now = DateTime.now();
    var fireAt = DateTime(now.year, now.month, now.day, h, m);
    if (!fireAt.isAfter(now)) fireAt = fireAt.add(const Duration(days: 1));

    final summary = await TodayService.build(asOf: fireAt, includeBackupHints: false);
    if (!summary.worthNotifying) return;

    final androidDetails = AndroidNotificationDetails(
      'daily_digest_channel',
      'Daily Digest',
      channelDescription: 'প্রতিদিনের কাজের সারসংক্ষেপ',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(
        summary.notificationBody(),
        contentTitle: '${TodaySummary.greeting(h)} আজকের ম্যানেজার',
        summaryText: summary.notificationShort,
      ),
    );

    await _plugin.zonedSchedule(
      _digestId,
      '${TodaySummary.greeting(h)} আজকের ম্যানেজার',
      summary.notificationShort,
      tz.TZDateTime.from(fireAt, tz.local),
      NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'today_digest',
    );

    debugPrint('Morning digest scheduled for $fireAt → ${summary.notificationShort}');
  }

  static Future<void> cancelDailyDigest() async {
    await _plugin.cancel(_digestId);
  }

  static Future<List<PendingNotificationRequest>> getPending() async {
    return _plugin.pendingNotificationRequests();
  }
}
