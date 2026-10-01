import 'package:flutter/foundation.dart';
import '../../cashbook/db/cashbook_db.dart';
import '../../cashbook/models/cashbook_account.dart';
import '../../cashbook/models/cashbook_entry.dart';
import '../../cashbook/services/cashbook_service.dart';
import '../../reminder/db/reminder_db.dart';
import '../../reminder/models/reminder.dart';
import '../../reminder/services/reminder_service.dart';
import '../db/family_db.dart';
import '../models/family_models.dart';
import 'family_backup_service.dart';

/// আসন্ন তারিখের একটা সারি (জন্মদিন বা বার্ষিকী)।
class UpcomingItem {
  final String emoji;
  final String title;
  final String sub;
  final DateTime next;
  final int daysLeft;
  final bool isBirthday;
  final FamilyDate? date; // নিজের বানানো তারিখ হলে
  UpcomingItem({
    required this.emoji,
    required this.title,
    required this.sub,
    required this.next,
    required this.daysLeft,
    required this.isBirthday,
    this.date,
  });
}

/// পরিবার মডিউলের লজিক। সব রিমাইন্ডার বিদ্যমান রিমাইন্ডার ইঞ্জিনে তৈরি হয়
/// (নোটিফিকেশন, Done/Not yet, স্নুজ সহ) — রিমাইন্ডার স্ক্রিনেও দেখা যায়।
class FamilyService {
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static void _notify() {
    changes.value++;
    FamilyBackupService.backupSilently();
  }

  // ───────────────────────── রিমাইন্ডার সহায়ক ─────────────────────────

  static Future<int> _mk(String title, String note, DateTime date, String repeat,
      {List<String> times = const ['08:00']}) async {
    final r = Reminder(
      title: title,
      note: note,
      kind: 'plan',
      date: date,
      times: List<String>.from(times),
      repeat: repeat,
    );
    r.id = await ReminderDB.insert(r);
    await ReminderService.rearm(r);
    ReminderService.changes.value++;
    return r.id!;
  }

  static Future<void> _deleteReminders(List<int> ids) async {
    for (final id in ids) {
      try {
        await ReminderService.delete(id);
      } catch (_) {}
    }
  }

  /// বার্ষিক ইভেন্টের জন্য ৩টা বছর-রিপিট রিমাইন্ডার: ৭ দিন আগে, ১ দিন আগে,
  /// আর ওই দিন সকাল ৮টায়। (লিপ-ইয়ারে ফেব্রুয়ারি-মার্চের কাছাকাছি তারিখে
  /// "আগে"-র রিমাইন্ডার একদিন এদিক-ওদিক হতে পারে।)
  static Future<List<int>> _annual(DateTime event, String emoji, String label, String note) async {
    final next = nextOccurrence(event);
    final ids = <int>[];
    final specs = <(int, String)>[
      (7, '$emoji $label — ৭ দিন বাকি'),
      (1, '$emoji কাল $label'),
      (0, '$emoji আজ $label'),
    ];
    for (final (off, title) in specs) {
      final base = next.subtract(Duration(days: off));
      ids.add(await _mk(title, note, base, 'yearly'));
    }
    return ids;
  }

  // ───────────────────────── সদস্য ─────────────────────────

  static Future<List<FamilyMember>> members() => FamilyDB.members();

  static Future<void> saveMember(FamilyMember m) async {
    if (m.id == null) {
      m.id = await FamilyDB.insertMember(m);
    }
    await _deleteReminders(m.bdayRem);
    m.bdayRem = [];
    if (m.birthDate != null) {
      m.bdayRem = await _annual(m.birthDate!, '🎂', '${m.name}-এর জন্মদিন',
          'জন্মতারিখ ${formatDateBn(m.birthDate!)}${m.phone.isNotEmpty ? '\nফোন: ${m.phone}' : ''}');
    }
    await FamilyDB.updateMember(m);
    _notify();
  }

  static Future<void> deleteMember(FamilyMember m) async {
    await _deleteReminders(m.bdayRem);
    if (m.id != null) await FamilyDB.deleteMember(m.id!);
    _notify();
  }

  // ───────────────────────── গুরুত্বপূর্ণ তারিখ ─────────────────────────

  static Future<List<FamilyDate>> dates() => FamilyDB.dates();

  static Future<void> saveDate(FamilyDate d) async {
    if (d.id == null) {
      d.id = await FamilyDB.insertDate(d);
    }
    await _deleteReminders(d.rem);
    d.rem = await _annual(d.date, d.emoji, d.title, d.note);
    await FamilyDB.updateDate(d);
    _notify();
  }

  static Future<void> deleteDate(FamilyDate d) async {
    await _deleteReminders(d.rem);
    if (d.id != null) await FamilyDB.deleteDate(d.id!);
    _notify();
  }

