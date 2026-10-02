import '../cashbook/db/cashbook_db.dart';
import '../docs/db/docs_db.dart';
import '../cashbook/services/cashbook_service.dart';
import '../db/db_helper.dart';
import '../family/db/family_db.dart';
import '../family/models/family_models.dart';
import '../jobs/db/job_db.dart';
import '../jobs/models/job_models.dart';
import '../jobs/services/job_service.dart';
import '../reminder/db/reminder_db.dart';
import '../reminder/models/reminder.dart';
import '../services/settings_service.dart';
import '../services/vault_backup_service.dart';
import '../services/vault_service.dart';

/// আইটেমটা ট্যাপ করলে কোন মডিউলে যাবে।
enum TodayTarget { reminders, jobs, familyBills, familyDates, cashbook, projects, backup, docs }

class TodayItem {
  final String emoji;
  final String title;
  final String sub;

  /// ২ = জরুরি/আজ, ১ = শিগগির, ০ = শুধু তথ্য
  final int level;
  final TodayTarget target;
  const TodayItem(this.emoji, this.title, this.sub, this.level, this.target);
}

class TodaySummary {
  final DateTime asOf;
  final List<TodayItem> items;
  TodaySummary(this.asOf, this.items);

  List<TodayItem> at(int level) => items.where((i) => i.level == level).toList();
  int get urgentCount => at(2).length;
  int get soonCount => at(1).length;

  /// সকালের নোটিফিকেশন পাঠানোর মতো কিছু আছে কিনা (শুধু তথ্য-আইটেমে বিরক্ত করে না)।
  bool get worthNotifying => urgentCount + soonCount > 0;

  static String greeting(int hour) {
    if (hour >= 4 && hour < 12) return 'সুপ্রভাত ☀️';
    if (hour >= 12 && hour < 16) return 'শুভ দুপুর 🌤️';
    if (hour >= 16 && hour < 19) return 'শুভ বিকাল 🌇';
    if (hour >= 19 && hour < 22) return 'শুভ সন্ধ্যা 🌙';
    return 'শুভ রাত্রি 🌙';
  }

  /// নোটিফিকেশনের ছোট লাইন (প্রথম [max] টা, বাকিটা "+N")।
  String notificationBody({int max = 6}) {
    final act = items.where((i) => i.level >= 1).toList();
    final lines = act.take(max).map((i) => '${i.emoji} ${i.title}${i.sub.isNotEmpty ? ' — ${i.sub}' : ''}').toList();
    if (act.length > max) lines.add('+ আরও ${bn(act.length - max)} টা');
    return lines.join('\n');
  }

  String get notificationShort {
    final parts = <String>[];
    if (urgentCount > 0) parts.add('${bn(urgentCount)} টা জরুরি');
    if (soonCount > 0) parts.add('${bn(soonCount)} টা আসছে');
    return parts.join(' · ');
  }
}

/// সব মডিউল থেকে "আজ কী কী গুরুত্বপূর্ণ" জড়ো করে একটা তালিকা বানায়।
/// প্রতিটা মডিউল আলাদা try/catch-এ — একটা ভাঙলে বাকিগুলো ঠিকঠাক আসে।
class TodayService {
  static String _money(double v) {
    final n = v.round().abs();
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i != 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${v < 0 ? '-' : ''}৳${bn(b.toString())}';
  }

  static String _dLabel(int d, {String zero = 'আজ', String one = 'কাল'}) =>
      d < 0 ? '${bn(-d)} দিন আগে' : (d == 0 ? zero : (d == 1 ? one : 'আর ${bn(d)} দিন'));

  /// [asOf] দিলে সেই দিনের হিসাবে (সকালের নোটিফিকেশন আগের রাতে বানানো হলে
  /// "আর ৩ দিন" যেন সকালে "আর ২ দিন" হয়ে যায়)। ডিফল্ট: আজ।
  static Future<TodaySummary> build({DateTime? asOf, bool includeBackupHints = true}) async {
    final now = DateTime.now();
    final day = dateOnly(asOf ?? now);
    final isToday = day == dateOnly(now);
    final items = <TodayItem>[];

    Future<void> safe(Future<void> Function() f) async {
      try {
        await f();
      } catch (_) {}
    }

    await safe(() => _reminders(items, day));
    await safe(() => _jobs(items, day));
    await safe(() => _family(items, day));
    await safe(() => _cashbook(items, day, isToday));
    await safe(() => _projects(items, day));
    await safe(() => _docs(items, day));
    if (includeBackupHints) await safe(() => _backupHints(items));

    // স্থিতিশীল সাজানো: জরুরি → শিগগির → তথ্য।
    final ordered = <TodayItem>[
      ...items.where((i) => i.level == 2),
      ...items.where((i) => i.level == 1),
      ...items.where((i) => i.level == 0),
    ];
    return TodaySummary(day, ordered);
  }

