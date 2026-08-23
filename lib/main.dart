import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'screens/home_shell.dart';
import 'widgets/app_theme.dart';
import 'widgets/overlay_bubble.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    tz.initializeTimeZones();
  } catch (_) {}
  try {
    await SettingsService.init();
  } catch (_) {}
  try {
    await NotificationService.init();
    // Schedule daily digest every morning at 8:00 AM
    await NotificationService.scheduleDailyDigest(hour: 8, minute: 0);
  } catch (_) {
    // Notifications failing to set up shouldn't block the app either.
  }
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
          enableDrag: false,
          positionGravity: PositionGravity.none,
          overlayTitle: 'My Manager',
          overlayContent: 'কুইক-অ্যাড বাবল চলছে',
        );
      }
    }
  } catch (_) {
    // Never let a bubble-restore failure prevent the app from starting.
  }
  runApp(const MyManagerApp());
}

/// Entry point for the system-wide overlay window (the floating chat-head).
/// This runs in its own separate Flutter engine, started by the native
/// Android side — completely independent of the app's normal UI tree.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayBubble());
}

class MyManagerApp extends StatefulWidget {
  const MyManagerApp({super.key});
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
  }

  void toggleTheme() => setState(() => _isDark = SettingsService.isDark);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
