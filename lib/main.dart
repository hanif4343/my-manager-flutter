import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'screens/dashboard_screen.dart';
import 'widgets/app_theme.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await SettingsService.init();
  await NotificationService.init();
  // Schedule daily digest every morning at 8:00 AM
  await NotificationService.scheduleDailyDigest(hour: 8, minute: 0);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const MyManagerApp());
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
      home: DashboardScreen(onThemeToggle: toggleTheme),
    );
  }
}
