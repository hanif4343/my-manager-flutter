import 'package:home_widget/home_widget.dart';
import '../db/cashbook_db.dart';
import 'spending_guard.dart';

/// হোম-স্ক্রিন ক্যাশবুক উইজেটে চলতি মাসের হিসাব পাঠায়
/// (android: CashbookWidgetProvider.kt)। সব মান String — আগের WidgetService-এর
/// মতোই, কারণ এই home_widget ভার্সনে সংখ্যা সেভে বাগ ছিল।
///
/// কখন চলে: প্রতিটা এন্ট্রি যোগ/এডিট/মুছলে (CashbookDB থেকে), অ্যাপ চালু হলে,
/// আর উইজেটের দ্রুত-এন্ট্রি সেভের পর। ব্যর্থ হলে চুপচাপ — মূল কাজ আটকায় না।
class CashbookWidgetService {
  static const providerName = 'CashbookWidgetProvider';
  static bool _busy = false;
  static bool _dirty = false;

  static String _money(double v) {
    final n = v.round().abs();
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i != 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${v < 0 ? '-' : ''}৳$b';
  }

  static Future<void> refresh() async {
    if (_busy) {
      _dirty = true; // চলার সময় আরেকটা পরিবর্তন এলে শেষে আবার একবার
      return;
    }
    _busy = true;
    try {
      do {
        _dirty = false;
        await _push();
      } while (_dirty);
    } catch (_) {
      // উইজেট রিফ্রেশ কখনো ক্যাশবুকের কাজে বাধা দেবে না।
    } finally {
      _busy = false;
    }
  }

  static Future<void> _push() async {
    final acc = await CashbookDB.currentMonthAccount();
    final entries = await CashbookDB.getEntries(accountId: acc.id);
    final now = DateTime.now();
    final monthKey = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

    double balance = 0, income = 0, expense = 0;
    for (final e in entries) {
      final isIn = e.type == 'in';
      balance += isIn ? e.amount : -e.amount;
      if (e.date.startsWith(monthKey)) {
        if (isIn) {
          income += e.amount;
        } else {
          expense += e.amount;
        }
      }
    }

    // খরচ-প্রহরীর সতর্কতা উইজেটের নামের পাশেও (হোম স্ক্রিনেই চোখে পড়ে)।
    var title = acc.name;
    try {
      if (SpendingGuard.enabled) {
        final g = await SpendingGuard.assess();
        if (g.level == GuardLevel.danger) {
          title = '$title 🚨 জরুরির টাকা নেই!';
        } else if (g.level == GuardLevel.near) {
          title = '$title ⚠️ সাবধান';
        }
      }
    } catch (_) {}
    await HomeWidget.saveWidgetData<String>('cb_title', title);
    await HomeWidget.saveWidgetData<String>('cb_balance', _money(balance));
    await HomeWidget.saveWidgetData<String>('cb_income', _money(income));
    await HomeWidget.saveWidgetData<String>('cb_expense', _money(expense));
    await HomeWidget.saveWidgetData<String>('cb_month_key', monthKey);
    await HomeWidget.updateWidget(name: providerName);
  }
}
