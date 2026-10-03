import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:workmanager/workmanager.dart';
import 'services/widget_service.dart';
import 'screens/home_shell.dart';
import 'widgets/app_theme.dart';
import 'widgets/overlay_bubble.dart';
import 'screens/autofill_picker_screen.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'services/drive_service.dart';
import 'cashbook/services/cashbook_notification_service.dart';
import 'cashbook/services/cashbook_widget_service.dart';
import 'screentime/screen_time_service.dart';
import 'cashbook/screens/cashbook_quick_add_app.dart';
import 'reminder/services/reminder_service.dart';

const autoBackupTaskName = 'my_manager_auto_backup';
const cashbookReminderTaskName = 'cashbook_reminder_check';
const reminderRearmTaskName = 'reminder_rearm';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Flutter's default release-mode error widget is a blank grey box with
  // no text (by design, to avoid leaking stack traces to end users) —
  // which is indistinguishable from a genuinely blank screen. Showing the
  // real message here instead makes any future crash immediately
  // diagnosable from a screenshot, on a real device, without adb.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            'কিছু একটা ভুল হয়েছে:\n\n${details.exceptionAsString()}\n\n${details.stack}',
            style: const TextStyle(color: Colors.red, fontSize: 11),
          ),
        ),
      ),
    );
  };
  try {
    tz.initializeTimeZones();
  } catch (_) {}
  try {
    await SettingsService.init();
  } catch (_) {}
  // হোম-স্ক্রিন ক্যাশবুক উইজেট হালনাগাদ (নতুন মাসের খাতাও এখানে বানানো হয়)।
  CashbookWidgetService.refresh();
  // স্ক্রিন টাইমের সতর্কবার্তার কনফিগ (অনুমতি না থাকলে চুপচাপ কিছু করে না)
  ScreenTimeService.syncConfig();
  try {
    await NotificationService.init();
    // সকালের "আজকের ম্যানেজার" নোটিফিকেশন (সময়/চালু-বন্ধ সেটিংস থেকে)
    await NotificationService.scheduleDailyDigest();
  } catch (_) {
    // Notifications failing to set up shouldn't block the app either.
  }
  // Reminder module: (re)arm the next few days of alarms for every saved
  // reminder. Cheap and idempotent — also runs on resume and every 6h.
  try {
    await ReminderService.rearmAll();
  } catch (_) {}
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  // If the floating bubble was left on last time and the overlay permission
  // is still granted, bring it back so it survives an app restart. If the
  // permission was revoked meanwhile, this just does nothing. Wrapped in
  // try-catch so a plugin hiccup here can never block the app from
  // launching — worst case, the bubble just doesn't reappear this time.
  try {
    final bubbleWanted = SettingsService.getBool('bubble_enabled', defaultValue: false);
    if (bubbleWanted) {
      final granted = await FlutterOverlayWindow.isPermissionGranted();
      if (granted) {
        await FlutterOverlayWindow.showOverlay(
          height: 60, width: 60,
          alignment: OverlayAlignment.centerRight,
          flag: OverlayFlag.defaultFlag,
          enableDrag: true,
          positionGravity: PositionGravity.auto,
          overlayTitle: 'My Manager',
          overlayContent: 'কুইক-অ্যাড বাবল চলছে',
        );
      }
    }
  } catch (_) {
    // Never let a bubble-restore failure prevent the app from starting.
  }
  // Auto-backup on WiFi — opt-in, off by default. If the person turned
  // it on in Settings, make sure the periodic task is (re-)registered
  // every time the app starts, in case it was somehow lost (e.g. after
  // a device reboot on some Android versions).
  try {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    if (SettingsService.getBool('auto_backup_enabled', defaultValue: false)) {
      await Workmanager().registerPeriodicTask(
        autoBackupTaskName, autoBackupTaskName,
        frequency: const Duration(hours: 1),
        constraints: Constraints(networkType: NetworkType.unmetered),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
    }
  } catch (_) {
    // Auto-backup setup failing shouldn't block the app from starting.
  }
  // Cashbook's "নাগ every 30 minutes after 8pm until an entry exists
  // today" reminder — always on, no setting to disable it, registered
  // once and left running by WorkManager's own dedup (existingWorkPolicy
  // keep). The exact 8pm ping itself is a separate one-off alarm
  // (CashbookNotificationService.refresh, scheduled whenever the
  // Cashbook screen or the app is opened); this periodic task is what
  // keeps nagging afterward even if the app is never reopened that
  // evening.
  try {
    await Workmanager().registerPeriodicTask(
      cashbookReminderTaskName, cashbookReminderTaskName,
      frequency: const Duration(minutes: 30),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  } catch (_) {
    // Reminder scheduling failing shouldn't block the app from starting.
  }
  try {
    await Workmanager().registerPeriodicTask(
      reminderRearmTaskName, reminderRearmTaskName,
      frequency: const Duration(hours: 6),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  } catch (_) {}
  runApp(const MyManagerApp());
  // Refresh the home screen widget on every cold start too, in case
  // something changed while the app wasn't running.
  WidgetService.update();
}

/// Runs in a headless background isolate whenever Android's WorkManager
/// decides conditions are met (WiFi connected, roughly every ~1h — exact
/// timing isn't guaranteed by Android, that's normal WorkManager
/// behavior). Only does anything if the person is already signed in to
/// Google Drive from a previous manual backup — this can't pop up a
/// sign-in screen since there's no UI here.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (task == reminderRearmTaskName) {
        await ReminderService.rearmAll();
        // সকালের ডাইজেস্টের বিষয়বস্তু তাজা রাখো (প্রতি ৬ ঘণ্টায়)।
        try {
          await SettingsService.init();
          await NotificationService.scheduleDailyDigest();
        } catch (_) {}
        return true;
      }
      if (task == cashbookReminderTaskName) {
        await CashbookNotificationService.backgroundCheck();
        return true;
      }
      await SettingsService.init();
      if (!SettingsService.getBool('auto_backup_enabled', defaultValue: false)) {
        return true;
      }
      final signedIn = await DriveService.instance.signInSilently();
      if (signedIn) {
        await DriveService.instance.backupDatabase();
      }
    } catch (_) {
      // Swallow errors — a failed background backup shouldn't crash
      // anything or retry-loop aggressively. It'll just try again on
      // the next scheduled run.
    }
    return true;
  });
}

