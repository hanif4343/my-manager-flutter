import 'package:flutter/foundation.dart';
import '../../family/db/family_db.dart';
import '../../family/models/family_models.dart';
import '../../reminder/models/reminder.dart' show bn, dateOnly;
import '../../services/settings_service.dart';
import '../db/cashbook_db.dart';
import '../models/cashbook_category.dart';
import 'cashbook_notification_service.dart';
import 'cashbook_service.dart';

enum GuardLevel { ok, near, danger }

class BudgetAlert {
  final CashbookCategory cat;
  final double spent;
  final double limit;
  BudgetAlert(this.cat, this.spent, this.limit);
  double get pct => limit <= 0 ? 0 : spent / limit;
  GuardLevel get level => pct >= 1.0 ? GuardLevel.danger : GuardLevel.near;
}

String _money(double v) {
  final n = v.round().abs();
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i != 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}৳${bn(b.toString())}';
}

class GuardReport {
  final double balance; // চলতি মাসের খাতার ব্যালেন্স (প্রস্তাবিত খরচ বাদ দিয়ে)
  final double reserved; // এ মাসে বাকি অতীব জরুরি: অপরিশোধিত বিল ও কিস্তি
  final List<FamilyBill> unpaid;
  final List<BudgetAlert> budgets;
  final double margin; // "কাছাকাছি" ধরার সীমা
  GuardReport(this.balance, this.reserved, this.unpaid, this.budgets, this.margin);

  /// জরুরি খরচ মেটানোর পরে হাতে থাকবে কত — এটাই "নিরাপদ খরচের" সীমা।
  double get free => balance - reserved;

  GuardLevel get essentialsLevel {
    if (reserved <= 0) return GuardLevel.ok;
    if (free < 0) return GuardLevel.danger;
    if (free < margin) return GuardLevel.near;
    return GuardLevel.ok;
  }

  GuardLevel get budgetLevel {
    var l = GuardLevel.ok;
    for (final b in budgets) {
      if (b.level == GuardLevel.danger) return GuardLevel.danger;
      l = GuardLevel.near;
    }
    return l;
  }

  GuardLevel get level =>
      essentialsLevel.index >= budgetLevel.index ? essentialsLevel : budgetLevel;

  String get headline {
    if (essentialsLevel == GuardLevel.danger) return '🚨 জরুরি খরচের টাকাই নেই!';
    final over = budgets.where((b) => b.level == GuardLevel.danger).toList();
    if (over.isNotEmpty) return '🚨 ${over.first.cat.name} বাজেট পেরিয়ে গেছে!';
    if (essentialsLevel == GuardLevel.near) return '⚠️ জরুরি খরচের টাকা প্রায় শেষ!';
    if (budgets.isNotEmpty) return '⚠️ ${budgets.first.cat.name} বাজেট প্রায় শেষ';
    return '✅ সব ঠিক আছে';
  }

  /// এক লাইনের সারসংক্ষেপ
  String get essentialsLine => reserved > 0
      ? 'ব্যালেন্স ${_money(balance)} · বাকি জরুরি (বিল/কিস্তি) ${_money(reserved)} → নিরাপদ খরচ ${_money(free)}'
      : 'ব্যালেন্স ${_money(balance)} · এ মাসের কোনো জরুরি বিল বাকি নেই';

  /// বিস্তারিত লাইন: অপরিশোধিত বিল, বাজেট পেরোনো খাত
  List<String> get detailLines {
    final out = <String>[];
    final now = dateOnly(DateTime.now());
    for (final b in unpaid.take(5)) {
      final due = DateTime(now.year, now.month, b.dueDay);
      final d = due.difference(now).inDays;
      final when = d < 0 ? '${bn(-d)} দিন বকেয়া' : (d == 0 ? 'আজই শেষ দিন' : 'আর ${bn(d)} দিন');
      out.add('${b.emoji} ${b.title} ${_money(b.amount.toDouble())} ($when)');
    }
    for (final b in budgets) {
      out.add('${b.cat.icon} ${b.cat.name}: ${bn((b.pct * 100).round())}% খরচ (${_money(b.spent)} / ${_money(b.limit)})');
    }
    return out;
  }

  /// নোটিফিকেশনের বডি
  String get notificationBody {
    final lines = <String>[essentialsLine, ...detailLines.take(4).map((e) => '• $e')];
    lines.add('এখন শুধু যা না করলেই নয় সেটাই খরচ করো। অকারণ খরচ আজ বাদ দাও।');
    return lines.join('\n');
  }
}

