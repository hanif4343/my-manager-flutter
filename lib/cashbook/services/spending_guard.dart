import 'package:flutter/foundation.dart';
import '../../reminder/models/reminder.dart' show bn, dateOnly;
import '../../services/settings_service.dart';
import '../db/cashbook_db.dart';
import '../models/cashbook_essential.dart';
import 'cashbook_notification_service.dart';

enum GuardLevel { ok, near, danger }

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

/// খাতায় এখন কত টাকা আছে আর এ মাসের বাকি আবশ্যিক খরচ কত — তার তুলনা।
class GuardReport {
  final double balance; // চলতি মাসের খাতার ব্যালেন্স (প্রস্তাবিত খরচ বাদ দিয়ে)
  final double reserved; // এ মাসে বাকি আবশ্যিক খরচের মোট
  final List<CashbookEssential> unpaid;
  final double margin; // "কাছাকাছি" ধরার সীমা
  GuardReport(this.balance, this.reserved, this.unpaid, this.margin);

  /// আবশ্যিক খরচ মেটানোর পরে হাতে থাকবে কত — এটাই "নিরাপদ খরচের" সীমা।
  double get free => balance - reserved;

  GuardLevel get level {
    if (reserved <= 0) return GuardLevel.ok;
    if (free < 0) return GuardLevel.danger;
    if (free < margin) return GuardLevel.near;
    return GuardLevel.ok;
  }

  /// জরুরি খরচ-সতর্কতার পুরনো নাম (বাইরের কোড এটাও ব্যবহার করে)।
  GuardLevel get essentialsLevel => level;

  String get headline {
    if (level == GuardLevel.danger) return '🚨 আবশ্যিক খরচের টাকাই নেই!';
    if (level == GuardLevel.near) return '⚠️ আবশ্যিক খরচের টাকা প্রায় শেষ!';
    return '✅ সব ঠিক আছে';
  }

  /// এক লাইনের সারসংক্ষেপ
  String get essentialsLine => reserved > 0
      ? 'ব্যালেন্স ${_money(balance)} · বাকি আবশ্যিক ${_money(reserved)} → নিরাপদ খরচ ${_money(free)}'
      : 'ব্যালেন্স ${_money(balance)} · এ মাসের কোনো আবশ্যিক খরচ বাকি নেই';

  /// বিস্তারিত লাইন: বাকি আবশ্যিক খরচ (তারিখ অনুযায়ী)
  List<String> get detailLines {
    final out = <String>[];
    final now = dateOnly(DateTime.now());
    for (final e in unpaid.take(5)) {
      var when = '';
      if (e.dueDay > 0) {
        final due = DateTime(now.year, now.month, e.dueDay);
        final d = due.difference(now).inDays;
        when = d < 0 ? ' (${bn(-d)} দিন বকেয়া)' : (d == 0 ? ' (আজই শেষ দিন)' : ' (আর ${bn(d)} দিন)');
      }
      out.add('${e.title} ${_money(e.amount)}$when');
    }
    return out;
  }

  /// নোটিফিকেশনের বডি
  String get notificationBody {
    final lines = <String>[essentialsLine, ...detailLines.take(4).map((e) => '• $e')];
    lines.add('টাকা কম খরচ করুন — আবশ্যিক কাজ আগে করুন।');
    return lines.join('\n');
  }
}

/// "খরচ-প্রহরী": ক্যাশবুকে এখন যত টাকা আছে তা এ মাসের বাকি আবশ্যিক খরচের কাছাকাছি গেলে
/// বড় লাল সতর্কতা দেয় (ক্যাশবুকের উপরে, খরচ লেখার সময়, আর নির্দিষ্ট ব্যবধানে নোটিফিকেশনে)।
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

  /// আবশ্যিক ক্যাটাগরি — এতে খরচ করলে সতর্কতা দেখানো হয় না (বিল দেওয়াই তো কাজ)।
  static bool isEssentialCategory(String id) => id == 'bill';

  /// [extraSpend]: এখনই যে খরচটা করতে যাচ্ছ তার প্রভাব ধরে হিসাব ("এটা করলে কী হবে")।
  /// [category] আগের সংস্করণের সাথে মিল রাখতে আছে; এখন হিসাবে লাগে না।
  static Future<GuardReport> assess({double extraSpend = 0, String? category}) async {
    final acc = await CashbookDB.currentMonthAccount();
    final entries = await CashbookDB.getEntries(accountId: acc.id);
    var balance = 0.0;
    for (final e in entries) {
      balance += e.type == 'in' ? e.amount : -e.amount;
    }
    balance -= extraSpend;

    // বাকি আবশ্যিক: এ মাসে এখনও মেটানো হয়নি এমন সব।
    final mk = CashbookDB.todayIso().substring(0, 7);
    final unpaid = <CashbookEssential>[];
    var reserved = 0.0;
    try {
      for (final e in await CashbookDB.getEssentials()) {
        if (!e.unpaidIn(mk) || e.amount <= 0) continue;
        unpaid.add(e);
        reserved += e.amount;
      }
    } catch (_) {}
    // তারিখ আগে যেগুলোর; তারিখ ছাড়াগুলো শেষে।
    unpaid.sort((a, b) {
      final x = a.dueDay == 0 ? 99 : a.dueDay;
      final y = b.dueDay == 0 ? 99 : b.dueDay;
      return x.compareTo(y);
    });

    final margin = reserved * marginPct / 100 < 500 ? 500.0 : reserved * marginPct / 100;
    return GuardReport(balance, reserved, unpaid, margin);
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