/// Entry point for the system-wide overlay window (the floating chat-head).
/// This runs in its own separate Flutter engine, started by the native
/// Android side — completely independent of the app's normal UI tree.
@pragma('vm:entry-point')
void overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Needed so the bubble's own "turn off" button can persist that choice
  // (SettingsService isn't shared automatically between the app's engine
  // and this separate overlay engine — each needs its own init call).
  try {
    await SettingsService.init();
  } catch (_) {}
  runApp(const OverlayBubble());
}

/// Entry point Android launches when it wants us to show autofill
/// suggestions for a login field somewhere else on the device. Runs in
/// its own separate Flutter engine, same pattern as overlayMain() above.
@pragma('vm:entry-point')
void autofillEntryPoint() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SettingsService.init();
  } catch (_) {}
  runApp(const AutofillPickerApp());
}

/// ক্যাশবুক হোম-উইজেটের "＋ জমা / − খরচ" থেকে খোলা দ্রুত-এন্ট্রি শিট
/// (CashbookQuickAddActivity)। নিজের আলাদা Flutter engine-এ চলে।
@pragma('vm:entry-point')
void cashbookQuickAddEntryPoint() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SettingsService.init();
  } catch (_) {}
  await runCashbookQuickAdd();
}

class MyManagerApp extends StatefulWidget {
  const MyManagerApp({super.key});
  static final navigatorKey = GlobalKey<NavigatorState>();
  static _MyManagerAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyManagerAppState>();
  @override State<MyManagerApp> createState() => _MyManagerAppState();
}

class _MyManagerAppState extends State<MyManagerApp> {
  bool _isDark = true;

  @override
  void initState() {
    super.initState();
    _isDark = SettingsService.isDark;
    // Crash log (if any) is now viewed on demand from Settings, not
    // auto-popped-up here — a crash severe/early enough can happen
    // before this widget ever gets a first frame, so a settings-page
    // viewer is the more reliable place either way.
  }

  void toggleTheme() => setState(() => _isDark = SettingsService.isDark);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: MyManagerApp.navigatorKey,
      title: 'My Manager',
      debugShowCheckedModeBanner: false,
      theme: _isDark ? AppTheme.dark : AppTheme.light,
      // Makes any text in the app long-press/drag-selectable and copyable,
      // without having to switch every Text widget to SelectableText.
      builder: (context, child) => SelectionArea(child: child!),
      home: HomeShell(onThemeToggle: toggleTheme),
    );
  }
}
