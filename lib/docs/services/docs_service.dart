import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../reminder/db/reminder_db.dart';
import '../../reminder/models/reminder.dart';
import '../../reminder/services/reminder_service.dart';
import '../db/docs_db.dart';
import '../models/doc_models.dart';
import 'docs_crypto.dart';

/// নতুন যোগ হতে যাওয়া একটা পাতা (ছবি/PDF) — সেভের সময় এনক্রিপ্ট হয়ে ফাইলে যায়।
class NewDocPage {
  final Uint8List bytes;
  final String name;
  final String mime;
  NewDocPage(this.bytes, this.name, this.mime);
}

class DocsService {
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static Future<List<VaultDoc>> list() => DocsDB.all();

  static String newId() => 'd_${DateTime.now().microsecondsSinceEpoch}';

  /// [number] নতুন নম্বর (সাধারণ লেখা) — null হলে আগেরটাই থাকে।
  /// [removed] এডিটে বাদ দেওয়া পাতা; [added] নতুন পাতা।
  static Future<void> save(
    VaultDoc doc, {
    String? number,
    List<NewDocPage> added = const [],
    List<DocPage> removed = const [],
  }) async {
    if (number != null) doc.numberEnc = await DocsCrypto.encryptText(number);

    for (final p in removed) {
      await DocsCrypto.deleteFile(p.fileId);
      doc.pages.removeWhere((x) => x.fileId == p.fileId);
    }
    for (final a in added) {
      final id = await DocsCrypto.saveFile(a.bytes);
      doc.pages.add(DocPage(id, a.name, a.mime, a.bytes.length));
    }

    doc.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _syncReminders(doc);
    await DocsDB.upsert(doc);
    changes.value++;
  }

  static Future<void> delete(VaultDoc doc) async {
    for (final p in doc.pages) {
      await DocsCrypto.deleteFile(p.fileId);
    }
    await _deleteReminders(doc.rem);
    await DocsDB.delete(doc.id);
    changes.value++;
  }

  static Future<String> numberOf(VaultDoc d) => DocsCrypto.decryptText(d.numberEnc);

  // ── মেয়াদের রিমাইন্ডার: ৯০, ৩০, ৭ দিন আগে ও শেষ দিনে (সকাল ৮টা) ──

  static Future<void> _deleteReminders(List<int> ids) async {
    for (final id in ids) {
      try {
        await ReminderService.delete(id);
      } catch (_) {}
    }
  }

  static Future<void> _syncReminders(VaultDoc d) async {
    await _deleteReminders(d.rem);
    d.rem = [];
    if (d.expiry == null) return;
    final today = dateOnly(DateTime.now());
    final exp = dateOnly(d.expiry!);
    for (final off in const [90, 30, 7, 0]) {
      final day = exp.subtract(Duration(days: off));
      if (day.isBefore(today)) continue;
      final title = off == 0
          ? '🚨 আজ ${d.title}-এর মেয়াদ শেষ!'
          : '📄 ${d.title}-এর মেয়াদ শেষ হতে ${bn(off)} দিন বাকি';
      final r = Reminder(
        title: title,
        note: 'মেয়াদ শেষ: ${formatDateBn(exp)} — নবায়নের প্রস্তুতি নাও',
        kind: 'plan',
        date: day,
        times: ['08:00'],
      );
      r.id = await ReminderDB.insert(r);
      await ReminderService.rearm(r);
      d.rem.add(r.id!);
    }
    ReminderService.changes.value++;
  }

  /// মেয়াদ [days] দিনের মধ্যে শেষ হবে বা শেষ হয়ে গেছে এমন ডকুমেন্ট।
  static Future<List<VaultDoc>> expiringWithin(int days) async {
    final all = await DocsDB.all();
    final out = all.where((d) => d.daysToExpiry != null && d.daysToExpiry! <= days).toList()
      ..sort((a, b) => a.daysToExpiry!.compareTo(b.daysToExpiry!));
    return out;
  }
}
