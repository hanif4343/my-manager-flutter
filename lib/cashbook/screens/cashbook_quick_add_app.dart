import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/app_theme.dart';
import '../db/cashbook_db.dart';
import '../services/cashbook_widget_service.dart';
import 'cashbook_entry_sheet.dart';

/// হোম-স্ক্রিন উইজেটের "＋ জমা / − খরচ" বাটন থেকে খোলে (CashbookQuickAddActivity)।
/// স্বচ্ছ উইন্ডোর উপর সরাসরি ক্যাশবুকের এন্ট্রি-শিট; সেভ বা বাইরে ট্যাপে বন্ধ।
///
/// নিরাপত্তা: শুধু নতুন এন্ট্রি যোগ হয়, কিছু দেখানো হয় না — তাই ক্যাশবুকের
/// লক/ফিঙ্গারপ্রিন্ট এখানে চাওয়া হয় না।
Future<void> runCashbookQuickAdd() async {
  String type = 'out';
  try {
    type = await const MethodChannel('com.hanif.mymanager/quickadd')
            .invokeMethod<String>('initialType') ??
        'out';
  } catch (_) {}
  int? accountId;
  try {
    accountId = (await CashbookDB.currentMonthAccount()).id;
  } catch (_) {}
  runApp(CashbookQuickAddApp(type: type == 'in' ? 'in' : 'out', accountId: accountId));
}

class CashbookQuickAddApp extends StatelessWidget {
  final String type;
  final int? accountId;
  const CashbookQuickAddApp({super.key, required this.type, required this.accountId});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: _Launcher(type: type, accountId: accountId),
    );
  }
}

class _Launcher extends StatefulWidget {
  final String type;
  final int? accountId;
  const _Launcher({required this.type, required this.accountId});
  @override State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final id = widget.accountId;
    if (id == null) {
      SystemNavigator.pop();
      return;
    }
    try {
      await CashbookEntrySheet.show(context, accountId: id, initialType: widget.type);
      // সেভ হোক বা না হোক, উইজেটের সংখ্যা হালনাগাদ করে তারপর বন্ধ।
      await CashbookWidgetService.refresh();
    } catch (_) {}
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    // স্বচ্ছ — উইজেটের পেছনের হোম স্ক্রিনই দেখা যায়।
    return const Scaffold(backgroundColor: Colors.transparent);
  }
}
