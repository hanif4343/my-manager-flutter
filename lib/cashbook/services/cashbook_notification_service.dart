import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import '../db/cashbook_db.dart';
import '../../reminder/services/reminder_service.dart';

/// "রাত ৮টা থেকে শুরু করে প্রতি ৩০ মিনিটে মনে করিয়ে দাও, যতক্ষণ না আজ
/// অন্তত একটা এন্ট্রি হয়" — implemented as a fixed chain of *exact*
/// alarms (8:00, 8:30, ... 11:30pm), not a single schedule plus a
/// periodic background poll. Exact alarms (AndroidScheduleMode.
/// exactAllowWhileIdle, backed by USE_EXACT_ALARM in the manifest) are
/// far more likely to actually fire on time on battery-aggressive OEMs
/// (Xiaomi/Vivo/Oppo/Realme) than WorkManager's ~30-min periodic jobs,
/// which Android is free to delay by hours under Doze.
///
/// [refresh] is idempotent and cheap to call often: cancels every slot,
/// then — only if today has no entry yet — re-arms every slot that
/// hasn't already passed. Call it whenever the day's entry state could
/// have changed: app open/resume, Cashbook screen load, and right after
/// saving/deleting an entry — that last one is what makes the reminder
/// actually stop the moment a real entry is logged, not just at the
/// next 30-min poll.
class CashbookNotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static const _channelId = 'cashbook_reminder_channel';

  // 8:00pm through 11:30pm, every 30 minutes — each slot is its own
  // notification ID so they can be scheduled/cancelled independently.
  static const _slots = [
    (20, 0), (20, 30), (21, 0), (21, 30),
    (22, 0), (22, 30), (23, 0), (23, 30),
  ];
  static int _idFor(int hour, int minute) => 7700 + hour * 2 + (minute == 30 ? 1 : 0);

  static Future<void> _init() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    // Without this, tz.local silently defaults to UTC, and every
    // zonedSchedule below fires 6 hours off in Bangladesh (a "8pm"
    // schedule actually lands at 2am local time) — this was the exact
    // bug behind the 8pm reminder never showing up in the first place.
    try {
      // flutter_timezone's return type has changed across versions —
      // older ones give a plain String, newer ones a TimezoneInfo object
      // with an .identifier field. Handling both dynamically avoids
      // guessing wrong and failing the build over a package version
      // detail that doesn't actually matter for what we need here.
      final dynamic tzResult = await FlutterTimezone.getLocalTimezone();
      final String tzName = tzResult is String ? tzResult : (tzResult.identifier as String);
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (_) {
      // Fall back to UTC rather than crashing — reminders would fire at
      // the wrong time instead of not existing at all.
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Reminder callbacks must be re-registered here: the plugin instance is
    // shared app-wide and the last initialize() call wins.
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: ReminderService.onForeground,
      onDidReceiveBackgroundNotificationResponse: reminderBackgroundHandler,
    );
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    try {
      // Android 12+ gates exact alarms behind this separate permission.
      // USE_EXACT_ALARM in the manifest auto-grants it for most installs,
      // but requesting explicitly is harmless and covers edge cases.
      await androidImpl?.requestExactAlarmsPermission();
    } catch (_) {
      // Older flutter_local_notifications versions or OEMs without this
      // API — exact alarms may just silently fall back to inexact.
    }
    _initialized = true;
  }

  static Future<void> _cancelAllSlots() async {
    for (final (h, m) in _slots) {
      await _plugin.cancel(_idFor(h, m));
    }
  }

  static Future<void> refresh() async {
    await _init();
    await _cancelAllSlots();

    final hasEntry = await CashbookDB.hasEntryToday();
    if (hasEntry) return; // today's already logged — nothing to nag about

    final now = DateTime.now();
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      'ক্যাশবুক রিমাইন্ডার',
      channelDescription: 'আজকের জমা-খরচ এন্ট্রি না দেওয়া থাকলে সন্ধ্যা থেকে রাত পর্যন্ত মনে করিয়ে দেয়',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    for (final (hour, minute) in _slots) {
      var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
      if (scheduled.isBefore(now)) continue; // that slot's already passed today
      await _plugin.zonedSchedule(
        _idFor(hour, minute),
        '🧾 আজকের হিসাব এখনও লেখা হয়নি',
        'ক্যাশবুকে আজকের জমা/খরচ যোগ করো — অন্তত একটা এন্ট্রি দিলেই আর মনে করাবে না',
        tz.TZDateTime.from(scheduled, tz.local),
        const NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  static Future<void> cancel() async {
    await _cancelAllSlots();
  }

  /// Called every ~30 minutes by a background WorkManager task (see
  /// main.dart) as a redundant safety net — e.g. if the app was never
  /// opened all day so the exact alarms above never got armed in the
  /// first place. Just re-runs the same idempotent [refresh] logic;
  /// WorkManager's own timing looseness no longer matters for whether
  /// the reminder fires on time, only for whether it gets armed at all.
  static Future<void> backgroundCheck() async {
    if (DateTime.now().hour < 20) return;
    await refresh();
  }

  /// MIUI/FunTouch/ColorOS-style battery managers on Xiaomi, Vivo, Oppo
  /// and some Samsung phones aggressively kill background work — no
  /// amount of app-side code fixes that, only the person granting an
  /// exemption does. Asks once, only if not already granted; safe to
  /// call repeatedly since it no-ops once granted or once permanently
  /// denied.
  static Future<void> requestBatteryExemptionIfNeeded() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (!status.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {
      // Not available on this platform/OEM — never block the app for it.
    }
  }
}