/// "খরচ-প্রহরী": জরুরি খরচ (বিল ও কিস্তি) মেটানোর টাকা থাকবে কিনা আর কোন খাতে বাজেটের
/// কত % গেল — দেখে কাছাকাছি গেলে বড় লাল সতর্কতা দেয় (ক্যাশবুকের উপরে, খরচ লেখার সময়,
/// আর নির্দিষ্ট ব্যবধানে নোটিফিকেশনে বারবার)।
class SpendingGuard {
  static final ValueNotifier<int> changes = ValueNotifier(0);

  // ── সেটিংস ──
  static bool get enabled => SettingsService.getBool('guard_on', defaultValue: true);
  static int get marginPct => SettingsService.getInt('guard_margin_pct', defaultValue: 30);
  static int get nagMinutes => SettingsService.getInt('guard_nag_min', defaultValue: 120);

  static Future<void> saveSettings({bool? on, int? margin, int? nag}) async {
    if (on != null) await SettingsService.setBool('guard_on', on);
    if (margin != null) await SettingsService.setInt('guard_margin_pct', margin);
    if (nag != null) await SettingsService.setInt('guard_nag_min', nag);
    changes.value++;
  }

  /// জরুরি ক্যাটাগরি — এতে খরচ করলে সতর্কতা দেখানো হয় না (বিল দেওয়াই তো কাজ)।
  static bool isEssentialCategory(String id) => id == 'bill';

  /// [extraSpend]: এখনই যে খরচটা করতে যাচ্ছ তার প্রভাব ধরে হিসাব ("এটা করলে কী হবে")।
  static Future<GuardReport> assess({double extraSpend = 0, String? category}) async {
    final acc = await CashbookDB.currentMonthAccount();
    final entries = await CashbookDB.getEntries(accountId: acc.id);
    var balance = 0.0;
    for (final e in entries) {
      balance += e.type == 'in' ? e.amount : -e.amount;
    }
    balance -= extraSpend;

    // বাকি জরুরি: এ মাসে অপরিশোধিত বিল/কিস্তি।
    final now = DateTime.now();
    final mk = FamilyBill.monthKey(now);
    final unpaid = <FamilyBill>[];
    var reserved = 0.0;
    try {
      for (final b in await FamilyDB.bills()) {
        if (b.lastPaidMonth == mk || b.amount <= 0) continue;
        unpaid.add(b);
        reserved += b.amount;
      }
    } catch (_) {}
    unpaid.sort((a, b) => a.dueDay.compareTo(b.dueDay));

    // বাজেট ≥ ৮০% (প্রস্তাবিত খরচসহ)।
    final alerts = <BudgetAlert>[];
    try {
      for (final b in await CashbookDB.getBudgets()) {
        if (b.monthlyLimit <= 0) continue;
        var spent = await CashbookDB.spentThisMonth(b.category);
        if (category != null && b.category == category) spent += extraSpend;
        final a = BudgetAlert(CashbookService.categoryById(b.category), spent, b.monthlyLimit);
        if (a.pct >= 0.8) alerts.add(a);
      }
    } catch (_) {}
    alerts.sort((a, b) => b.pct.compareTo(a.pct));

    final margin = reserved * marginPct / 100 < 500 ? 500.0 : reserved * marginPct / 100;
    return GuardReport(balance, reserved, unpaid, alerts, margin);
  }

  // ───────────── বারবার নোটিফিকেশন ─────────────

  /// সকাল ৮টা–রাত ১০টায়, সতর্কতার অবস্থায় থাকলে নির্দিষ্ট ব্যবধানে লাল নোটিফিকেশন।
  /// ব্যাকগ্রাউন্ড টাস্ক (প্রতি ~৩০ মিনিটে), অ্যাপ চালু ও রিজিউমে ডাকা হয়।
  /// danger-এ ব্যবধান অর্ধেক, তাই জরুরি অবস্থায় আরও ঘনঘন বলে।
  static Future<void> nudgeIfNeeded({bool force = false}) async {
    if (!enabled && !force) return;
    final now = DateTime.now();
    if (!force && (now.hour < 8 || now.hour >= 22)) return;

    final r = await assess();
    if (r.level == GuardLevel.ok && !force) return;

    final last = SettingsService.getInt('guard_last_nudge_ms', defaultValue: 0);
    final interval = (r.level == GuardLevel.danger ? (nagMinutes ~/ 2).clamp(30, 600) : nagMinutes) * 60000;
    if (!force && now.millisecondsSinceEpoch - last < interval) return;

    await CashbookNotificationService.showGuardNudge(
      title: r.level == GuardLevel.ok ? '✅ খরচ-প্রহরী পরীক্ষা: সব ঠিক আছে' : r.headline,
      body: r.notificationBody,
      danger: r.level == GuardLevel.danger,
    );
    await SettingsService.setInt('guard_last_nudge_ms', now.millisecondsSinceEpoch);
  }
}