  // ───────────────── রিমাইন্ডার ─────────────────

  /// অন্য মডিউল (চাকরি/পরিবার) নিজেরা যেসব রিমাইন্ডার বানায় সেগুলো আলাদা
  /// আইটেম হিসেবেই আসে — এখানে দ্বিতীয়বার দেখালে ডুপ্লিকেট হতো।
  static Future<Set<int>> managedReminderIds({bool includeWeekly = false}) async {
    final s = <int>{};
    try {
      for (final c in await JobDB.all()) {
        s.addAll(c.deadlineRem);
        s.addAll(c.examRem);
      }
    } catch (_) {}
    try {
      for (final m in await FamilyDB.members()) {
        s.addAll(m.bdayRem);
      }
      for (final d in await FamilyDB.dates()) {
        s.addAll(d.rem);
      }
      for (final b in await FamilyDB.bills()) {
        s.addAll(b.rem);
      }
    } catch (_) {}
    try {
      for (final d in await DocsDB.all()) {
        s.addAll(d.rem);
      }
    } catch (_) {}
    if (includeWeekly) {
      // চাকরি হাবের "সাপ্তাহিক রিভিউ" রিমাইন্ডার।
      final w = SettingsService.getInt('job_weekly_rem', defaultValue: 0);
      if (w != 0) s.add(w);
    }
    return s;
  }

  static Future<void> _reminders(List<TodayItem> out, DateTime day) async {
    final all = await ReminderDB.all();
    final managed = await managedReminderIds();
    final mine = all.where((r) => r.id == null || !managed.contains(r.id)).toList();

    final overdue = mine.where((r) => r.isOverdue(day)).toList();
    for (final r in overdue.take(3)) {
      out.add(TodayItem('⏰', r.title, 'বাকি পড়ে আছে · ${formatDateBn(r.date, now: day)}', 2, TodayTarget.reminders));
    }
    if (overdue.length > 3) {
      out.add(TodayItem('⏰', 'আরও ${bn(overdue.length - 3)} টা পুরোনো রিমাইন্ডার বাকি', '', 2, TodayTarget.reminders));
    }

    final due = mine.where((r) => r.isDueToday(day)).toList()
      ..sort((a, b) => (a.times.isEmpty ? '99:99' : a.times.first).compareTo(b.times.isEmpty ? '99:99' : b.times.first));
    for (final r in due.take(5)) {
      out.add(TodayItem('🔔', r.title, r.times.map(formatTimeBn).join(', '), 2, TodayTarget.reminders));
    }
    if (due.length > 5) {
      out.add(TodayItem('🔔', 'আজকের আরও ${bn(due.length - 5)} টা রিমাইন্ডার', '', 2, TodayTarget.reminders));
    }
  }

  // ───────────────── চাকরি ─────────────────

  static Future<void> _jobs(List<TodayItem> out, DateTime day) async {
    final list = await JobService.circulars();
    for (final Circular c in list) {
      final label = c.post.isNotEmpty ? '${c.title} (${c.post})' : c.title;
      if (c.status == 'watching' && c.deadline != null) {
        final d = dateOnly(c.deadline!).difference(day).inDays;
        if (d >= 0 && d <= 7) {
          out.add(TodayItem('📨', label,
              'আবেদনের ${d == 0 ? 'আজই শেষ দিন!' : (d == 1 ? 'শেষ কাল' : 'শেষ আর ${bn(d)} দিন')}'
              '${c.fee > 0 ? ' · ফি ৳${bn(c.fee)}' : ''}',
              d <= 1 ? 2 : 1, TodayTarget.jobs));
        }
      }
      if (c.examDate != null && c.status != 'closed' && c.status != 'result') {
        final d = dateOnly(c.examDate!).difference(day).inDays;
        if (d >= 0 && d <= 7) {
          out.add(TodayItem('📝', label, 'পরীক্ষা ${d == 0 ? 'আজ!' : (d == 1 ? 'কাল' : 'আর ${bn(d)} দিন')}',
              d <= 1 ? 2 : 1, TodayTarget.jobs));
        }
      }
    }
    final ageOut = JobService.ageOut;
    if (ageOut != null) {
      final d = dateOnly(ageOut).difference(day).inDays;
      if (d >= 0 && d <= 90) {
        out.add(TodayItem('⏳', 'বয়সসীমা শেষ হতে আর ${bn(d)} দিন', 'যত তাড়াতাড়ি সম্ভব আবেদন করো', d <= 30 ? 1 : 0, TodayTarget.jobs));
      }
    }
    final exam = JobService.examDate;
    if (exam != null) {
      final d = dateOnly(exam).difference(day).inDays;
      final name = JobService.examName.isEmpty ? 'টার্গেট পরীক্ষা' : JobService.examName;
      if (d >= 0 && d <= 60) {
        out.add(TodayItem('🎯', '$name — আর ${bn(d)} দিন', d <= 7 ? 'শেষ মুহূর্তের রিভিশন' : 'প্রস্তুতি চলুক', d <= 7 ? 1 : 0, TodayTarget.jobs));
      }
    }
  }

