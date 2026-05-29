import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter/material.dart';
import '../db/db_helper.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId = 'my_manager_channel';
  static const _digestId = 9999; // fixed ID for daily digest

  static Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint('Notification tapped: ${details.payload}');
      },
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

  /// Schedule (or reschedule) the daily digest at [hour]:[minute].
  /// Reads live DB data at fire time via a background entrypoint is not
  /// feasible in flutter_local_notifications alone, so we schedule it now
  /// with a summary built from the current DB state, then re-schedule every
  /// time the app opens.
  static Future<void> scheduleDailyDigest({int hour = 8, int minute = 0}) async {
    await init();

    // Cancel old digest first
    await _plugin.cancel(_digestId);

    // Build summary from current DB state
    final ideas = await DBHelper.getAllActiveIdeas();
    final now = DateTime.now();

    final pending = ideas.where((i) => i.status != 'done').length;

    // Ideas whose deadline is today or tomorrow
    final upcoming = ideas.where((i) {
      if (i.deadline == null) return false;
      final d = DateTime.fromMillisecondsSinceEpoch(i.deadline!);
      final diff = d.difference(now).inDays;
      return diff >= 0 && diff <= 1;
    }).length;

    final overdue = ideas.where((i) => i.isOverdue).length;

    if (pending == 0 && upcoming == 0) return; // nothing to notify about

    final parts = <String>[];
    if (pending > 0) parts.add('$pending টা task pending');
    if (upcoming > 0) parts.add('$upcoming টা deadline আসছে');
    if (overdue > 0) parts.add('$overdue টা overdue ⚠️');
    final body = parts.join(', ');

    // Schedule for next occurrence of hour:minute
    var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'daily_digest_channel',
      'Daily Digest',
      channelDescription: 'প্রতিদিনের কাজের সারসংক্ষেপ',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );

    await _plugin.zonedSchedule(
      _digestId,
      '📋 আজকের কাজ',
      body,
      tz.TZDateTime.from(scheduled, tz.local),
      const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily
    );

    debugPrint('Daily digest scheduled at $hour:$minute → $body');
  }

  static Future<void> cancelDailyDigest() async {
    await _plugin.cancel(_digestId);
  }

  static Future<List<PendingNotificationRequest>> getPending() async {
    return _plugin.pendingNotificationRequests();
  }
}
