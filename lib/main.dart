import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/dashboard_screen.dart';
import 'widgets/app_theme.dart';
import 'services/notification_service.dart'; // নোটিফিকেশন সার্ভিস ইমপোর্ট করুন

void main() async { // এখানে async যোগ করা হয়েছে
  WidgetsFlutterBinding.ensureInitialized();
  
  // নোটিফিকেশন সার্ভিস ইনিশিয়ালাইজ করা
  await NotificationService.init(); 

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const MyManagerApp());
}

class MyManagerApp extends StatelessWidget {
  const MyManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const DashboardScreen(),
    );
  }
}
