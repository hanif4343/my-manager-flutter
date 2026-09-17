import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../db/cashbook_db.dart';

/// "রাত ৮টায় মনে করিয়ে দাও যদি আজ কিছু যোগ না করে থাকি" — this only ever
/// checks *today's* entries at the moment the app is opened/resumed and
/// re-schedules from there (flutter_local_notifications can't run a
/// fresh DB query at the exact moment the alarm fires), so call
/// [refresh] from app-resume and from the Cashbook screen's initState,
/// same spirit as the app's existing daily digest.
class CashbookNotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static const _channelId = 'cashbook_reminder_channel';
  static const _reminderId = 7777;

  static Future<void> _init() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  static Future<void> refresh({int hour = 20, int minute = 0}) async {
    await _init();
    await _plugin.cancel(_reminderId);

    final hasEntry = await CashbookDB.hasEntryToday();
    if (hasEntry) return; // today's already logged, nothing to nudge about

    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      'ক্যাশবুক রিমাইন্ডার',
      channelDescription: 'আজকের জমা-খরচ এন্ট্রি না দেওয়া থাকলে রাতে মনে করিয়ে দেয়',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );

    await _plugin.zonedSchedule(
      _reminderId,
      '🧾 আজকের হিসাব লেখা হয়নি',
      'ক্যাশবুকে আজকের জমা/খরচ যোগ করতে ভুলো না',
      tz.TZDateTime.from(scheduled, tz.local),
      const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancel() async {
    await _plugin.cancel(_reminderId);
  }
}
