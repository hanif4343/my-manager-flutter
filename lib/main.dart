import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'screens/dashboard_screen.dart';
import 'screens/pin_screen.dart';
import 'widgets/app_theme.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await SettingsService.init();
  await NotificationService.init();
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
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _isDark = SettingsService.isDark;
    _unlocked = !SettingsService.pinEnabled;
  }

  void toggleTheme() {
    setState(() => _isDark = SettingsService.isDark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Manager',
      debugShowCheckedModeBanner: false,
      theme: _isDark ? AppTheme.dark : AppTheme.light,
      home: SettingsService.pinEnabled && !_unlocked
          ? PinScreen(
              isSetup: false,
              onSuccess: () => setState(() => _unlocked = true),
            )
          : DashboardScreen(onThemeToggle: toggleTheme),
    );
  }
}