  /// সব জন্মদিন + নিজের বানানো তারিখ, কাছেরটা আগে।
  static Future<List<UpcomingItem>> upcoming() async {
    final members = await FamilyDB.members();
    final dates = await FamilyDB.dates();
    final out = <UpcomingItem>[];
    for (final m in members) {
      if (m.birthDate == null) continue;
      final next = nextOccurrence(m.birthDate!);
      out.add(UpcomingItem(
        emoji: '🎂',
        title: '${m.name}-এর জন্মদিন',
        sub: '${bn(m.turningAge ?? 0)} বছর পূর্ণ হবে · ${m.relation}',
        next: next,
        daysLeft: daysUntil(next),
        isBirthday: true,
      ));
    }
    for (final d in dates) {
      final next = nextOccurrence(d.date);
      final n = next.year - d.date.year;
      out.add(UpcomingItem(
        emoji: d.emoji,
        title: d.title,
        sub: n > 0 ? '${bn(n)}তম বছর · মূল তারিখ ${formatDateBn(d.date)}' : formatDateBn(d.date),
        next: next,
        daysLeft: daysUntil(next),
        isBirthday: false,
        date: d,
      ));
    }
    out.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return out;
  }

  // ───────────────────────── নিয়মিত বিল ─────────────────────────

  static Future<List<FamilyBill>> bills() => FamilyDB.bills();

  /// প্রতি মাসের ডিউ ডেটে সকাল ৮টায় একটা, আর ৩ দিন আগে (মাসের ১ তারিখের
  /// নিচে নামলে ১ তারিখে) আরেকটা রিমাইন্ডার।
  static Future<void> saveBill(FamilyBill b) async {
    if (b.id == null) {
      b.id = await FamilyDB.insertBill(b);
    }
    await _deleteReminders(b.rem);
    b.rem = [];
    final now = DateTime.now();
    final amt = b.amount > 0 ? ' (≈ ৳${bn(b.amount)})' : '';
    final advanceDay = (b.dueDay - 3) < 1 ? 1 : b.dueDay - 3;
    if (advanceDay != b.dueDay) {
      b.rem.add(await _mk(
        '⏳ ${b.title} পরিশোধের সময় ঘনিয়ে এসেছে$amt',
        'মাসের ${bn(b.dueDay)} তারিখের মধ্যে দিতে হবে${b.note.isNotEmpty ? '\n${b.note}' : ''}',
        DateTime(now.year, now.month, advanceDay),
        'monthly',
      ));
    }
    b.rem.add(await _mk(
      '🧾 আজ ${b.title} পরিশোধের শেষ দিন$amt',
      b.note,
      DateTime(now.year, now.month, b.dueDay),
      'monthly',
    ));
    await FamilyDB.updateBill(b);
    _notify();
  }

  static Future<void> deleteBill(FamilyBill b) async {
    await _deleteReminders(b.rem);
    if (b.id != null) await FamilyDB.deleteBill(b.id!);
    _notify();
  }

  static Future<List<CashbookAccount>> cashbookAccounts() => CashbookDB.getAccounts();
  static int? get lastCashbookAccountId => CashbookService.lastAccountId;

  /// "পরিশোধ করেছি": ক্যাশবুকে খরচ যোগ + এই মাসের বাকি রিমাইন্ডার চুপ।
  static Future<void> payBill(FamilyBill b, {required int amount, required int accountId}) async {
    final now = DateTime.now();
    final ms = now.millisecondsSinceEpoch;
    await CashbookDB.insertEntry(CashbookEntry(
      accountId: accountId,
      type: 'out',
      amount: amount.toDouble(),
      category: 'bill',
      note: b.title,
      date: Reminder.ymd(now),
      createdAt: ms,
      updatedAt: ms,
    ));
    await CashbookService.setLastAccountId(accountId);

    b.lastPaidMonth = FamilyBill.monthKey(now);
    if (amount > 0) b.amount = amount;

    // এই মাসের যেসব রিমাইন্ডার এখনো আসেনি সেগুলো Done — যাতে পরিশোধের পরও
    // "আজ শেষ দিন" বলে বিরক্ত না করে। পরের মাস থেকে আবার স্বাভাবিক।
    final today = dateOnly(now);
    for (final id in b.rem) {
      final r = await ReminderDB.getById(id);
      if (r == null) continue;
      final occ = DateTime(now.year, now.month, r.date.day);
      if (!occ.isBefore(today)) {
        await ReminderService.markDone(id, Reminder.ymd(occ));
      }
    }
    await FamilyDB.updateBill(b);
    _notify();
  }

  static Future<void> markUnpaid(FamilyBill b) async {
    b.lastPaidMonth = '';
    await FamilyDB.updateBill(b);
    _notify();
  }

  // ───────────────────────── জরুরি তথ্য ─────────────────────────

  static Future<List<FamilyContact>> contacts() => FamilyDB.contacts();

  static Future<void> saveContact(FamilyContact c) async {
    if (c.id == null) {
      c.id = await FamilyDB.insertContact(c);
    } else {
      await FamilyDB.updateContact(c);
    }
    _notify();
  }

  static Future<void> deleteContact(FamilyContact c) async {
    if (c.id != null) await FamilyDB.deleteContact(c.id!);
    _notify();
  }
}