  // ───────────────── পরিবার ─────────────────

  static Future<void> _family(List<TodayItem> out, DateTime day) async {
    final bills = await FamilyDB.bills();
    final monthKey = FamilyBill.monthKey(day);
    for (final b in bills) {
      if (b.lastPaidMonth == monthKey) continue;
      final due = DateTime(day.year, day.month, b.dueDay);
      final d = due.difference(day).inDays;
      if (d <= 3) {
        out.add(TodayItem(b.emoji, b.title,
            '${d < 0 ? '${bn(-d)} দিন বকেয়া' : (d == 0 ? 'আজ শেষ দিন' : 'আর ${bn(d)} দিন')}'
            '${b.amount > 0 ? ' · ৳${bn(b.amount)}' : ''}',
            d <= 0 ? 2 : 1, TodayTarget.familyBills));
      }
    }

    final members = await FamilyDB.members();
    final dates = await FamilyDB.dates();
    for (final m in members) {
      if (m.birthDate == null) continue;
      final next = nextOccurrence(m.birthDate!, from: day);
      final d = next.difference(day).inDays;
      if (d <= 7) {
        out.add(TodayItem('🎂', '${m.name}-এর জন্মদিন', _dLabel(d), d == 0 ? 2 : 1, TodayTarget.familyDates));
      }
    }
    for (final fd in dates) {
      final next = nextOccurrence(fd.date, from: day);
      final d = next.difference(day).inDays;
      if (d <= 7) {
        out.add(TodayItem(fd.emoji, fd.title, _dLabel(d), d == 0 ? 2 : 1, TodayTarget.familyDates));
      }
    }
  }

  // ───────────────── ক্যাশবুক ─────────────────

  static Future<void> _cashbook(List<TodayItem> out, DateTime day, bool isToday) async {
    // বাজেট/মাসের হিসাব চলতি মাসের — অন্য দিনের জন্য বানানো সারসংক্ষেপে বাদ।
    if (!isToday) return;

    final budgets = await CashbookDB.getBudgets();
    for (final b in budgets) {
      if (b.monthlyLimit <= 0) continue;
      final spent = await CashbookDB.spentThisMonth(b.category);
      final pct = spent / b.monthlyLimit;
      if (pct >= 0.8) {
        final cat = CashbookService.categoryById(b.category);
        out.add(TodayItem(
          pct >= 1 ? '🚨' : '⚠️',
          '${cat.icon} ${cat.name} বাজেট ${pct >= 1 ? 'পেরিয়ে গেছে' : '${bn((pct * 100).round())}% শেষ'}',
          '${_money(spent)} / ${_money(b.monthlyLimit)}',
          pct >= 1 ? 2 : 1,
          TodayTarget.cashbook,
        ));
      }
    }

    final acc = await CashbookDB.currentMonthAccount();
    final entries = await CashbookDB.getEntries(accountId: acc.id);
    if (entries.isNotEmpty) {
      final mk = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}';
      double bal = 0, inc = 0, exp = 0;
      for (final e in entries) {
        final isIn = e.type == 'in';
        bal += isIn ? e.amount : -e.amount;
        if (e.date.startsWith(mk)) {
          if (isIn) {
            inc += e.amount;
          } else {
            exp += e.amount;
          }
        }
      }
      out.add(TodayItem('📒', 'এ মাসে ব্যালেন্স ${_money(bal)}',
          'জমা ${_money(inc)} · খরচ ${_money(exp)}', 0, TodayTarget.cashbook));
    }

