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

  /// Called every ~30 minutes by a background WorkManager task (see
  /// main.dart), all day, every day — it only actually does anything
  /// from 8pm onward. If today already has an entry it stays silent
  /// (and this is also how nagging "stops": once one entry exists, every
  /// subsequent 30-min check just no-ops for the rest of the day).
  /// Android's WorkManager periodic timing isn't clock-exact, so the
  /// first nag after 8pm may land a little before or after the hour —
  /// that's normal background-scheduling behavior, not a bug.
  static Future<void> backgroundCheck() async {
    if (DateTime.now().hour < 20) return;
    await _init();
    final hasEntry = await CashbookDB.hasEntryToday();
    if (hasEntry) {
      await _plugin.cancel(_reminderId);
      return;
    }
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      'ক্যাশবুক রিমাইন্ডার',
      channelDescription: 'আজকের জমা-খরচ এন্ট্রি না দেওয়া থাকলে রাতে মনে করিয়ে দেয়',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    await _plugin.show(
      _reminderId,
      '🧾 আজকের হিসাব এখনও লেখা হয়নি',
      'ক্যাশবুকে আজকের জমা/খরচ যোগ করো — অন্তত একটা এন্ট্রি দিলেই আর মনে করাবো না',
      const NotificationDetails(android: androidDetails),
    );
  }
}