    double lend = 0, borrow = 0;
    for (final d in await CashbookDB.getDebts()) {
      if (d.cleared) continue;
      if (d.type == 'lend') {
        lend += d.amount;
      } else {
        borrow += d.amount;
      }
    }
    if (lend > 0 || borrow > 0) {
      out.add(TodayItem('🤝', 'পাওনা ${_money(lend)} · দেনা ${_money(borrow)}',
          'নিট ${lend >= borrow ? 'আমি পাবো' : 'আমি দেবো'} ${_money((lend - borrow).abs())}', 0, TodayTarget.cashbook));
    }
  }

  // ───────────────── প্রজেক্ট ─────────────────

  static Future<void> _projects(List<TodayItem> out, DateTime day) async {
    final ideas = await DBHelper.getAllActiveIdeas();
    final active = ideas.where((i) => i.status != 'done').toList();
    if (active.isEmpty) return;
    final dayMs = day.millisecondsSinceEpoch;
    final overdue = active.where((i) => i.deadline != null && i.deadline! < dayMs).length;
    final soon = active.where((i) =>
        i.deadline != null && i.deadline! >= dayMs && i.deadline! < dayMs + 2 * 86400000).length;
    if (overdue > 0) {
      out.add(TodayItem('📌', '${bn(overdue)} টা প্রজেক্ট টাস্ক ওভারডিউ', 'সময় পেরিয়ে গেছে', 2, TodayTarget.projects));
    }
    if (soon > 0) {
      out.add(TodayItem('📌', '${bn(soon)} টা টাস্কের ডেডলাইন আজ-কালের মধ্যে', '', 1, TodayTarget.projects));
    }
    out.add(TodayItem('📋', '${bn(active.length)} টা প্রজেক্ট টাস্ক চলমান', '', 1, TodayTarget.projects));
  }

  // ───────────────── ডকুমেন্ট ─────────────────

  /// মেয়াদ শেষ হয়ে গেছে বা ৩০ দিনের মধ্যে শেষ হবে এমন ডকুমেন্ট।
  static Future<void> _docs(List<TodayItem> out, DateTime day) async {
    final all = await DocsDB.all();
    final list = all.where((d) => d.expiry != null).toList()
      ..sort((a, b) => a.expiry!.compareTo(b.expiry!));
    var shown = 0;
    for (final d in list) {
      final n = dateOnly(d.expiry!).difference(day).inDays;
      if (n > 30 || shown >= 4) continue;
      shown++;
      out.add(TodayItem(
        '📄',
        '${d.title}-এর মেয়াদ ${n < 0 ? '${bn(-n)} দিন আগে শেষ হয়েছে' : (n == 0 ? 'আজ শেষ!' : 'আর ${bn(n)} দিনে শেষ')}',
        'নবায়নের ব্যবস্থা নাও',
        n <= 7 ? 2 : 1,
        TodayTarget.docs,
      ));
    }
  }

  // ───────────────── ব্যাকআপ স্মরণ ─────────────────

  /// শুধু স্থানীয়ভাবে জানা যায় এমন সতর্কতা (ভল্ট): ব্যাকআপ নেই বা ৩০ দিনের বেশি পুরোনো।
  /// ভল্টের পাসওয়ার্ড হারালে ফেরত আনার উপায় নেই, তাই এটাই সবচেয়ে গুরুত্বপূর্ণ।
  static Future<void> _backupHints(List<TodayItem> out) async {
    final vault = await VaultService.getAll();
    if (vault.isEmpty) return;
    final ms = VaultBackupService.lastBackupMs();
    if (ms == 0) {
      out.add(const TodayItem('🔐', 'ভল্টের কোনো ব্যাকআপ নেই',
          'ফোন হারালে বা রিসেট হলে সব পাসওয়ার্ড চলে যাবে', 1, TodayTarget.backup));
      return;
    }
    final days = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)).inDays;
    if (days >= 30) {
      out.add(TodayItem('🔐', 'ভল্টের শেষ ব্যাকআপ ${bn(days)} দিন আগের',
          'নতুন পাসওয়ার্ড যোগ হয়ে থাকলে আবার ব্যাকআপ নাও', 1, TodayTarget.backup));
    }
  }
}
